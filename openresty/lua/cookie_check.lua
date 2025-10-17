local auth = require("api_key_auth")
local cors = require("cors")

local method = ngx.req.get_method()
if method == "OPTIONS" then
    return
end

local api_key_name = ngx.var.api_key_name
local status, err = auth.verify_cookie(api_key_name)
if status ~= ngx.HTTP_OK then
    if ngx.var.cdn_enable_cors_on_failure == "1" then
        cors.add_headers()
    end
    ngx.status = status
    ngx.say(err)
    return ngx.exit(status)
end
