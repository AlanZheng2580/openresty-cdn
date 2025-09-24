-- test/lua/api_key_auth_test.lua

-- Tell resty where to find our modules
package.path = '/opt/bitnami/openresty/nginx/lua/?.lua;' .. package.path

-- Mock container for ngx APIs
local mock_ngx = {
    req = {},
    log = function(...) end -- Dummy log function
}

-- Helper to reset mocks before a test group
local function setup_mocks(headers_to_set)
    -- Mock ngx.req.get_headers
    mock_ngx.req.get_headers = function() return headers_to_set or {} end

    -- IMPORTANT: We are now using the REAL ngx.shared dictionary provided by resty
    -- We just need to clear it before each test run.
    if _G.ngx and _G.ngx.shared and _G.ngx.shared.secrets then
        _G.ngx.shared.secrets:flush_all()
    end

    -- Replace parts of the global ngx object with our mock
    _G.ngx.req = mock_ngx.req
    _G.ngx.log = mock_ngx.log
end

-- CRITICAL: Set a dummy req object on the real ngx BEFORE requiring the module
-- This prevents errors if the module accesses ngx.req at load time.
if not _G.ngx then _G.ngx = {} end
_G.ngx.req = {}

local api_key_auth = require("api_key_auth")

-- Reusable assertion helper
local function assert_equal(actual, expected, message)
    assert(actual == expected, string.format("%s: expected '%s', got '%s'", message, tostring(expected), tostring(actual)))
end


-- ===== Test Suite for _M.verify =====
print("\nRunning tests for: _M.verify (Header Auth)")

-- Test 1: Valid API Key
setup_mocks({ ["X-SECDN-API-KEY"] = "secret123" })
ngx.shared.secrets:set("api_key_user-a", "secret123")
local ok, err = api_key_auth.verify("user-a")
assert_equal(ok, true, "Test 1.1 failed - should be OK")
assert_equal(err, "OK", "Test 1.2 failed - should return OK message")
print("  [PASS] Test 1: Valid API Key")

-- Test 2: Invalid API Key
setup_mocks({ ["X-SECDN-API-KEY"] = "wrong_key" })
ngx.shared.secrets:set("api_key_user-a", "secret123")
local ok, err = api_key_auth.verify("user-a")
assert_equal(ok, false, "Test 2.1 failed - should fail")
assert_equal(err, "Invalid API Key", "Test 2.2 failed - should return correct error")
print("  [PASS] Test 2: Invalid API Key")

-- Test 3: Missing API Key Header
setup_mocks() -- No headers
ngx.shared.secrets:set("api_key_user-a", "secret123")
local ok, err = api_key_auth.verify("user-a")
assert_equal(ok, false, "Test 3.1 failed - should fail")
assert_equal(err, "Invalid API Key", "Test 3.2 failed - should return correct error")
print("  [PASS] Test 3: Missing API Key Header")

-- Test 4: Key not configured in secrets
setup_mocks({ ["X-SECDN-API-KEY"] = "secret123" })
-- No key is set in secrets
local ok, err = api_key_auth.verify("user-a")
assert_equal(ok, false, "Test 4.1 failed - should fail")
assert_equal(err, "API key not configured", "Test 4.2 failed - should return correct error")
print("  [PASS] Test 4: Key not configured")


print("\n[SUCCESS] All api_key_auth.verify tests passed!")
