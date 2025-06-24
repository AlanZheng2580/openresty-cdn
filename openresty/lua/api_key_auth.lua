local _M = {}
local dict = ngx.shared.secrets
local resty_string = require "resty.string"
local base64 = require "ngx.base64"

-- Function to convert a hex string to binary (raw bytes)
local function hex_to_binary(hex)
    return (hex:gsub('..', function (cc)
        return string.char(tonumber(cc, 16))
    end))
end

-- Utility function to parse the cookie into key-value pairs
local function parse_cookie(cookie_value)
    local cookie_data = {}

    -- Split the cookie string by ":"
    local segments = {}
    for segment in string.gmatch(cookie_value, "([^:]+)") do
        table.insert(segments, segment)
    end

    -- Iterate over each segment and split by the first "=" to extract key and value
    for _, segment in ipairs(segments) do
        local key, value = string.match(segment, "([%w%-_]+)=(.+)")
        if key and value then
            cookie_data[key] = value
        end
    end

    return cookie_data
end

-- Check if all required fields are present
local function check_required_fields(cookie_data)
    local required_fields = {"URLPrefix", "Expires", "KeyName", "Signature"}
    for _, field in ipairs(required_fields) do
        if not cookie_data[field] then
            ngx.log(ngx.ERR, "[HMAC] Missing required cookie field: " .. field)
            return false, "Missing required field: " .. field
        end
    end
    return true
end

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

-- Verify cookie and HMAC signature
-- Example: Set-Cookie: SECDN-CDN-Cookie=URLPrefix=aHR0cHM6Ly9tZWRpYS5leGFtcGxlLmNvbS92aWRlb3Mv:Expires=1566268009:KeyName=mySigningKey:Signature=0W2xlMlQykL2TG59UZnnHzkxoaw=; Domain=media.example.com; Path=/; Expires=Tue, 20 Aug 2019 02:26:49 GMT; HttpOnly
function _M.verify_cookie(api_key_name)
    -- Fetch the signed cookie from the request
    local cookie_value = ngx.var["cookie_secdn-cdn-cookie"]  -- 'SECDN-CDN-Cookie' will be used here (in lowercase)
    if not cookie_value then
        ngx.log(ngx.ERR, "[HMAC] Missing cookie: SECDN-CDN-Cookie")
        return false, "Cookie not found"
    end

    ngx.log(ngx.INFO, "[HMAC] Cookie: " .. cookie_value)

    -- Parse cookie values (URLPrefix, Expires, KeyName, Signature)
    local cookie_data = parse_cookie(cookie_value)

    -- Check if all required fields are present
    local valid, err = check_required_fields(cookie_data)
    if not valid then
        return false, err
    end

    -- Retrieve the secret key for this cookie
    if api_key_name ~= cookie_data.KeyName then
        ngx.log(ngx.ERR, "[HMAC] Invalid API Key name in cookie")
        return false, "Invalid API Key name"
    end
    local api_key = dict:get("api_key_" .. api_key_name)

    if not api_key then
        ngx.log(ngx.ERR, "[HMAC] No key found for KeyName: ", api_key_name)
        return false, "Invalid API Key"
    end

    -- Convert hex string to binary for HMAC key
    local hmac_key = hex_to_binary(api_key)

    -- Verify HMAC signature
    local data_to_sign = "URLPrefix=" .. cookie_data.URLPrefix .. ":Expires=" .. cookie_data.Expires .. ":KeyName=" .. cookie_data.KeyName
    local expected_signature = base64.encode_base64url(ngx.hmac_sha1(hmac_key, data_to_sign))
    -- Calculate the required padding length
    local padding_length = 4 - (#expected_signature % 4)
    if padding_length ~= 4 then
        expected_signature = expected_signature .. string.rep("=", padding_length)
    end

    ngx.log(ngx.INFO, "[HMAC] expected_signature: " .. expected_signature)

    if cookie_data.Signature ~= expected_signature then
        ngx.log(ngx.ERR, "[HMAC] Invalid signature in cookie")
        return false, "Invalid HMAC signature"
    end

    -- Check if the cookie has expired
    local expires = tonumber(cookie_data.Expires)
    if not expires or expires < ngx.time() then
        ngx.log(ngx.ERR, "[HMAC] Cookie has expired")
        return false, "Cookie expired"
    end

    -- Decode URLPrefix from base64
    local url_prefix = ngx.decode_base64(cookie_data.URLPrefix)
    if not url_prefix then
        ngx.log(ngx.ERR, "[HMAC] Invalid URLPrefix in cookie")
        return false, "Invalid URLPrefix"
    end

    -- Validate URL prefix (match URL)
    local request_url = ngx.var.request_uri
    if not ngx.re.match(request_url, url_prefix) then
        ngx.log(ngx.ERR, "[HMAC] URL does not match URLPrefix in cookie")
        return false, "URL does not match URLPrefix"
    end

    ngx.log(ngx.INFO, "[HMAC] Valid cookie for URL: ", request_url)
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
