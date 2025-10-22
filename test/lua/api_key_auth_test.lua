-- test/lua/api_key_auth_test.lua

-- Tell resty where to find our modules
package.path = '/opt/bitnami/openresty/nginx/lua/?.lua;' .. package.path

--------------------------------------------------------------------------------
-- MOCK SETUP
--------------------------------------------------------------------------------
-- Create a mock_ngx object that initially copies all real ngx functions/tables
local mock_ngx = {}
for k, v in pairs(_G.ngx) do
    mock_ngx[k] = v
end

-- Helper to reset mocks before a test group
local function setup_mocks(config)
    config = config or {}

    -- Use the REAL ngx.shared.secrets, just flush it.
    if mock_ngx and mock_ngx.shared and mock_ngx.shared.secrets then
        mock_ngx.shared.secrets:flush_all()
    end

    -- Overwrite ngx.req with a mock implementation
    mock_ngx.req = {
        get_headers = function() return config.headers or {} end,
        get_uri_args = function() return config.uri_args or {} end,
        set_uri_args = function() end, -- Dummy function
        set_header = function() end -- Dummy function
    }

    -- Overwrite ngx.var with a mock table
    mock_ngx.var = {
        scheme = config.vars and config.vars.scheme or nil,
        host = config.vars and config.vars.host or nil,
        server_port = config.vars and config.vars.server_port or nil,
        request_uri = config.vars and config.vars.request_uri or nil,
        ["cookie_secdn-cdn-cookie"] = config.vars and config.vars["cookie_secdn-cdn-cookie"] or nil,
        http_host = config.vars and config.vars.http_host or nil
    }

    -- Overwrite ngx.time and ngx.log
    mock_ngx.time = function() return 1727172000 end -- Fixed time: 2024-09-24 10:00:00 GMT
    mock_ngx.log = function(...) end -- Dummy log function
    mock_ngx.decode_base64 = ngx.decode_base64
end

-- CRITICAL: Assign the mock object to the global scope BEFORE requiring the module.
_G.ngx = mock_ngx

local api_key_auth = require("api_key_auth")
local base64 = require("ngx.base64")

-- Reusable assertion helper
local function assert_equal(actual, expected, message)
    assert(actual == expected, string.format("%s: expected '%s', got '%s'", message, tostring(expected), tostring(actual)))
end

-- Helper to convert hex to binary, copied from module for test generation
local function hex_to_binary(hex)
    return (hex:gsub('..', function (cc)
        return string.char(tonumber(cc, 16))
    end))
end

-- source_type is "Cookie" or "Signed URL Prefix" for logging
local function generate_signature(prefix_b64, expires, key_name, binary_key, source_type)
    local data_to_sign
    if source_type == "Cookie" then
        data_to_sign = "URLPrefix=" .. prefix_b64 .. ":Expires=" .. expires .. ":KeyName=" .. key_name
    else -- "Signed URL Prefix"
        data_to_sign = "URLPrefix=" .. prefix_b64 .. "&Expires=" .. expires .. "&KeyName=" .. key_name
    end
    local signature = base64.encode_base64url(ngx.hmac_sha1(binary_key, data_to_sign))
    if #signature % 4 ~= 0 then
        signature = signature .. string.rep("=", 4 - (#signature % 4))
    end
    return signature
end

local test_key_name = "user-b"
local test_hex_key = "12345678901234567890123456789012"
local test_binary_key = hex_to_binary(test_hex_key)
local test_url_prefix = "http://example.com/videos/"
local test_url_prefix_b64 = base64.encode_base64url(test_url_prefix)
local expires_time = ngx.time() + 3600 -- Expires in 1 hour

--------------------------------------------------------------------------------
-- TEST SUITE: _M.verify (Header Auth)
--------------------------------------------------------------------------------
print("\nRunning tests for: _M.verify (Header Auth)")

-- Test 1.1: Valid API Key
setup_mocks({ headers = { ["X-SECDN-API-KEY"] = test_hex_key } })
ngx.shared.secrets:set("api_key_" .. test_key_name, test_hex_key)
local status, err = api_key_auth.verify(test_key_name)
assert_equal(status, mock_ngx.HTTP_OK, "Test 1.1.1 failed")
assert_equal(err, "OK", "Test 1.1.2 failed")
print("  [PASS] Test 1.1: Valid API Key")

-- Test 1.2: Invalid API Key
setup_mocks({ headers = { ["X-SECDN-API-KEY"] = "wrong_key" } })
ngx.shared.secrets:set("api_key_" .. test_key_name, test_hex_key)
local status, err = api_key_auth.verify(test_key_name)
assert_equal(status, mock_ngx.HTTP_FORBIDDEN, "Test 1.2.1 failed")
assert_equal(err, "Invalid API Key", "Test 1.2.2 failed")
print("  [PASS] Test 1.2: Invalid API Key")

-- Test 1.3: Missing API Key Header
setup_mocks() -- No headers
ngx.shared.secrets:set("api_key_" .. test_key_name, test_hex_key)
local status, err = api_key_auth.verify(test_key_name)
assert_equal(status, mock_ngx.HTTP_BAD_REQUEST, "Test 1.3.1 failed")
assert_equal(err, "Missing API Key header", "Test 1.3.2 failed")
print("  [PASS] Test 1.3: Missing API Key Header")

-- Test 1.4: Key not configured in secrets
setup_mocks({ headers = { ["X-SECDN-API-KEY"] = test_hex_key } })
-- No key is set in secrets
local status, err = api_key_auth.verify(test_key_name)
assert_equal(status, mock_ngx.HTTP_INTERNAL_SERVER_ERROR, "Test 1.4.1 failed - should fail")
assert_equal(err, "API key not configured", "Test 1.4.2 failed")
print("  [PASS] Test 1.4: Key not configured")

--------------------------------------------------------------------------------
-- TEST SUITE: _M.verify_cookie
--------------------------------------------------------------------------------
print("\nRunning tests for: _M.verify_cookie")

-- Test 2.1: Valid Cookie
local cookie_signature = generate_signature(test_url_prefix_b64, expires_time, test_key_name, test_binary_key, "Cookie")
local cookie_value = "URLPrefix=" .. test_url_prefix_b64 .. ":Expires=" .. expires_time .. ":KeyName=" .. test_key_name .. ":Signature=" .. cookie_signature
local cookie_vars = {
    scheme = "http",
    host = "example.com",
    server_port = "80",
    request_uri = "/videos/movie.mp4",
    ["cookie_secdn-cdn-cookie"] = cookie_value
}

setup_mocks({
    vars = cookie_vars
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
local status, err = api_key_auth.verify_cookie(test_key_name)
assert_equal(status, mock_ngx.HTTP_OK, "Test 2.1.1 failed")
assert_equal(err, "OK", "Test 2.1.2 failed")
print("  [PASS] Test 2.1: Valid cookie")

-- Test 2.2: Expired Cookie
setup_mocks({
    vars = cookie_vars
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
mock_ngx.time = function() return expires_time + 1 end -- Time travel to after expiration
local status, err = api_key_auth.verify_cookie(test_key_name)
assert_equal(status, mock_ngx.HTTP_FORBIDDEN, "Test 2.2.1 failed")
assert_equal(err, "Cookie expired", "Test 2.2.2 failed")
print("  [PASS] Test 2.2: Expired cookie")
mock_ngx.time = function() return mock_ngx.time() - 1 end -- Reset time

-- Test 2.3: Invalid Signature
local tampered_cookie_value = cookie_value:gsub("Signature=..", "Signature=XX") -- Tamper signature
setup_mocks({
    vars = {
        scheme = "http",
        host = "example.com",
        server_port = "80",
        request_uri = "/videos/movie.mp4",
        ["cookie_secdn-cdn-cookie"] = tampered_cookie_value
    }
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
local status, err = api_key_auth.verify_cookie(test_key_name)
assert_equal(status, mock_ngx.HTTP_FORBIDDEN, "Test 2.3.1 failed")
assert_equal(err, "Invalid HMAC signature", "Test 2.3.2 failed")
print("  [PASS] Test 2.3: Invalid signature")

-- Test 2.4: Mismatched Request URI
setup_mocks({
    vars = {
        scheme = "http",
        host = "example.com",
        server_port = "80",
        request_uri = "/another/path/movie.mp4", -- Mismatched URI
        ["cookie_secdn-cdn-cookie"] = cookie_value
    }
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
local status, err = api_key_auth.verify_cookie(test_key_name)
assert_equal(status, mock_ngx.HTTP_FORBIDDEN, "Test 2.4.1 failed")
assert_equal(err, "URI prefix mismatch", "Test 2.4.2 failed")
print("  [PASS] Test 2.4: Mismatched Request URI")

-- Test 2.5: Missing Cookie
setup_mocks({
    vars = {
        scheme = "http",
        host = "example.com",
        server_port = "80",
        request_uri = "/videos/movie.mp4",
        -- Missing 'cookie_secdn-cdn-cookie'
    }
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
local status, err = api_key_auth.verify_cookie(test_key_name)
assert_equal(status, mock_ngx.HTTP_BAD_REQUEST, "Test 2.5.1 failed")
assert_equal(err, "Cookie not found", "Test 2.5.2 failed")
print("  [PASS] Test 2.5: Missing Cookie")

-- Test 2.6: Malformed Cookie String
setup_mocks({
    vars = {
        scheme = "http",
        host = "example.com",
        server_port = "80",
        request_uri = "/videos/movie.mp4",
        ["cookie_secdn-cdn-cookie"] = "InvalidCookieFormat"
    }
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
local status, err = api_key_auth.verify_cookie(test_key_name)
assert_equal(status, mock_ngx.HTTP_BAD_REQUEST, "Test 2.6.1 failed")
assert_equal(err, "Invalid cookie format", "Test 2.6.2 failed")
print("  [PASS] Test 2.6: Malformed Cookie String")

-- Test 2.7: KeyName Mismatch
local mismatched_cookie_signature = generate_signature(test_url_prefix_b64, expires_time, "wrong-key", test_binary_key, "Cookie")
local mismatched_cookie_value = "URLPrefix=" .. test_url_prefix_b64 .. ":Expires=" .. expires_time .. ":KeyName=wrong-key:Signature=" .. mismatched_cookie_signature
setup_mocks({
    vars = {
        scheme = "http",
        host = "example.com",
        server_port = "80",
        request_uri = "/videos/movie.mp4",
        ["cookie_secdn-cdn-cookie"] = mismatched_cookie_value
    }
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
local status, err = api_key_auth.verify_cookie(test_key_name)
assert_equal(status, mock_ngx.HTTP_FORBIDDEN, "Test 2.7.1 failed")
assert_equal(err, "Invalid API Key name", "Test 2.7.2 failed")
print("  [PASS] Test 2.7: KeyName Mismatch")

-- Test 2.8: Binary Key Not Found
setup_mocks({
    vars = cookie_vars -- Use the valid cookie vars from 2.1
})
-- ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key) -- Key not set
local status, err = api_key_auth.verify_cookie(test_key_name)
assert_equal(status, mock_ngx.HTTP_INTERNAL_SERVER_ERROR, "Test 2.8.1 failed")
assert_equal(err, "Invalid binary API Key", "Test 2.8.2 failed")
print("  [PASS] Test 2.8: Binary Key Not Found")

--------------------------------------------------------------------------------
-- TEST SUITE: _M.verify_signed_url_prefix
--------------------------------------------------------------------------------
print("\nRunning tests for: _M.verify_signed_url_prefix")

local url_prefix_vars = {
    scheme = "http",
    host = "example.com",
    server_port = "80",
    request_uri = "/videos/movie.mp4?some_other_param=1",
    http_host = "example.com" -- Added for X-Client-Request-URL
}
local url_prefix_uri_args = {
    URLPrefix = test_url_prefix_b64,
    Expires = tostring(expires_time),
    KeyName = test_key_name,
    Signature = generate_signature(test_url_prefix_b64, expires_time, test_key_name, test_binary_key, "Signed URL Prefix")
}

-- Test 3.1: Valid Signed URL Prefix (from previous run)
setup_mocks({
    vars = url_prefix_vars,
    uri_args = url_prefix_uri_args
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
local status, err = api_key_auth.verify_signed_url_prefix(test_key_name)
assert_equal(status, mock_ngx.HTTP_OK, "Test 3.1.1 failed")
assert_equal(err, "OK", "Test 3.1.2 failed")
print("  [PASS] Test 3.1: Valid signed URL Prefix")

-- Test 3.2: Expired Signed URL Prefix (from previous run)
setup_mocks({
    vars = url_prefix_vars,
    uri_args = url_prefix_uri_args
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
mock_ngx.time = function() return expires_time + 1 end -- Time travel to after expiration
local status, err = api_key_auth.verify_signed_url_prefix(test_key_name)
assert_equal(status, mock_ngx.HTTP_FORBIDDEN, "Test 3.2.1 failed")
assert_equal(err, "Signed URL Prefix expired", "Test 3.2.2 failed")
print("  [PASS] Test 3.2: Expired Signed URL Prefix")
mock_ngx.time = function() return 1727172000 end -- Reset time

-- Test 3.3: Invalid Signature
local tampered_uri_args = {
    URLPrefix = test_url_prefix_b64,
    Expires = tostring(expires_time),
    KeyName = test_key_name,
    Signature = url_prefix_uri_args.Signature:gsub("=", "X") -- Tamper signature
}
setup_mocks({
    vars = url_prefix_vars,
    uri_args = tampered_uri_args
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
local status, err = api_key_auth.verify_signed_url_prefix(test_key_name)
assert_equal(status, mock_ngx.HTTP_FORBIDDEN, "Test 3.3.1 failed")
assert_equal(err, "Invalid HMAC signature", "Test 3.3.2 failed")
print("  [PASS] Test 3.3: Invalid Signature")

-- Test 3.4: Mismatched Request URI
local mismatched_url_prefix_vars = {
    scheme = "http",
    host = "example.com",
    server_port = "80",
    request_uri = "/another/path/movie.mp4?some_other_param=1", -- Mismatched URI
    http_host = "example.com"
}
setup_mocks({
    vars = mismatched_url_prefix_vars,
    uri_args = url_prefix_uri_args
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
local status, err = api_key_auth.verify_signed_url_prefix(test_key_name)
assert_equal(status, mock_ngx.HTTP_FORBIDDEN, "Test 3.4.1 failed")
assert_equal(err, "URI prefix mismatch", "Test 3.4.2 failed")
print("  [PASS] Test 3.4: Mismatched Request URI")

-- Test 3.5: Missing Query Parameters
setup_mocks({
    vars = url_prefix_vars,
    uri_args = {
        URLPrefix = test_url_prefix_b64,
        Expires = tostring(expires_time),
        KeyName = test_key_name
        -- Signature is missing
    }
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
local status, err = api_key_auth.verify_signed_url_prefix(test_key_name)
assert_equal(status, mock_ngx.HTTP_BAD_REQUEST, "Test 3.5.1 failed")
assert_equal(err, "Missing one or more of: URLPrefix, Expires, KeyName, Signature", "Test 3.5.2 failed")
print("  [PASS] Test 3.5: Missing Query Parameters")

-- Test 3.6: KeyName Mismatch
local mismatched_url_prefix_uri_args = {
    URLPrefix = test_url_prefix_b64,
    Expires = tostring(expires_time),
    KeyName = "wrong-key",
    Signature = generate_signature(test_url_prefix_b64, expires_time, "wrong-key", test_binary_key, "Signed URL Prefix")
}
setup_mocks({
    vars = url_prefix_vars,
    uri_args = mismatched_url_prefix_uri_args
})
ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key)
local status, err = api_key_auth.verify_signed_url_prefix(test_key_name)
assert_equal(status, mock_ngx.HTTP_FORBIDDEN, "Test 3.6.1 failed")
assert_equal(err, "Invalid API Key name", "Test 3.6.2 failed")
print("  [PASS] Test 3.6: KeyName Mismatch")

-- Test 3.7: Binary Key Not Found
setup_mocks({
    vars = url_prefix_vars,
    uri_args = url_prefix_uri_args
})
-- ngx.shared.secrets:set("b_api_key_" .. test_key_name, test_binary_key) -- Key not set
local status, err = api_key_auth.verify_signed_url_prefix(test_key_name)
assert_equal(status, mock_ngx.HTTP_INTERNAL_SERVER_ERROR, "Test 3.7.1 failed")
assert_equal(err, "Invalid binary API Key", "Test 3.7.2 failed")
print("  [PASS] Test 3.7: Binary Key Not Found")


print("\n[SUCCESS] All tests passed!")