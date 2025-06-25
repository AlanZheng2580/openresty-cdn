local auth = require("api_key_auth")
local auth_mode = ngx.var.secdn_auth_mode or "api_key"      -- default to api_key
local api_key_name = ngx.var.api_key_name

local ok, err
if auth_mode == "api_key" then
    ok, err = auth.verify(api_key_name)
elseif auth_mode == "cookie" then
    ok, err = auth.verify_cookie(api_key_name)
else
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.say("Unknown auth_mode: " .. tostring(auth_mode))
    return
end

if not ok then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say(err)
    return
end
