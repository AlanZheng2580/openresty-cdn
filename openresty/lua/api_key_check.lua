local auth = require("api_key_auth")
local api_key_name = ngx.var.api_key_name
local ok, err = auth.verify(api_key_name)
if not ok then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say(err)
    return ngx.exit(ngx.HTTP_UNAUTHORIZED)
end
