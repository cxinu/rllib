local redis = require("resty.redis")
local red = redis:new()

if not red then
  ngx.log(ngx.ERR, "failed to create Redis instance")
  return ngx.exit(500)
end

red:set_timeout(1000)
local ok, err = red:connect("127.0.0.1", 6379)
if not ok then
  ngx.log(ngx.ERR, "failed to connect to redis: ", err)
  return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

local limit = 10
local window = 60
local client_ip = ngx.var.remote_addr
local key = "rate_limit:" .. client_ip

local count, _ = red:get(key)
if count == ngx.null then
  count = 0
else
  count = tonumber(count)
end

if count >= limit then
  red:close()
  ngx.status = 429
  ngx.say("Rate limit exceeded")
  return ngx.exit(ngx.HTTP_TOO_MANY_REQUESTS)
end

count = red:incr(key)
if count == 1 then
  red:expire(key, window)
end

red:set_keepalive(10000, 100)
red:set_keepalive(10000, 100) -- Pool connection
