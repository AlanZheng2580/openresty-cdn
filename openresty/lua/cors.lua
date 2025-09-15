-- cors.lua
-- This module automatically handles CORS (Cross-Origin Resource Sharing) headers.
-- It detects CORS requests based on the presence of the Origin header and
-- responds with appropriate headers. It requires no manual flags or parameters.

local _M = {}

function _M.add_headers()
    local origin = ngx.var.http_origin
    local method = ngx.req.get_method()

    -- Only handle CORS if the Origin header is present
    if origin then
        -- Always allow the origin that made the request
        ngx.header["Access-Control-Allow-Origin"] = origin

        -- Allow credentials (cookies, authorization headers, etc.)
        ngx.header["Access-Control-Allow-Credentials"] = "true"

        -- Expose certain headers to the browser
        ngx.header["Access-Control-Expose-Headers"] = "Content-Length, Content-Type"
    end
end

return _M
