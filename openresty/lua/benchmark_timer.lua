local ffi = require "ffi"

-- 高精度時間
ffi.cdef[[
    typedef long time_t;
    typedef long suseconds_t;
    typedef struct timeval {
        time_t      tv_sec;
        suseconds_t tv_usec;
    } timeval;
    int gettimeofday(struct timeval *tv, void *tz);
]]

local function get_time_usec()
    local tv = ffi.new("struct timeval")
    ffi.C.gettimeofday(tv, nil)
    return tonumber(tv.tv_sec) * 1e6 + tonumber(tv.tv_usec)
end

-- 方案 A：兩次 os.date
local function old_way()
    local a = os.date("!%Y%m%dT%H%M%SZ")
    local b = a:sub(1, 8)
    return a, b
end

-- 方案 B：一次 ngx.utctime + 字串處理
local function new_way()
    local utc = ngx.utctime()
    local date_stamp = utc:sub(1,4) .. utc:sub(6,7) .. utc:sub(9,10)
    local amz_date = date_stamp .. "T" .. utc:sub(12,13) .. utc:sub(15,16) .. utc:sub(18,19) .. "Z"
    return amz_date, datestamp
end

-- 測試參數
local rounds = 50000  -- 5萬次，夠穩定

-- 測試舊方法
local start_old = get_time_usec()
for i = 1, rounds do
    old_way()
end
local duration_old = (get_time_usec() - start_old) / 1000  -- 毫秒

-- 測試新方法
local start_new = get_time_usec()
for i = 1, rounds do
    new_way()
end
local duration_new = (get_time_usec() - start_new) / 1000  -- 毫秒

ngx.say(string.format("Old way (os.date x2): %.2f ms", duration_old))
ngx.say(string.format("New way (ngx.utctime + sub): %.2f ms", duration_new))
ngx.say(string.format("Speedup: %.2fx faster", duration_old / duration_new))
