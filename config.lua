local rate_limit = require("rate_limit")
rate_limit.init({
  limit = 20,
  window = 60,
  err_msg = "Too many requests, please try again later",
  identifier_fn = function() return ngx.var.http_authorization or ngx.var.remote_addr end
})
