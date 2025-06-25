local signer = require "aws_v4_signer"
local http = require "resty.http"

-- configurations from NGINX
local schema      = ngx.var.minio_schema
local host        = ngx.var.minio_host
local access_key  = ngx.var.access_key
-- local secret_key  = ngx.var.secret_key
local secret_key  = ngx.shared.secrets:get("MINIO_SECRET_KEY")
if not secret_key then
    ngx.log(ngx.ERR, "[SIGNER] No secret key found in shared dict!")
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.say("No secret key found in shared dict!")
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end
local bucket      = ngx.var.bucket_name
local object      = ngx.var.object_key

if not (host and access_key and secret_key and bucket and object) then
    ngx.log(ngx.ERR, "[SIGNER] Missing required parameters.")
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.say("Missing required parameters.")
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end
ngx.log(ngx.INFO, "access_key: "..access_key)

local sig = signer.build{
    schema = schema,
    host = host,
    access_key = access_key,
    secret_key = secret_key,
    bucket = bucket,
    object = object,
}

-- set headers
ngx.req.set_header("Host", sig.host)
ngx.req.set_header("x-amz-date", sig.amz_date)
ngx.req.set_header("x-amz-content-sha256", sig.payload_hash)
ngx.req.set_header("Authorization", sig.authorization)