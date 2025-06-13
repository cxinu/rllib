local redis = require "ratelimit.redis"
local postgres = require "ratelimit.postgres"
local worker = require "ratelimit.worker"
local _M = {}

function _M.new(config)
  local self = {
    config = config,
    redis = redis.new(config.redis),
    postgres = config.postgres.enabled and postgres.new(config.postgres) or nil,
    worker = config.worker.enabled and worker.new(config) or nil
  }
  if self.worker then
    self.worker:start(config.worker.interval)
  end
  return setmetatable(self, { __index = _M })
end

function _M.apply(self, key)
  local count, err = self.redis:get_count(key, self.config.rate_limit.window)
  if err then
    return false, err
  end
  if count >= self.config.rate_limit.limit then
    return false, "rate limit exceeded"
  end
  self.redis:increment(key, self.config.rate_limit.window)
  return true
end

return _M
