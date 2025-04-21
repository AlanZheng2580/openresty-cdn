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

local function build_aws_v4_signature(args)
    local access_key = args.access_key
    local secret_key = args.secret_key
    local host = args.host
    local bucket = args.bucket
    local object = args.object
    local bucket_url  = "http://" .. host .. "/" .. bucket .. "/" .. object

    local amz_date = os.date("!%Y%m%dT%H%M%SZ")
    local datestamp = os.date("!%Y%m%d")
    local region = args.region or "us-east-1"
    local service = "s3"
    local body = args.body or ""
    local method = args.method or "GET"

    local canonical_uri = "/" .. bucket .. "/" .. object
    local canonical_headers = "host:" .. host .. "\n" .. "x-amz-date:" .. amz_date .. "\n"
    local signed_headers = "host;x-amz-date"
    local payload_hash = str.to_hex(sha256:new():final(""))

    local canonical_request = table.concat({
        method,
        canonical_uri,
        "",
        canonical_headers,
        signed_headers,
        payload_hash
    }, "\n")

    -- string to sign
    local algorithm = "AWS4-HMAC-SHA256"
    local credential_scope = datestamp .. "/" .. region .. "/" .. service .. "/aws4_request"
    local hashed_request = sha256:new()
    hashed_request:update(canonical_request)
    local string_to_sign = table.concat({
        algorithm,
        amz_date,
        credential_scope,
        str.to_hex(hashed_request:final())
    }, "\n")

    -- signature
    local k_date = hmac_sha256("AWS4" .. secret_key, datestamp)
    local k_region = hmac_sha256(k_date, region)
    local k_service = hmac_sha256(k_region, service)
    local k_signing = hmac_sha256(k_service, "aws4_request")
    local signature = str.to_hex(hmac_sha256(k_signing, string_to_sign))

    -- authorization header
    local authorization = table.concat({
        algorithm .. " ",
        "Credential=" .. access_key .. "/" .. credential_scope .. ", ",
        "SignedHeaders=" .. signed_headers .. ", ",
        "Signature=" .. signature
    })

    return {
        host = host,
        amz_date = amz_date,
        authorization = authorization,
        canonical_request = canonical_request,
        string_to_sign = string_to_sign,
        payload_hash = payload_hash,
        bucket_url = bucket_url
    }
end

return {
    build = build_aws_v4_signature
}
