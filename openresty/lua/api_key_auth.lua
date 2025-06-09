local _M = {}
local dict = ngx.shared.secrets

function _M.load(dir)
    if not dir then
        ngx.log(ngx.ERR, "[API-KEY] Directory not set.")
        return false, "missing directory"
    end

    ngx.log(ngx.INFO, "[API-KEY] loading keys from dir: ", dir)
    local handle = io.popen("ls -1 " .. dir)
    if not handle then
        ngx.log(ngx.ERR, "[API-KEY] Failed to list files in ", dir)
        return false, "failed to list dir"
    end

    local new_keys = {}
    for filename in handle:lines() do
        local path = dir .. "/" .. filename
        local f = io.open(path, "r")
        if f then
            local key = f:read("*l")
            f:close()
            if key and #key > 0 then
                new_keys[filename] = key
            else
                ngx.log(ngx.ERR, "[API-KEY] Empty or invalid key in file: ", filename)
            end
        else
            ngx.log(ngx.ERR, "[API-KEY] Failed to open: ", path)
        end
    end
    handle:close()

    local keys_to_remove = {}
    local existing_keys = dict:get_keys(0)
    for _, k in ipairs(existing_keys) do
        if k:match("^api_key_") then
            local filename = k:sub(9)
            if not new_keys[filename] then
                dict:delete(k)
                ngx.log(ngx.NOTICE, "[API-KEY] Removed stale key: ", filename)
            end
        end
    end

    for filename, key in pairs(new_keys) do
        dict:set("api_key_" .. filename, key)
        ngx.log(ngx.INFO, "[API-KEY] Loaded key file: ", filename)
    end

    return true, "OK"
end

function _M.verify(api_key_name)
    local expected = dict:get("api_key_" .. api_key_name)
    if not expected then
        ngx.log(ngx.ERR, "[API-KEY] No key found for: ", api_key_name)
        return false, "API key not configured"
    end

    local actual = ngx.req.get_headers()["X-SECDN-API-KEY"]
    if not actual or actual ~= expected then
        return false, "Invalid API Key"
    end

    return true, "OK"
end

function _M.list()
    local keys = dict:get_keys(0)
    local result = {}
    for _, k in ipairs(keys) do
        if k:match("^api_key_") then
            table.insert(result, k:sub(9))
        end
    end
    return result
end

return _M
