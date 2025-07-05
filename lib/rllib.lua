local _M = { _VERSION = "1.0.2" }

local redis = require "resty.redis"
local redis_cluster = require "resty.rediscluster"

local DEFAULT_CONFIG = {
  -- Standalone Redis settings
  redis_host = "127.0.0.1",
  redis_port = 6379,
  password = nil,
  db = nil,

  -- Connection settings
  redis_timeout = 1000,
  redis_pool_size = 100,
  redis_keepalive_timeout = 60000,

  -- Redis Cluster support
  use_redis_cluster = false,
  redis_cluster_nodes = {
    { ip = "127.0.0.1", port = 7000 },
    { ip = "127.0.0.1", port = 7001 },
    { ip = "127.0.0.1", port = 7002 },
    { ip = "127.0.0.1", port = 7003 },
    { ip = "127.0.0.1", port = 7004 },
    { ip = "127.0.0.1", port = 7005 },
  },
  redis_cluster_name = "rate_limit_cluster",
  redis_cluster_dict_name = "redis_cluster_slot_locks",

  -- Rate limiting config
  default_limit = 10,
  default_window = 60,
  key_prefix = "rate_limit:{",
  key_suffix = "}",

  -- Identifier resolver
  default_identifier_fn = function()
    return ngx.var.http_x_forwarded_for or ngx.var.remote_addr
  end,

  -- Local cache support (disabled by default)
  local_cache_enabled = false,
  local_cache_name = nil,
}

local module_config = {}

local function get_redis_conn()
  if module_config.use_redis_cluster then
    local config = {
      name = module_config.redis_cluster_name,
      dict_name = module_config.redis_cluster_dict_name,
      serv_list = module_config.redis_cluster_nodes,
      connect_timeout = module_config.redis_timeout,
      read_timeout = module_config.redis_timeout,
      send_timeout = module_config.redis_timeout,
      keepalive_timeout = module_config.redis_keepalive_timeout,
      keepalive_cons = module_config.redis_pool_size,
      max_redirection = 5,
      max_connection_attempts = 1,
      auth = module_config.password,
      enable_slave_read = false,
      debug = false,
    }

    local red, err = redis_cluster:new(config)
    if not red then
      ngx.log(ngx.ERR, "Redis Cluster connection failed: ", err)
      return nil, "REDIS_CLUSTER_CONNECTION_ERROR: " .. (err or "unknown error")
    end

    return red, nil
  end

  local red, err = redis:new()
  if not red then
    ngx.log(ngx.ERR, "Failed to instantiate Redis: ", err)
    return nil, "REDIS_INSTANCE_ERROR"
  end

  red:set_timeouts(module_config.redis_timeout, module_config.redis_timeout, module_config.redis_timeout)

  local ok, conn_err = red:connect(module_config.redis_host, module_config.redis_port)
  if not ok then
    ngx.log(ngx.ERR, "Redis connection failed: ", conn_err)
    return nil, "REDIS_CONNECTION_ERROR: " .. conn_err
  end

  if module_config.password then
    local auth_ok, auth_err = red:auth(module_config.password)
    if not auth_ok then
      red:close()
      ngx.log(ngx.ERR, "Redis authentication failed: ", auth_err)
      return nil, "REDIS_AUTH_ERROR: " .. auth_err
    end
  end

  if module_config.db then
    local select_ok, select_err = red:select(module_config.db)
    if not select_ok then
      red:close()
      ngx.log(ngx.ERR, "Failed to select Redis DB: ", select_err)
      return nil, "REDIS_DB_ERROR: " .. select_err
    end
  end

  return red, nil
end

local function put_redis_conn(red)
  if not red or module_config.use_redis_cluster then
    return
  end

  local ok, err = red:set_keepalive(module_config.redis_keepalive_timeout, module_config.redis_pool_size)
  if not ok then
    ngx.log(ngx.ERR, "Failed to set Redis keepalive: ", err)
  end
end

--- Initializes the rate limit module with optional configuration overrides.
---@param custom_config table Configuration overrides.
---@return boolean, string
function _M.init(custom_config)
  for k, v in pairs(DEFAULT_CONFIG) do
    module_config[k] = custom_config[k] or v
  end

  if module_config.use_redis_cluster and not redis_cluster then
    ngx.log(ngx.ERR, "resty-redis-cluster module not found")
    return false, "REDIS_CLUSTER_MODULE_NOT_FOUND"
  end

  ngx.log(ngx.INFO, "Rate limiter initialized successfully")
  return true, "OK"
end

--- Enforces fixed-window rate limiting.
---@param identifier string Unique key (e.g., IP or user ID).
---@param limit number Max allowed requests.
---@param window number Time window in seconds.
---@return boolean|nil, string|nil
function _M.enforce_limit(identifier, limit, window)
  limit = limit or module_config.default_limit
  window = window or module_config.default_window
  identifier = identifier or module_config.default_identifier_fn()

  if not identifier or limit <= 0 or window <= 0 then
    ngx.log(ngx.ERR, "Invalid parameters for enforce_limit")
    return false, "INVALID_ARGUMENTS"
  end

  local red, conn_err = get_redis_conn()
  if not red then
    ngx.log(ngx.ERR, "Redis connection error: ", conn_err)
    return nil, conn_err
  end

  local now = ngx.time()
  local window_start = math.floor(now / window) * window
  local redis_key = string.format("rate_limit:{%s}:%d", identifier, window_start)

  local lua_script = [[
    local current = redis.call("INCR", KEYS[1])
    if tonumber(current) == 1 then
      redis.call("EXPIRE", KEYS[1], ARGV[1])
    end
    return current
  ]]

  local count, err = red:eval(lua_script, 1, redis_key, tostring(window))
  if not count then
    ngx.log(ngx.ERR, "Redis eval failed: ", err)
    return false, "REDIS_EVAL_ERROR"
  end

  if tonumber(count) > limit then
    ngx.log(ngx.WARN, "Rate limit exceeded: ", identifier)
    return false, "RATE_LIMITED"
  end

  return true, "OK"
end

--- Returns the current count and TTL for a rate limit key.
---@param identifier string Rate limit identifier.
---@param window number Time window in seconds.
---@return table|nil, string|nil
function _M.get_status(identifier, window)
  window = window or module_config.default_window
  identifier = identifier or module_config.default_identifier_fn()
  if not identifier then
    return nil, "INVALID_IDENTIFIER"
  end

  local now = ngx.time()
  local window_start = math.floor(now / window) * window
  local redis_key =
    string.format("%s%s%s:%d", module_config.key_prefix, identifier, module_config.key_suffix, window_start)

  local red, conn_err = get_redis_conn()
  if not red then
    ngx.log(ngx.ERR, "Redis connection error: ", conn_err)
    return nil, conn_err
  end

  local results, err
  if module_config.use_redis_cluster then
    red:init_pipeline()
    red:get(redis_key)
    red:ttl(redis_key)
    results, err = red:commit_pipeline()
  else
    red:multi()
    red:get(redis_key)
    red:ttl(redis_key)
    results, err = red:exec()
  end

  put_redis_conn(red)

  if not results then
    ngx.log(ngx.ERR, "Failed to retrieve rate limit status: ", err)
    return nil, "REDIS_PIPELINE_ERROR: " .. (err or "unknown error")
  end

  local count = tonumber(results[1]) or 0
  local ttl = results[2] or -1

  return { current_count = count, ttl = ttl }, "OK"
end

return _M
