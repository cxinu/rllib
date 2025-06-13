local pg = require "resty.postgres"
local _M = {}

function _M.new(config)
  local db = pg:new()
  db:set_timeout(config.timeout)
  local ok, err = db:connect({
    host = config.host,
    port = config.port,
    database = config.database,
    user = config.user,
    password = config.password
  })
  if not ok then
    return nil, err
  end
  db:set_keepalive(config.pool_size)
  return setmetatable({ db = db }, { __index = _M })
end

function _M.mirror(self, key, count, timestamp)
  local query = string.format(
    "INSERT INTO rate_limits (key, count, timestamp) VALUES ('%s', %d, to_timestamp(%d)) ON CONFLICT (key) DO UPDATE SET count = %d, timestamp = to_timestamp(%d)",
    key, count, timestamp, count, timestamp
  )
  return self.db:query(query)
end

return _M
