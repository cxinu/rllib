# rllib

[![LuaRocks](https://img.shields.io/badge/LuaRocks-rllib-purple)](https://luarocks.org/modules/cxinu/rllib)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A high-performance, distributed rate-limiting library for OpenResty using Redis.

## Features

- **Distributed Counting**: Atomic, cross-node rate limiting with Redis.
- **Local Caching**: Optional `lua_shared_dict` cache to absorb traffic spikes and reduce Redis load.
- **Fixed Window Algorithm**: Simple and efficient rate limiting.
- **Header Helpers**: `get_status` function for setting `X-RateLimit-*` headers.
- **Configurable**: Customize Redis connections, identifiers, limits, and windows.

## Installation

```sh
luarocks install rllib
```

## Quick Start

1.  **Define `lua_shared_dict` in `nginx.conf`**

    Add this to your `http` block in `nginx.conf` to enable the local cache.

    ```nginx
    # http { ... }
    lua_shared_dict rllib_cache 10m;
    ```

2.  **Protect an Endpoint**

    Initialize the library in `init_worker_by_lua_block` and apply it to a location using `access_by_lua_block`.

    ```nginx
    # in http block
    init_worker_by_lua_block {
        -- Initialize rllib once per worker.
        local rllib = require "rllib"
        rllib.init({
            redis_host = "127.0.0.1",
            redis_port = 6379,
            -- password = "your_redis_password",

            -- Enable the local cache for performance
            local_cache_enabled = true,
            local_cache_name = "rllib_cache" -- Must match the dict name above
        })
    }

    server {
        listen 80;

        location /api/protected {
            access_by_lua_block {
                local rllib = require "rllib"

                local limit = 20  -- requests
                local window = 60 -- seconds
                local identifier = ngx.var.binary_remote_addr -- Use client IP

                local allowed, reason = rllib.enforce_limit(identifier, limit, window)

                if not allowed then
                    if reason == "RATE_LIMITED" then
                        return ngx.exit(ngx.HTTP_TOO_MANY_REQUESTS)
                    end
                    -- Handle other errors (e.g., Redis connection issue)
                    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
                end

                -- Optional: Set rate limit headers
                local status, err = rllib.get_status(identifier, window)
                if status then
                    ngx.header["X-RateLimit-Limit"] = limit
                    ngx.header["X-RateLimit-Remaining"] = math.max(0, limit - status.current_count)
                    ngx.header["X-RateLimit-Reset"] = ngx.time() + (status.ttl > 0 and status.ttl or window)
                end
            }

            # Your backend logic here...
            # proxy_pass http://my_backend;
            return(200, "OK\n");
        }
    }
    ```

## API

#### `rllib.init(config_table)`

Initializes the library with global settings. Call this once in `init_worker_by_lua_block`.

#### `rllib.enforce_limit(identifier, limit, window)`

Checks and increments the rate limit counter.

- **`identifier`** `(string)`: The key to rate limit on (e.g., IP, API key).
- **`limit`** `(number)`: Max requests allowed in the window.
- **`window`** `(number)`: Window duration in seconds.
- **Returns** `(boolean, string)`:
  - `true, "OK"`: Request is allowed.
  - `false, "RATE_LIMITED"`: Request is denied.
  - `false, <error_string>`: An internal error occurred.

#### `rllib.get_status(identifier, window)`

Fetches the current count and TTL for a key. Does not increment the counter.

- **`identifier`** `(string)`: The key to check.
- **`window`** `(number)`: The configured window for the key.
- **Returns** `(table, string)`:
  - `{ current_count = N, ttl = T }, "OK"` on success.
  - `nil, <error_string>` on failure.

## Configuration

Pass a table to `rllib.init()` to override defaults.

| Key                     | Description                             | Default                                     |
| ----------------------- | --------------------------------------- | ------------------------------------------- |
| `redis_host`            | Redis server hostname.                  | `"redis"`                                   |
| `redis_port`            | Redis server port.                      | `6379`                                      |
| `redis_timeout`         | Redis command timeout in ms.            | `1000`                                      |
| `redis_pool_size`       | Connection pool size.                   | `100`                                       |
| `password`              | Redis AUTH password.                    | `nil`                                       |
| `db`                    | Redis database number.                  | `nil`                                       |
| `default_limit`         | Default request limit if unspecified.   | `10`                                        |
| `default_window`        | Default window in seconds.              | `60`                                        |
| `key_prefix`            | Prefix for all Redis keys.              | `"rate_limit:"`                             |
| `default_identifier_fn` | Function to generate identifier if nil. | `function() return ngx.var.remote_addr end` |
| `local_cache_enabled`   | Enable the `lua_shared_dict` cache.     | `false`                                     |
| `local_cache_name`      | Name of the `lua_shared_dict` zone.     | `nil`                                       |

## License

[MIT](LICENSE)
