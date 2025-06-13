local redis = require "ratelimit.redis"
local postgres = require "ratelimit.postgres"
local raft = require "ratelimit.raft"
local _M = {}

function _M.new(config)
  local self = {
    redis = redis.new(config.redis),
    postgres = postgres.new(config.postgres),
    raft = raft.new(config),
    config = config
  }
  return setmetatable(self, { __index = _M })
end

function _M.run(self)
  if not self.raft:is_leader() then
    return
  end
  local keys = self.redis:get_all_keys(self.config.redis.prefix .. "*")
  for _, key in ipairs(keys) do
    local count = self.redis:get_count(key)
    self.postgres:mirror(key, count, os.time())
  end
end

function _M.start(self, interval)
  local function loop(premature)
    if premature then return end
    self:run()
    self.raft:elect_leader()
    ngx.timer.at(interval, loop)
  end
  ngx.timer.at(0, loop)
end

return _M
