local http = require "resty.http"
local ffi = require "ffi"
local C = ffi.C
local str = require "resty.string"
local sha256 = require "resty.sha256"

ffi.cdef[[
    typedef void ENGINE;
    typedef struct env_md_ctx_st EVP_MD_CTX;
    typedef struct env_md_st EVP_MD;

    EVP_MD_CTX *EVP_MD_CTX_new(void);
    void EVP_MD_CTX_free(EVP_MD_CTX *ctx);
    const EVP_MD *EVP_sha256(void);
    int HMAC(const EVP_MD *evp_md, const void *key, int key_len,
             const unsigned char *d, size_t n, unsigned char *md,
             unsigned int *md_len);
]]

local function hmac_sha256(key, msg)
    local md = ffi.new("unsigned char[?]", 32)
    local md_len = ffi.new("unsigned int[1]")
    local evp = C.EVP_sha256()
    C.HMAC(evp, key, #key, msg, #msg, md, md_len)
    return ffi.string(md, md_len[0])
end

-- config
local access_key = os.getenv("AWS_ACCESS_KEY_ID")
local secret_key = os.getenv("AWS_SECRET_ACCESS_KEY")
local host = "minio:9000"
local region = "us-east-1"
local service = "s3"

if not access_key or not secret_key then
    ngx.status = 500
    ngx.say("Missing AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY environment variables.")
    return
end

-- path
local uri = ngx.var.uri
local object_path = string.sub(uri, 8)
local bucket_url = "http://" .. host .. "/" .. object_path

-- timestamps
local amz_date = os.date("!%Y%m%dT%H%M%SZ")
local datestamp = os.date("!%Y%m%d")

-- canonical request
local canonical_uri = "/" .. object_path
local canonical_headers = "host:" .. host .. "\n" .. "x-amz-date:" .. amz_date .. "\n"
local signed_headers = "host;x-amz-date"
local payload_hash = str.to_hex(sha256:new():final("")) -- empty body

local canonical_request = table.concat({
    "GET",
    canonical_uri,
    "",
    canonical_headers,
    signed_headers,
    payload_hash
}, "\n")

-- string to sign
local algorithm = "AWS4-HMAC-SHA256"
local credential_scope = datestamp .. "/" .. region .. "/" .. service .. "/aws4_request"
local hashed_canonical_request = sha256:new()
hashed_canonical_request:update(canonical_request)
local string_to_sign = table.concat({
    algorithm,
    amz_date,
    credential_scope,
    str.to_hex(hashed_canonical_request:final())
}, "\n")

-- signature
local k_date = hmac_sha256("AWS4" .. secret_key, datestamp)
local k_region = hmac_sha256(k_date, region)
local k_service = hmac_sha256(k_region, service)
local k_signing = hmac_sha256(k_service, "aws4_request")
local signature = str.to_hex(hmac_sha256(k_signing, string_to_sign))

-- authorization header
local authorization_header = table.concat({
    algorithm .. " ",
    "Credential=" .. access_key .. "/" .. credential_scope .. ", ",
    "SignedHeaders=" .. signed_headers .. ", ",
    "Signature=" .. signature
})

-- send to MinIO
local httpc = http.new()
local res, err = httpc:request_uri(bucket_url, {
    method = "GET",
    headers = {
        ["Host"] = host,
        ["x-amz-date"] = amz_date,
        ["Authorization"] = authorization_header
    }
})

if not res then
    ngx.status = 502
    ngx.say("Failed to request MinIO: ", err)
    return
end

ngx.status = res.status
ngx.print(res.body)
