# rllib

[![LuaRocks](https://img.shields.io/badge/LuaRocks-rllib-purple)](https://luarocks.org/modules/cxinu/rllib)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A high-performance, distributed rate-limiting library for OpenResty using Redis or Redis Cluster.

## Features

- **Distributed Counting**: Atomic, cross-node rate limiting with Redis or Redis Cluster.
- **Cluster Support**: Native integration with [kong-redis-cluster](https://github.com/Kong/resty-redis-cluster) for sharded setups.
- **Local Caching**: Optional `lua_shared_dict` cache to absorb traffic spikes and reduce Redis load.
- **Fixed Window Algorithm**: Simple and efficient rate limiting.
- **Header Helpers**: `get_status` function for setting `X-RateLimit-*` headers.
- **Configurable**: Customize Redis connections, identifiers, limits, and windows.

## Installation

```sh
luarocks install rllib
```

## Quick Start

### 1. Define `lua_shared_dict` in `nginx.conf` (Optional)

Add this to your `http` block in `nginx.conf` to enable local caching:

```nginx
# http { ... }
lua_shared_dict rllib_cache 10m;
```

### 2. Protect an Endpoint with Rate Limiting

Initialize the library in `init_worker_by_lua_block` and apply it to a location using `access_by_lua_block`.

```nginx
# in http block
init_worker_by_lua_block {
    local rllib = require "rllib"
    rllib.init({
        -- For standalone Redis
        redis_host = "127.0.0.1",
        redis_port = 6379,

        -- OR for Redis Cluster
        -- use_redis_cluster = true,
        -- redis_cluster_nodes = {
        --     { ip = "127.0.0.1", port = 7000 },
        --     { ip = "127.0.0.1", port = 7001 },
        --     { ip = "127.0.0.1", port = 7002 },
        -- },

        -- Optional: Enable the local cache
        local_cache_enabled = true,
        local_cache_name = "rllib_cache"
    })
}

server {
    listen 80;

    location /api/protected {
        access_by_lua_block {
            local rllib = require "rllib"

            local limit = 20
            local window = 60
            local identifier = ngx.var.binary_remote_addr

            local allowed, reason = rllib.enforce_limit(identifier, limit, window)

            if not allowed then
                if reason == "RATE_LIMITED" then
                    return ngx.exit(ngx.HTTP_TOO_MANY_REQUESTS)
                end
                return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end

            local status, err = rllib.get_status(identifier, window)
            if status then
                ngx.header["X-RateLimit-Limit"] = limit
                ngx.header["X-RateLimit-Remaining"] = math.max(0, limit - status.current_count)
                ngx.header["X-RateLimit-Reset"] = ngx.time() + (status.ttl > 0 and status.ttl or window)
            end
        }

        # Your backend logic here...
        return(200, "OK\n");
    }
}
```

## API

### `rllib.init(config_table)`

Initializes the library with configuration. Call once per worker (e.g., in `init_worker_by_lua_block`).

### `rllib.enforce_limit(identifier, limit, window)`

Checks and increments the rate limit counter.

- `identifier` `(string)`: The key to rate limit on (e.g., IP, user ID).
- `limit` `(number)`: Max requests per window.
- `window` `(number)`: Duration of the window in seconds.
- **Returns**: `(boolean, string)`

  - `true, "OK"`: Request allowed.
  - `false, "RATE_LIMITED"`: Request blocked.
  - `false, <error_string>`: Internal failure (e.g. Redis error).

### `rllib.get_status(identifier, window)`

Retrieves current count and TTL for the identifier.

- `identifier` `(string)`: The key to check.
- `window` `(number)`: Time window in seconds.
- **Returns**: `(table|nil, string)`

  - `{ current_count = N, ttl = T }, "OK"` on success.
  - `nil, <error_string>` on error.

## Configuration

Pass a config table to `rllib.init()` to override defaults.

| Key                       | Description                                       | Default                                     |
| ------------------------- | ------------------------------------------------- | ------------------------------------------- |
| `redis_host`              | Redis host (standalone mode)                      | `"redis"`                                   |
| `redis_port`              | Redis port (standalone mode)                      | `6379`                                      |
| `password`                | Redis AUTH password                               | `nil`                                       |
| `db`                      | Redis database number                             | `nil`                                       |
| `redis_timeout`           | Redis command timeout (ms)                        | `1000`                                      |
| `redis_pool_size`         | Connection pool size                              | `100`                                       |
| `redis_keepalive_timeout` | Connection keepalive timeout (ms)                 | `60000`                                     |
| `use_redis_cluster`       | Enable Redis Cluster mode                         | `false`                                     |
| `redis_cluster_nodes`     | List of `{ ip, port }` cluster nodes              | `{{ip="redis-cluster",port=7000},...}`      |
| `test_redis_cluster`      | Log ping status on init (for debugging)           | `false`                                     |
| `default_limit`           | Default requests allowed per window               | `10`                                        |
| `default_window`          | Default window duration (seconds)                 | `60`                                        |
| `key_prefix`              | Prefix for Redis keys                             | `"rate_limit:"`                             |
| `default_identifier_fn`   | Function to generate key if `identifier` is `nil` | `function() return ngx.var.remote_addr end` |
| `local_cache_enabled`     | Enable local shared dict caching                  | `false`                                     |
| `local_cache_name`        | Name of your `lua_shared_dict` zone               | `nil`                                       |

## License

[MIT](LICENSE)
