local _M = {}

-- Default configuration
local DEFAULT_CONFIG = {
  rate_limit = {
    algorithm = "token_bucket", -- Options: token_bucket, leaky_bucket
    limit = 100,                -- Requests per window
    window = 60,                -- Window in seconds
    burst = 10                  -- Allow burst requests (optional)
  },
  redis = {
    host = "127.0.0.1",
    port = 6379,
    timeout = 1000,         -- Connection timeout in ms
    pool_size = 100,        -- Connection pool size
    prefix = "rate_limit:", -- Key prefix for Redis
    ttl = 3600              -- TTL for keys in seconds
  },
  postgres = {
    enabled = false,
    host = "127.0.0.1",
    port = 5432,
    database = "rate_limits",
    user = "postgres",
    password = "",
    timeout = 1000,
    pool_size = 50
  },
  raft = {
    node_id = ngx.var.server_name or "unknown_node", -- Unique node ID
    election_key = "raft:leader",
    election_ttl = 30,                               -- Leader lease duration
    heartbeat_interval = 5                           -- Heartbeat interval in seconds
  },
  worker = {
    enabled = false, -- Disable mirroring by default
    interval = 10    -- Mirroring interval in seconds
  }
}

local function merge_config(default, user)
  local result = {}
  for k, v in pairs(default) do
    if type(v) == "table" and user[k] and type(user[k]) == "table" then
      result[k] = merge_config(v, user[k])
    else
      result[k] = user[k] or v
    end
  end
  return result
end

local function validate_config(config)
  if not config.rate_limit.limit or config.rate_limit.limit < 1 then
    return false, "rate_limit.limit must be a positive integer"
  end
  if not config.rate_limit.window or config.rate_limit.window < 1 then
    return false, "rate_limit.window must be a positive integer"
  end
  if config.rate_limit.algorithm ~= "token_bucket" and config.rate_limit.algorithm ~= "leaky_bucket" then
    return false, "rate_limit.algorithm must be 'token_bucket' or 'leaky_bucket'"
  end
  if config.redis.host == "" or not config.redis.port then
    return false, "redis.host and redis.port are required"
  end
  if config.postgres.enabled then
    if not config.postgres.host or not config.postgres.port or not config.postgres.database then
      return false, "postgres.host, postgres.port, and postgres.database are required when enabled"
    end
  end
  return true
end

function _M.new(user_config)
  local config = merge_config(DEFAULT_CONFIG, user_config or {})
  local ok, err = validate_config(config)
  if not ok then
    return nil, err
  end
  return config
end

return _M
