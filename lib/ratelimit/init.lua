local config = require "ratelimit.config"
local core = require "ratelimit.core"
local _M = {}

function _M.new(user_config)
  local cfg, err = config.new(user_config)
  if not cfg then
    return nil, err
  end
  return core.new(cfg)
end

return _M
