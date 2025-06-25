package = "rllib"
version = "1.0.2-0"
source = {
  url = "git+ssh://git@github.com/cxinu/rllib.git",
  tag = "1.0.2",
}
description = {
  summary = "High-performance, Redis-backed rate limiter for OpenResty and NGINX.",
  detailed = [[
rllib is a high-performance, distributed rate-limiting library for OpenResty using Redis.
It supports atomic cross-node request limiting, optional local caching with `lua_shared_dict`,
and a simple fixed-window algorithm.

The library is easy to configure, production-ready, and includes helper functions for setting
standard rate-limit headers. Designed for use in NGINX with Lua, it enables robust IP-based
throttling and traffic control across horizontally scaled environments.
]],
  homepage = "https://github.com/cxinu/rllib",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1, < 5.5",
  "kong-redis-cluster >= 1.5.5",
}

build = {
  type = "builtin",
  modules = {
    ["rllib"] = "lib/rllib.lua",
  },
}
