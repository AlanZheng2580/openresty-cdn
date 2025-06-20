local signer = require "aws_v4_signer"
local ffi = require "ffi"

local function get_time_usec()
    local tv = ffi.new("struct timeval")
    ffi.C.gettimeofday(tv, nil)
    return tonumber(tv.tv_sec) * 1e6 + tonumber(tv.tv_usec)
end

local function handler()
    local args = ngx.req.get_uri_args()
    local n = tonumber(args.n) or 10000

    local t0 = get_time_usec()

    for i = 1, n do
        local _ = signer.build{
            schema = "http",
            host = "minio:9000",
            access_key = "access_key",
            secret_key = "secret_key",
            bucket = "bucket",
            object = "object"
        }
    end

    local t1 = get_time_usec()
    local total = t1 - t0

    ngx.say("Signatures: ", n)
    ngx.say("Total Time (us): ", total)
    ngx.say("Avg per signature (us): ", total / n)
end

return handler()
