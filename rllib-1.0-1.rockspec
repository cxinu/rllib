rockspec_format = "3.0"

package = "rllib"
version = "1.0-1"
source = {
  url = "git+ssh://git@github.com/cxinu/rllib.git",
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

dependencies = {}
build_dependencies = {}
test_dependencies = {}

build = {
  type = "builtin",
  modules = {
    ["rllib.rllib"] = "lib/rllib/rllib.lua",
  },
  copy_directories = {
    "docs",
  },
}
