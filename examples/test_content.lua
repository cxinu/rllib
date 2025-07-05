local redis_cluster = require "resty.rediscluster"

local red, err = redis_cluster:new {
  name = "testCluster",
  serv_list = {
    { ip = "127.0.0.1", port = 7000 },
    { ip = "127.0.0.1", port = 7001 },
    { ip = "127.0.0.1", port = 7002 },
  },
}

if not red then
  ngx.say("Failed to connect: ", err)
  return
end

local res, err = red:get "resty:testkey"
if not res then
  ngx.say("Failed to get key: ", err)
  return
end

ngx.say("Value: ", res)
