local auth = require("api_key_auth")
local cors = require("cors")

-- Let OPTIONS requests pass through for CORS preflight, handled by upstream.
local method = ngx.req.get_method()
if method == "OPTIONS" then
    return
end

local api_key_name = ngx.var.api_key_name
local ok, err = auth.verify_header_signature(api_key_name)
if not ok then
    -- On failure, add CORS headers and exit with 401
    cors.add_headers()
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say(err)
    return ngx.exit(ngx.HTTP_UNAUTHORIZED)
end
