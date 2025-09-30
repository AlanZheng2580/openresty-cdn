package.path = '/opt/bitnami/openresty/nginx/lua/?.lua;' .. package.path

local function deep_compare(t1, t2)
    if type(t1) ~= 'table' or type(t2) ~= 'table' then
        return t1 == t2
    end

    local keys1 = {}
    for k in pairs(t1) do table.insert(keys1, k) end
    local keys2 = {}
    for k in pairs(t2) do table.insert(keys2, k) end

    if #keys1 ~= #keys2 then return false end

    for _, k in ipairs(keys1) do
        if not deep_compare(t1[k], t2[k]) then
            print("Mismatch at key: " .. tostring(k))
            print("Got: ", t1[k])
            print("Expected: ", t2[k])
            return false
        end
    end
    return true
end

ngx.utctime = function()
    return "2025-09-24T09:02:38Z"
end

local aws_v4_signer = require("aws_v4_signer")

print("Running AWS V4 Signer test...")

local args = {
    schema = "http",
    host = "localhost:9000",
    access_key = "test_access_key",
    secret_key = "test_secret_key",
    bucket = "bucket-a",
    object = "test.txt",
    region = "us-east-1",
    method = "GET",
    body = ""
}

local result = aws_v4_signer.build(args)

-- Calculate AWS V4 Signature: https://datafetcher.com/aws-signature-version-4-calculator
local expected = {
    host = "localhost:9000",
    amz_date = "20250924T090238Z",
    -- Corrected signature based on the new hash
    authorization = "AWS4-HMAC-SHA256 Credential=test_access_key/20250924/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=6f682cd9cfd1c12671faf839587bd8b42f780f5b582624432e318385f905bb22",
    payload_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    bucket_url = "http://localhost:9000/bucket-a/test.txt",
    -- Corrected string_to_sign with the correct canonical request hash
    string_to_sign = table.concat({
        "AWS4-HMAC-SHA256",
        "20250924T090238Z",
        "20250924/us-east-1/s3/aws4_request",
        "c807f34d325c67bc85a0982e004de24b851319f4913217a5069c9469d2456bbe"
    }, "\n"),
    canonical_request = table.concat({
        "GET",
        "/bucket-a/test.txt",
        "",
        "host:localhost:9000\nx-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nx-amz-date:20250924T090238Z\n",
        "host;x-amz-content-sha256;x-amz-date",
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }, "\n")
}

assert(deep_compare(result, expected), "Test failed: Result does not match expected output.")

print("\n[SUCCESS] All tests passed!")
