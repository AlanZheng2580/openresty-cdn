local _M = {}
local keys = {}
local secret_dir = nil

function _M.set_dir(dir)
    secret_dir = dir
end

function _M.load_all_keys_from_dir()
    if not secret_dir then
        ngx.log(ngx.ERR, "[API-KEY] Directory not set. Call set_dir() first.")
        return
    end

    ngx.log(ngx.INFO, "[API-KEY] loading keys from dir: ", secret_dir)
    local handle = io.popen("ls -1 " .. secret_dir)
    if not handle then
        ngx.log(ngx.ERR, "[API-KEY] Failed to list files in ", secret_dir)
        return
    end

    local new_keys = {}
    for filename in handle:lines() do
        local path = secret_dir .. "/" .. filename
        local f = io.open(path, "r")
        if f then
            local key = f:read("*l")
            f:close()
            if key then
                new_keys[filename] = key
                ngx.log(ngx.INFO, "[API-KEY] Loaded key from file: ", filename)
            end
        else
            ngx.log(ngx.ERR, "[API-KEY] Failed to open: ", path)
        end
    end
    handle:close()

    keys = new_keys
end

function _M.verify(api_key_name)
    local expected = keys[api_key_name]
    if not expected then
        ngx.log(ngx.ERR, "[API-KEY] No key loaded for api_key_name: ", api_key_name)
        return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    local actual = ngx.req.get_headers()["X-Secdn-API-KEY"]
    if not actual or actual ~= expected then
        ngx.status = ngx.HTTP_UNAUTHORIZED
        ngx.say("Unauthorized")
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end
end

function _M.reload()
    ngx.log(ngx.WARN, "[API-KEY] Manual reload triggered.")
    _M.load_all_keys_from_dir()
    ngx.say("API Keys Reloaded")
end

return _M
