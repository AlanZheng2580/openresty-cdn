local http = require "resty.http"

local function call_auth_request_api(auth_request_url)
    local httpc = http.new()
    -- Set timeout for connection + response in milliseconds
    httpc:set_timeout(3000)

    local headers = {
        ["Authorization"]       = ngx.var.http_authorization,
        ["Cookie"]              = ngx.var.http_cookie,
        ["X-Real-IP"]           = ngx.var.remote_addr,
        ["X-Forwarded-For"]     = ngx.var.http_x_forwarded_for or ngx.var.remote_addr,
        ["X-Forwarded-Host"]    = ngx.var.host,
        ["X-Forwarded-Method"]  = ngx.req.get_method(),
        ["X-Forwarded-Uri"]     = ngx.var.request_uri,
        ["User-Agent"]          = "SECDN-API-CHECK/1.0",
    }

    local res, err
    for i = 1, 3 do
        -- By default, resty.http keeps the connection alive.
        -- Connection pool is managed by:
        --   * lua_socket_keepalive_timeout (default: 60s)
        --   * lua_socket_pool_size (default: 30 connections for every pool)
        res, err = httpc:request_uri(auth_request_url, {
            method = "GET",
            headers = headers,
        })

        if res then break end

        ngx.log(ngx.WARN, "[AUTH_API] Retry ", i, ": ", err)
        ngx.sleep(1)
    end

    if not res then
        ngx.log(ngx.ERR, "[AUTH_API] Auth API error: ", err)
        return false, "Auth API error: " .. err
    end

    -- Accept 2xx responses (200, 201, 202, etc.)
    if res.status < 200 or res.status >= 300 then
        ngx.log(ngx.WARN, "[AUTH_API] Auth API failed: ", res.status)
        return false, "Auth API failed: " .. res.status
    end

    return true, "OK"
end

local auth_request_url = ngx.var.secdn_auth_request_url
local ok, err = call_auth_request_api(auth_request_url)
if not ok then
    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.say(err)
    return ngx.exit(ngx.HTTP_UNAUTHORIZED)
end
