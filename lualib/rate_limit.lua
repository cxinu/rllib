local _M = {}

-- Default configuration
_M.default_config = {
  redis_host = "127.0.0.1",
  redis_port = 6379,
  redis_timeout = 1000,            -- ms
  redis_keepalive_timeout = 10000, -- ms
  redis_keepalive_pool_size = 100,
  limit = 10,                      -- requests
  window = 60,                     -- seconds
  key_prefix = "rate_limit:",
  err_msg = "Rate limit exceeded",
  err_status = 429,
  identifier_fn = function() return ngx.var.remote_addr end
}

function _M.init(custom_config)
  local config = {}
  for k, v in pairs(_M.default_config) do
    config[k] = custom_config[k] or v
  end
  _M.config = config
end

function _M.enforce()
  local config = _M.config or _M.default_config

  local redis = require("resty.redis")
  local red = redis:new()

  if not red then
    ngx.log(ngx.ERR, "failed to create Redis instance")
    return ngx.exit(500)
  end

  red:set_timeout(config.redis_timeout)
  local ok, err = red:connect(config.redis_host, config.redis_port)
  if not ok then
    ngx.log(ngx.ERR, "failed to connect to redis: ", err)
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  local identifier = config.identifier_fn()
  local key = config.key_prefix .. identifier

  local count, _ = red:get(key)
  if count == ngx.null then
    count = 0
  else
    count = tonumber(count)
  end

  if count >= config.limit then
    red:close()
    ngx.status = config.err_status
    ngx.say(config.err_msg)
    return ngx.exit(config.err_status)
  end

  count = red:incr(key)
  if count == 1 then
    red:expire(key, config.window)
  end

  red:set_keepalive(config.redis_keepalive_timeout, config.redis_keepalive_pool_size)
end

return _M
