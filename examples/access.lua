local rllib = require "rllib"

-- Define specific limits for this endpoint
local endpoint_limit = 10 -- requests
local endpoint_window = 60 -- seconds

-- Get the client identifier (e.g., remote IP)
local client_id = ngx.var.remote_addr
-- Or, if using an API key:
-- local client_id = ngx.var.http_x_api_key or ngx.var.remote_addr

local allowed, status_code = rllib.enforce_limit(client_id, endpoint_limit, endpoint_window)

if not allowed then
  ngx.header["X-RateLimit-Limit"] = endpoint_limit
  ngx.header["X-RateLimit-Remaining"] = 0
  -- Attempt to get TTL for Retry-After header
  local status_info, status_err = rllib.get_status(client_id, endpoint_window)
  if status_info and status_info.ttl and status_info.ttl > 0 then
    ngx.header["Retry-After"] = status_info.ttl
    ngx.header["X-RateLimit-Reset"] = ngx.time() + status_info.ttl
  else
    ngx.header["Retry-After"] = endpoint_window -- Fallback
    ngx.header["X-RateLimit-Reset"] = ngx.time() + endpoint_window
  end

  if status_code == "RATE_LIMITED" then
    ngx.status = ngx.HTTP_TOO_MANY_REQUESTS
    ngx.say "Too Many Requests. Please try again later."
  else
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.say("An internal error occurred: " .. status_code)
  end
  return ngx.exit(ngx.status)
end

-- Request is allowed. Set X-RateLimit headers.
local status_info, status_err = rllib.get_status(client_id, endpoint_window)
if status_info then
  ngx.header["X-RateLimit-Limit"] = endpoint_limit
  ngx.header["X-RateLimit-Remaining"] = math.max(0, endpoint_limit - status_info.current_count)
  if status_info.ttl and status_info.ttl > 0 then
    ngx.header["X-RateLimit-Reset"] = ngx.time() + status_info.ttl
  else
    -- Fallback for reset if TTL is not available (e.g., new window start)
    ngx.header["X-RateLimit-Reset"] = ngx.time() + endpoint_window
  end
else
  ngx.log(ngx.WARN, "Failed to get rate limit status for headers: ", status_err)
end
