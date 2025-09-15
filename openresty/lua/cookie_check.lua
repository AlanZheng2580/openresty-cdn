local auth = require("api_key_auth")
local cors = require("cors")

local method = ngx.req.get_method()
if method == "OPTIONS" then
    return
end

local api_key_name = ngx.var.api_key_name
local ok, err = auth.verify_cookie(api_key_name)
if not ok then
    cors.add_headers()
    ngx.status = ngx.HTTP_FORBIDDEN
    ngx.say(err)
    return ngx.exit(ngx.HTTP_FORBIDDEN)
end
