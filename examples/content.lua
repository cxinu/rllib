local cjson = require "cjson"
ngx.say "allowed request"
ngx.say("Is encode available? ", tostring(cjson.encode))
