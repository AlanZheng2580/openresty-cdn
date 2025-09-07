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

        -- Handle preflight (OPTIONS) request
        if method == "OPTIONS" then
            local req_method = ngx.var.http_access_control_request_method
            if req_method then
                -- Allow common HTTP methods
                ngx.header["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"

                -- Echo back the requested headers or use a default set
                local req_headers = ngx.var.http_access_control_request_headers
                ngx.header["Access-Control-Allow-Headers"] =
                    req_headers or "Authorization, Content-Type, X-SECDN-API-KEY"

                -- Return 204 No Content for preflight request
                ngx.status = ngx.HTTP_NO_CONTENT
                return ngx.exit(ngx.HTTP_NO_CONTENT)
            end
        end

        -- Expose certain headers to the browser
        ngx.header["Access-Control-Expose-Headers"] = "Content-Length, Content-Type"
    end
end

return _M
