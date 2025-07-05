local redis_cluster = require "resty.rediscluster"

local red, err = redis_cluster:new {
  name = "testCluster",
  serv_list = {
    { ip = "127.0.0.1", port = 7000 },
    { ip = "127.0.0.1", port = 7001 },
    { ip = "127.0.0.1", port = 7002 },
  },
  read_timeout = 1000,
  keepalive_timeout = 60000,
  keepalive_cons = 100,
}

if not red then
  ngx.log(ngx.ERR, "Failed to create Redis cluster client: ", err)
  return ngx.exit(500)
end

local ok, err = red:set("resty:testkey", "hello")
if not ok then
  ngx.log(ngx.ERR, "Failed to set key: ", err)
  return ngx.exit(500)
end
