local redis = require "resty.redis"
local _M = {}

function _M.new(config)
  local red = redis:new()
  if not red then
    ngx.log(ngx.ERR, "failed to create Redis instance")
    return ngx.exit(500)
  end
  red:set_timeout(config.timeout)
  red:set_keepalive(config.pool_size)
  local ok, err = red:connect(config.host, config.port)
  if not ok then
    return nil, err
  end
  return setmetatable({ redis = red, prefix = config.prefix, ttl = config.ttl }, { __index = _M })
end

function _M.increment(self, key, window)
  local full_key = self.prefix .. key
  local count = self.redis:incr(full_key)
  self.redis:expire(full_key, self.ttl)
  return count
end

function _M.get_count(self, key, window)
  local full_key = self.prefix .. key
  return self.redis:get(full_key) or 0
end

return _M
