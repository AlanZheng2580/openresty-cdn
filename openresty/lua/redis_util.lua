local redis = require("resty.redis")

local _M = {}

function _M.new()
    local red = redis:new()

    red:set_timeout(1000) -- 1 sec

    -- or connect to a unix domain socket:
    -- local ok, err = red:connect("unix:/path/to/redis.sock")

    local ok, err = red:connect("redis", 6379)
    if not ok then
        ngx.log(ngx.ERR, "failed to connect to redis: ", err)
        return nil, err
    end

    return red
end

function _M.close(red)
    if red then
        local ok, err = red:close()
        if not ok then
            ngx.log(ngx.ERR, "failed to close redis connection: ", err)
        end
    end
end

return _M
