local signer = require "aws_v4_signer"
local http = require "resty.http"

-- configurations from NGINX
local schema    = ngx.var.minio_schema
local host        = ngx.var.minio_host
local access_key  = ngx.var.access_key
local secret_key  = ngx.var.secret_key
local bucket      = ngx.var.bucket_name
local object      = ngx.var.object_key

if not (host and access_key and secret_key and bucket and object) then
    ngx.status = 500
    ngx.say("Missing required parameters.")
    return
end

local sig = signer.build{
    schema = schema,
    host = host,
    access_key = access_key,
    secret_key = secret_key,
    bucket = bucket,
    object = object,
}

-- send to MinIO
local httpc = http.new()
local res, err = httpc:request_uri(sig.bucket_url, {
    method = "GET",
    headers = {
        ["Host"] = sig.host,
        ["x-amz-date"] = sig.amz_date,
        ["x-amz-content-sha256"] = sig.payload_hash,
        ["Authorization"] = sig.authorization
    }
})

if not res then
    ngx.status = 502
    ngx.say("Failed to request MinIO: ", err)
    return
end

ngx.status = res.status
ngx.print(res.body)
