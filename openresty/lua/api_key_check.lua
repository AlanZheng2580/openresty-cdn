local auth = require("api_key_auth")
local api_key_name = ngx.var.api_key_name
auth.verify(api_key_name)
