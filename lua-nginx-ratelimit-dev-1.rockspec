package = "lua-nginx-ratelimit"
version = "dev-1"
source = {
   url = "git+ssh://git@github.com/cxinu/lua-nginx-ratelimit.git"
}
description = {
   summary = "This repository implements an efficient, Redis-backed rate limiter for NGINX using OpenResty and Lua.",
   detailed = "This repository implements an efficient, Redis-backed rate limiter for NGINX using OpenResty and Lua. It provides IP-based request throttling using lightweight Lua scripts executed directly in the NGINX request processing phase.",
   homepage = "*** please enter a project homepage ***",
   license = "*** please specify a license ***"
}
build = {
   type = "builtin",
   modules = {
      ["lualib.mirror"] = "lualib/mirror.lua",
      ["lualib.rate_limit"] = "lualib/rate_limit.lua"
   },
   copy_directories = {
      "docs"
   }
}
