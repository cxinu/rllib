# NGINX Rate Limiter with Lua and Redis

This repository implements an efficient, Redis-backed rate limiter for NGINX using OpenResty and Lua. It provides IP-based request throttling using lightweight Lua scripts executed directly in the NGINX request processing phase.

## Overview

The rate limiter is designed for high-performance scenarios where low overhead and shared state across instances are required. Redis is used as the central store for tracking request counts and time windows, enabling consistent enforcement across distributed environments.

- API gateways
- Microservices rate limiting
- Reverse proxies or edge protection

## Architecture

* **NGINX (OpenResty)** handles HTTP traffic and executes embedded Lua scripts.
* **Lua** defines the rate limiting logic in `access_by_lua_file`.
* **Redis** stores per-IP counters with expiration for windowed rate limiting.

## Prerequisites

* OpenResty ([https://openresty.org/](https://openresty.org/))
* Redis server (local or remote)

## Usage

Start the OpenResty server from the project root:

```bash
openresty -p $PWD -c conf/nginx.conf
```

Ensure Redis is running and reachable from the host running OpenResty.

## Configuration

Specifiy Correct lua package path in `nginx.conf`

```nginx
lua_package_path "<openresty_path>/lualib/?.lua;;";
```

### Lua Module Usage

`example.lua`

```lua
local config = {
  redis_host = "127.0.0.1",
  redis_port = 6379,
  limit = 100,
  window = 60,
  key_func = function() return ngx.var.remote_addr end,
}
```
