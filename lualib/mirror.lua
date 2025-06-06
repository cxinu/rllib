local _M = {}

local function mirror_to_postgres(premature)
  if premature then
    return
  end

  local redis = require("resty.redis")
  local pgmoon = require("pgmoon")

  -- Connect to Redis
  local red = redis:new()
  if not red then
    ngx.log(ngx.ERR, "failed to create Redis instance")
    return ngx.exit(500)
  end

  red:set_timeout(1000)

  local ok, err = red:connect("127.0.0.1", 6379)
  if not ok then
    ngx.log(ngx.ERR, "Redis connect failed: ", err)
    return
  end

  -- Get keys
  local keys, key_err = red:keys("rate_limit:*")
  if not keys then
    ngx.log(ngx.ERR, "Redis keys failed: ", key_err)
    return
  end

  -- Connect to PostgreSQL
  local pg = pgmoon.new({
    host = "127.0.0.1",
    port = 5432,
    database = "mydb",
    user = "myuser",
    password = "mypassword"
  })

  ok, err = pg:connect()
  if not ok then
    ngx.log(ngx.ERR, "PostgreSQL connect failed: ", err)
    return
  end

  for _, key in ipairs(keys) do
    local count, _ = red:get(key)
    if count and count ~= ngx.null then
      local ip = key:match("rate_limit:(.+)")
      if ip then
        local res, query_err = pg:query([[
          INSERT INTO rate_limit_log (ip, count)
          VALUES ($1, $2)
        ]], { ip, tonumber(count) })

        if not res then
          ngx.log(ngx.ERR, "Postgres insert failed: ", query_err)
        end
      end
    end
  end

  red:set_keepalive(10000, 100)
  pg:keepalive()
end

function _M.run()
  local ok, err = ngx.timer.every(30, mirror_to_postgres)
  if not ok then
    ngx.log(ngx.ERR, "Failed to create timer: ", err)
  end
end

return _M
