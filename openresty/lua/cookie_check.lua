local auth = require("api_key_auth")
local api_key_name = ngx.var.api_key_name
local ok, err = auth.verify_cookie(api_key_name)
if not ok then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say(err)
    return nginx.exit(ngx.HTTP_UNAUTHORIZED)
end
