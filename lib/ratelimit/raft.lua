local redis = require "ratelimit.redis"
local _M = {}

function _M.new(config)
  local self = {
    redis = redis.new(config.redis),
    node_id = config.raft.node_id,
    election_key = config.raft.election_key,
    election_ttl = config.raft.election_ttl
  }
  return setmetatable(self, { __index = _M })
end

function _M.is_leader(self)
  local leader = self.redis:get(self.election_key)
  return leader == self.node_id
end

function _M.elect_leader(self)
  local ok = self.redis:setnx(self.election_key, self.node_id)
  if ok then
    self.redis:expire(self.election_key, self.election_ttl)
  end
  return ok
end

return _M
