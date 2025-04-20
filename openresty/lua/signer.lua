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

-- configurations from NGINX
local access_key  = ngx.var.access_key
local secret_key  = ngx.var.secret_key
local host        = ngx.var.minio_host
local bucket      = ngx.var.bucket_name
local object      = ngx.var.object_key
local bucket_url  = "http://" .. host .. "/" .. bucket .. "/" .. object

if not (host and access_key and secret_key and bucket and object) then
    ngx.status = 500
    ngx.say("Missing required parameters.")
    return
end

-- AWS Signature V4
-- timestamps
local amz_date = os.date("!%Y%m%dT%H%M%SZ")
local datestamp = os.date("!%Y%m%d")
local region = "us-east-1"
local service = "s3"

-- canonical request
local canonical_uri = "/" .. bucket .. "/" .. object
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
