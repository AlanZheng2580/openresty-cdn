-- test cmd: TEST_ACCESS_KEY=bucketa-key TEST_SECRET_KEY=bucketa-secret TEST_BUCKET=bucket-a TEST_OBJECT=hello.txt resty test_signer.lua
local signer = require "aws_v4_signer"

-- 解析 CLI 引數
local args = {}
for _, arg in ipairs(arg) do
    local key, val = arg:match("^%-%-([^=]+)=(.*)$")
    if key and val then
        args[key] = val
    end
end

-- 預設值（環境變數 or fallback）
local access_key = args.access_key or os.getenv("TEST_ACCESS_KEY") or "bucketa-key"
local secret_key = args.secret_key or os.getenv("TEST_SECRET_KEY") or "bucketa-secret"
local host       = args.host or os.getenv("TEST_MINIO_HOST") or "minio:9000"
local bucket     = args.bucket or os.getenv("TEST_BUCKET") or "bucket-a"
local object     = args.object or os.getenv("TEST_OBJECT") or "hello.txt"
local method     = args.method or "GET"
local body       = args.body or ""

local sig = signer.build{
    access_key = access_key,
    secret_key = secret_key,
    host = host,
    bucket = bucket,
    object = object,
    method = method,
    body = body,
}

print("🔐 AWS Signature V4 Headers:")
print("Host: " .. sig.host)
print("x-amz-date: " .. sig.amz_date)
print("Authorization: " .. sig.authorization)
print("----\nCanonical Request:\n" .. sig.canonical_request)
print("----\nString to Sign:\n" .. sig.string_to_sign)
print("----\nPayload Hash: " .. sig.payload_hash)
print("----\n")

print("🧪 Example curl command:\n")
print(string.format([[
curl -v -X %s "%s" \
  -H "Host: %s" \
  -H "x-amz-date: %s" \
  -H "x-amz-content-sha256: %s" \
  -H "Authorization: %s" %s
]], method, sig.bucket_url, sig.host, sig.amz_date, sig.payload_hash, sig.authorization,
   (#body > 0) and string.format("-d '%s'", body) or ""))
