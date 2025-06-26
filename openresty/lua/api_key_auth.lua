local _M = {}
local dict = ngx.shared.secrets
local resty_string = require "resty.string"
local base64 = require "ngx.base64"

-- Convert hex string (e.g. "abcdef1234") to binary string (raw bytes)
local function hex_to_binary(hex)
    return (hex:gsub('..', function (cc)
        return string.char(tonumber(cc, 16))
    end))
end

-- Fast, fixed-format cookie parser
-- e.g.: URLPrefix=aHR0cDovL2xvY2FsaG9zdDo4MDgwL3Rlc3QvY29va2llL29r:Expires=1753055999:KeyName=user-a:Signature=bd1SquQdQhGK4rURuiufrg8m0Vs=
local function parse_cookie(cookie_value)
    local m, err = ngx.re.match(cookie_value, [[^URLPrefix=([^:]+):Expires=(\d+):KeyName=([\w\-]+):Signature=([A-Za-z0-9\-_]+=*)$]], "jo")
    if not m then
        return nil, "Invalid cookie format"
    end

    return {
        URLPrefix = m[1],
        Expires   = m[2],
        KeyName   = m[3],
        Signature = m[4],
    }, nil
end

-- Parse a full URL into its components
local function parse_url(url)
    local m, err = ngx.re.match(url, [[^(https?)://([^:/]+)(?::(\d+))?(/.*)$]], "jo")
    if not m then
        return nil, "Invalid URL format"
    end

    return {
        scheme = m[1],  -- http or https
        host = m[2],    -- domain or IP
        port = m[3],    -- optional port string
        uri = m[4],     -- URI path (e.g., /video/abc.mp4)
    }, nil
end

-- Compare current request against the signed URLPrefix
local function verify_request_matches_prefix(prefix_url)
    -- Parse the URLPrefix from cookie
    local parsed_prefix, err = parse_url(prefix_url)
    if not parsed_prefix then
        ngx.log(ngx.ERR, "[AUTH] Failed to parse URLPrefix: ", err)
        return false, "Invalid URLPrefix format"
    end

    -- Get request components
    local scheme = ngx.var.scheme          -- e.g., "http"
    local host = ngx.var.host              -- e.g., "localhost"
    local port = ngx.var.server_port       -- e.g., "8080"
    local uri = ngx.var.request_uri        -- e.g., "/test/cookie/ok/abc.jpg"

    -- Compare scheme
    if scheme ~= parsed_prefix.scheme then
        ngx.log(ngx.ERR, "[AUTH] Scheme mismatch (expected: ", parsed_prefix.scheme, ", got: ", scheme, ")")
        return false, "Scheme mismatch"
    end

    -- Compare host
    if host ~= parsed_prefix.host then
        ngx.log(ngx.ERR, "[AUTH] Host mismatch (expected: ", parsed_prefix.host, ", got: ", host, ")")
        return false, "Host mismatch"
    end

    -- Compare port (default to 80 or 443 if not present)
    -- Port comparison is skipped because in Kubernetes
    -- local default_port = (parsed_prefix.scheme == "http" and "80") or (parsed_prefix.scheme == "https" and "443")
    -- local expected_port = parsed_prefix.port or default_port
    -- if port ~= expected_port then
    --     ngx.log(ngx.ERR, "[AUTH] Port mismatch (expected: ", expected_port, ", got: ", port, ")")
    --     return false, "Port mismatch"
    -- end

    -- Compare URI prefix
    if uri:sub(1, #parsed_prefix.uri) ~= parsed_prefix.uri then
        ngx.log(ngx.ERR, "[AUTH] URI mismatch (expected prefix: ", parsed_prefix.uri, ", got: ", uri, ")")
        return false, "URI prefix mismatch"
    end

    return true, "OK"
end

-- Load API keys from disk and cache both plain and binary formats
function _M.load(dir)
    if not dir then
        ngx.log(ngx.ERR, "[AUTH] Directory not set.")
        return false, "missing directory"
    end

    ngx.log(ngx.INFO, "[AUTH] loading keys from dir: ", dir)
    local handle = io.popen("ls -1 " .. dir)
    if not handle then
        ngx.log(ngx.ERR, "[AUTH] Failed to list files in ", dir)
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
                ngx.log(ngx.ERR, "[AUTH] Empty or invalid key in file: ", filename)
            end
        else
            ngx.log(ngx.ERR, "[AUTH] Failed to open: ", path)
        end
    end
    handle:close()

    -- Remove outdated keys from dict
    local existing_keys = dict:get_keys(0)
    for _, k in ipairs(existing_keys) do
        if k:match("^api_key_") then
            local filename = k:sub(9)
            if not new_keys[filename] then
                dict:delete(k)
                ngx.log(ngx.NOTICE, "[AUTH] Removed stale key: ", filename)
            end
        elseif k:match("^b_api_key_") then
            local filename = k:sub(11)
            if not new_keys[filename] then
                dict:delete(k)
                ngx.log(ngx.NOTICE, "[AUTH] Removed stale binary key: ", filename)
            end
        end
    end

    -- Store both raw hex and binary
    for filename, key in pairs(new_keys) do
        dict:set("api_key_" .. filename, key)
        dict:set("b_api_key_" .. filename, hex_to_binary(key))
        ngx.log(ngx.INFO, "[AUTH] Loaded key file: ", filename)
    end

    return true, "OK"
end

-- Header-based API key verification
function _M.verify(api_key_name)
    local expected = dict:get("api_key_" .. api_key_name)
    if not expected then
        ngx.log(ngx.ERR, "[AUTH] No key found for: ", api_key_name)
        return false, "API key not configured"
    end

    local actual = ngx.req.get_headers()["X-SECDN-API-KEY"]
    if not actual or actual ~= expected then
        ngx.log(ngx.ERR, "[AUTH] Invalid API Key: ", api_key_name)
        return false, "Invalid API Key"
    end

    return true, "OK"
end

-- Cookie-based HMAC signature verification
-- Example: Set-Cookie: SECDN-CDN-Cookie=URLPrefix=aHR0cHM6Ly9tZWRpYS5leGFtcGxlLmNvbS92aWRlb3Mv:Expires=1566268009:KeyName=mySigningKey:Signature=0W2xlMlQykL2TG59UZnnHzkxoaw=; Domain=media.example.com; Path=/; Expires=Tue, 20 Aug 2019 02:26:49 GMT; HttpOnly
function _M.verify_cookie(api_key_name)
    -- Fetch the signed cookie from the request
    local cookie_value = ngx.var["cookie_secdn-cdn-cookie"]  -- 'SECDN-CDN-Cookie' will be used here (in lowercase)
    if not cookie_value then
        ngx.log(ngx.ERR, "[AUTH] Missing cookie: SECDN-CDN-Cookie")
        return false, "Cookie not found"
    end

    ngx.log(ngx.INFO, "[AUTH] Cookie: " .. cookie_value)

    -- Parse cookie values (URLPrefix, Expires, KeyName, Signature)
    local cookie_data, err = parse_cookie(cookie_value)
    if not cookie_data then
        ngx.log(ngx.ERR, "[AUTH] Cookie parse error: ", err)
        return false, "Invalid cookie format"
    end

    -- Retrieve the secret key for this cookie
    if api_key_name ~= cookie_data.KeyName then
        ngx.log(ngx.ERR, "[AUTH] Invalid KeyName in cookie")
        return false, "Invalid API Key name"
    end

    local b_api_key = dict:get("b_api_key_" .. api_key_name)
    if not b_api_key then
        ngx.log(ngx.ERR, "[AUTH] No binary key for: ", api_key_name)
        return false, "Invalid binary API Key"
    end

    -- Verify HMAC signature
    local data_to_sign = "URLPrefix=" .. cookie_data.URLPrefix .. ":Expires=" .. cookie_data.Expires .. ":KeyName=" .. cookie_data.KeyName
    local expected_signature = base64.encode_base64url(ngx.hmac_sha1(b_api_key, data_to_sign))
    -- Calculate the required padding length
    if #expected_signature % 4 ~= 0 then
        expected_signature = expected_signature .. string.rep("=", 4 - (#expected_signature % 4))
    end

    ngx.log(ngx.INFO, "[AUTH] expected_signature: " .. expected_signature)
    if cookie_data.Signature ~= expected_signature then
        ngx.log(ngx.ERR, "[AUTH] Invalid signature in cookie")
        return false, "Invalid HMAC signature"
    end

    -- Check if the cookie has expired
    local expires = tonumber(cookie_data.Expires)
    if not expires or expires < ngx.time() then
        ngx.log(ngx.ERR, "[AUTH] Cookie has expired")
        return false, "Cookie expired"
    end

    -- Decode URLPrefix from base64
    local url_prefix = ngx.decode_base64(cookie_data.URLPrefix)
    if not url_prefix then
        ngx.log(ngx.ERR, "[AUTH] Invalid URLPrefix in cookie")
        return false, "Invalid URLPrefix"
    end

    -- Validate URL prefix (match URL)
    local ok, err = verify_request_matches_prefix(url_prefix)
    if not ok then
        return false, err
    end

    return true, "OK"
end

-- List all currently loaded API key names
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
