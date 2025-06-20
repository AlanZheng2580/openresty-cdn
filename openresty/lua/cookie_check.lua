local auth = require("api_key_auth")
local ok, err = auth.verify_cookie()
if not ok then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say(err)
    return
end
