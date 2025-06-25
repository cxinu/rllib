local _M = { _VERSION = "1.0.2" }

local redis = require "resty.redis"
local cluster = require "kong-redis-cluster"

local DEFAULT_CONFIG = {
  -- Standalone Redis settings
  redis_host = "redis",
  redis_port = 6379,
  password = nil, -- Redis auth
  db = nil, -- specific Redis DB

  -- Redis common settings
  redis_timeout = 1000, -- ms
  redis_pool_size = 100,
  redis_keepalive_timeout = 60000, -- ms (for standalone Redis only)

  -- Cluster support
  test_redis_cluster = false,
  use_redis_cluster = false,
  redis_cluster_nodes = {
    { ip = "redis-cluster", port = 7000 },
    { ip = "redis-cluster", port = 7001 },
    { ip = "redis-cluster", port = 7002 },
  },

  -- Rate limiting
  default_limit = 10, -- requests per window
  default_window = 60, -- seconds
  key_prefix = "rate_limit:",

  -- Identifier function
  default_identifier_fn = function()
    return ngx.var.http_x_forwarded_for or ngx.var.remote_addr
  end,

  -- Local cache
  local_cache_enabled = false,
  local_cache_name = nil,
}

local module_config = {}

local function get_redis_conn()
  if module_config.use_redis_cluster then
    local red, err = cluster:new {
      name = "rate_limit_cluster",
      serv_list = module_config.redis_cluster_nodes,
      timeout = module_config.redis_timeout,
      keepalive_timeout = module_config.redis_keepalive_timeout or 60000,
      keepalive_cons = module_config.redis_pool_size or 100,
      max_redirections = 5,
      read_slave = false,
    }

    if not red then
      ngx.log(ngx.ERR, "Failed to connect to Redis Cluster: ", err)
      return nil, "REDIS_CLUSTER_CONNECTION_ERROR: " .. err
    end

    return red, nil
  else
    local red, err = redis:new()
    if not red then
      ngx.log(ngx.ERR, "failed to instantiate redis: ", (err or "unknown error"))
      return nil, "REDIS_INSTANCE_ERROR"
    end

    red:set_timeouts(module_config.redis_timeout, module_config.redis_timeout, module_config.redis_timeout)

    local ok, conn_err = red:connect(module_config.redis_host, module_config.redis_port)
    if not ok then
      ngx.log(ngx.ERR, "failed to connect to redis: ", conn_err)
      return nil, "REDIS_CONNECTION_ERROR: " .. conn_err
    end

    if module_config.password then
      local auth_ok, auth_err = red:auth(module_config.password)
      if not auth_ok then
        red:close()
        ngx.log(ngx.ERR, "redis authentication failed: ", auth_err)
        return nil, "REDIS_AUTH_ERROR: " .. auth_err
      end
    end

    if module_config.db then
      local select_ok, select_err = red:select(module_config.db)
      if not select_ok then
        red:close()
        ngx.log(ngx.ERR, "redis DB selection failed: ", select_err)
        return nil, "REDIS_DB_ERROR: " .. select_err
      end
    end

    return red, nil
  end
end

local function put_redis_conn(red)
  if not red or module_config.use_redis_cluster then
    return
  end

  local ok, err = red:set_keepalive(module_config.redis_keepalive_timeout, module_config.redis_pool_size)
  if not ok then
    ngx.log(ngx.ERR, "failed to set redis keepalive: ", err)
  end
end

---@param custom_config table: A table to override default_config values.
function _M.init(custom_config)
  for k, v in pairs(DEFAULT_CONFIG) do
    module_config[k] = custom_config[k] or v
  end

  -- test clusters
  if module_config.test_redis_cluster then
    if not cluster then
      ngx.log(ngx.ERR, "kong-redis-cluster module not installed or failed to load: ", cluster)
    else
      ngx.log(ngx.INFO, "Successfully loaded kong-redis-cluster module")

      local red, err = cluster:new {
        name = "rate_limit_cluster",
        serv_list = module_config.redis_cluster_nodes,
        timeout = module_config.redis_timeout,
        keepalive_timeout = module_config.redis_keepalive_timeout or 60000,
        keepalive_cons = module_config.redis_pool_size or 100,
        max_redirections = 5,
        read_slave = false,
      }

      if not red then
        ngx.log(ngx.ERR, "Failed to connect to Redis Cluster: ", err)
      else
        local pong, ping_err = red:ping()
        if not pong then
          ngx.log(ngx.ERR, "Redis Cluster ping failed: ", ping_err)
        else
          ngx.log(ngx.INFO, "Redis Cluster is reachable: ", pong)
        end
      end
    end
  end

  ngx.log(ngx.INFO, "Rate limit library initialized")
end

--- Enforces a fixed-window rate limit for a given identifier.
---@param identifier string: The unique key for rate limiting (e.g., IP address, user ID).
---@param limit number: The maximum number of requests allowed in the window.
---@param window number: The duration of the window in seconds.
---@return boolean: true if the request is allowed, false if rate limited.
---@return string|nil: "OK" if allowed, "RATE_LIMITED" if blocked, or an error message if an internal issue occurred.
function _M.enforce_limit(identifier, limit, window)
  limit = limit or module_config.default_limit
  window = window or module_config.default_window

  if not identifier then
    identifier = module_config.default_identifier_fn()
  end

  if not identifier or limit <= 0 or window <= 0 then
    ngx.log(
      ngx.ERR,
      "Invalid arguments for enforce_limit: identifier=",
      identifier,
      ", limit=",
      limit,
      ", window=",
      window
    )
    return false, "INVALID_ARGUMENTS"
  end

  local current_time = ngx.time()
  local window_start_time = math.floor(current_time / window) * window
  local redis_key = module_config.key_prefix .. identifier .. ":" .. window_start_time

  if module_config.local_cache_enabled then
    local cache = ngx.shared[module_config.local_cache_name]
    if cache then
      local local_count = cache:get(redis_key)
      if local_count and local_count >= limit then
        if (local_count + 1) > limit then
          ngx.log(ngx.WARN, "Rate limit exceeded (local cache) for identifier '", identifier, "'")
          return false, "RATE_LIMITED"
        end
      end
    else
      ngx.log(
        ngx.ERR,
        "lua_shared_dict '",
        module_config.local_cache_name,
        "' not found. Did you declare it in nginx.conf?"
      )
    end
  end

  local red, conn_err = get_redis_conn()
  if not red then
    ngx.log(ngx.ERR, "Failed to get Redis connection for rate limiting: ", conn_err)
    return false, conn_err
  end

  local success, incr_err = red:incr(redis_key)
  if not success then
    put_redis_conn(red)
    ngx.log(ngx.ERR, "Redis INCR command failed for key '", redis_key, "': ", incr_err)
    return false, "REDIS_INCR_ERROR: " .. incr_err
  end

  local current_count = success

  -- set expiry only if it's the first request in the window (count == 1)
  if current_count == 1 then
    local expire_ok, expire_err = red:expire(redis_key, window)
    if not expire_ok then
      ngx.log(ngx.ERR, "Redis EXPIRE command failed for key '", redis_key, "': ", expire_err)
      -- This is often a soft error, request can still proceed, but log it.
      -- The key will eventually expire, or the new window will use a new key.
    end
  end

  put_redis_conn(red)

  if module_config.local_cache_enabled then
    local cache = ngx.shared[module_config.local_cache_name]
    if cache then
      local ok, err = cache:set(redis_key, current_count, window)
      if not ok then
        ngx.log(ngx.ERR, "Failed to update local cache: ", err)
      end
    end
  end

  if current_count > limit then
    ngx.log(
      ngx.WARN,
      "Rate limit exceeded for identifier '",
      identifier,
      "'. Count: ",
      current_count,
      ", Limit: ",
      limit
    )
    return false, "RATE_LIMITED"
  else
    ngx.log(ngx.INFO, "Request allowed for identifier '", identifier, "'. Count: ", current_count, ", Limit: ", limit)
    return true, "OK"
  end
end

--- Retrieves the current count and TTL for a given rate limit key.
-- Usecase for setting X-RateLimit-* headers.
---@param identifier string: The unique key for rate limiting.
---@param window number: The duration of the window in seconds.
---@return table|nil: { current_count: Number, ttl: Number } or nil if an error occurs.
---@return string|nil: "OK" or an error message if something went wrong.
function _M.get_status(identifier, window)
  window = window or module_config.default_window

  if not identifier then
    identifier = module_config.default_identifier_fn()
  end

  if not identifier then
    return nil, "INVALID_IDENTIFIER"
  end

  local current_time = ngx.time()
  local window_start_time = math.floor(current_time / window) * window
  local redis_key = module_config.key_prefix .. identifier .. ":" .. window_start_time

  local red, conn_err = get_redis_conn()
  if not red then
    ngx.log(ngx.ERR, "Failed to get Redis connection for rate limit status: ", conn_err)
    return nil, conn_err
  end

  -- Use Redis pipeline for atomic GET and TTL
  local pipeline_ok, pipeline_err = red:multi()
  if not pipeline_ok then
    put_redis_conn(red)
    ngx.log(ngx.ERR, "Redis MULTI command failed: ", pipeline_err)
    return nil, "REDIS_MULTI_ERROR: " .. pipeline_err
  end

  red:get(redis_key)
  red:ttl(redis_key)

  local results, exec_err = red:exec()
  put_redis_conn(red)

  if not results then
    ngx.log(ngx.ERR, "Redis EXEC command failed: ", exec_err)
    return nil, "REDIS_EXEC_ERROR: " .. exec_err
  end

  local current_count = tonumber(results[1]) or 0
  local remaining_ttl = results[2] or -1 -- -1 if key exists but no expire, -2 if key does not exist

  return { current_count = current_count, ttl = remaining_ttl }, "OK"
end

return _M
