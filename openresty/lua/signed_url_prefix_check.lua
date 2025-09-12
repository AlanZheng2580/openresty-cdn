local auth = require("api_key_auth")

local method = ngx.req.get_method()
if method == "OPTIONS" then
    return
end

local api_key_name = ngx.var.api_key_name
local ok, err = auth.verify_signed_url_prefix(api_key_name)
if not ok then
    ngx.status = ngx.HTTP_FORBIDDEN
    ngx.say(err)
    return ngx.exit(ngx.HTTP_FORBIDDEN)
end

-- Validation successful

-- Add original URL to a header for the origin to optionally use
local original_url = ngx.var.scheme .. "://" .. ngx.var.http_host .. ngx.var.request_uri
ngx.req.set_header("X-Client-Request-URL", original_url)

-- Remove auth query parameters before proxying
local args = ngx.req.get_uri_args()
args.URLPrefix = nil
args.Expires = nil
args.KeyName = nil
args.Signature = nil
ngx.req.set_uri_args(args)

