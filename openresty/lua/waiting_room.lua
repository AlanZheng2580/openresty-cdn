-- waiting_room.lua

local redis = require "resty.redis"
local cjson = require "cjson"

-- Configuration
local config = {
    redis_host = os.getenv("REDIS_HOST") or "127.0.0.1",
    redis_port = tonumber(os.getenv("REDIS_PORT")) or 6379,
    max_users = tonumber(os.getenv("VWR_MAX_USERS")) or 10,
    session_timeout = tonumber(os.getenv("VWR_SESSION_TIMEOUT")) or 900, -- 15 minutes
    session_cookie_name = "vwr_session_id",
    cleanup_probability = 0.1 -- 10% chance to run cleanup
}

local _M = {}

-- Simple random string generator to replace uuid
local function generate_session_id()
    math.randomseed(ngx.now() * 1000)
    local hash = ngx.md5(ngx.now() .. math.random() .. ngx.var.remote_addr)
    return hash
end

function _M.new()
    local self = setmetatable({}, { __index = _M })
    return self
end

function _M.connect_to_redis(self)
    local red = redis:new()
    red:set_timeout(1000) -- 1 second

    local ok, err = red:connect(config.redis_host, config.redis_port)
    if not ok then
        ngx.log(ngx.ERR, "failed to connect to redis: ", err)
        return nil, err
    end
    return red, nil
end

function _M.get_or_create_session_id(self)
    local session_id = ngx.var.cookie_vwr_session_id
    if not session_id or session_id == "" then
        session_id = generate_session_id()
        ngx.header["Set-Cookie"] = config.session_cookie_name .. "=" .. session_id .. "; Path=/; HttpOnly"
    end
    return session_id
end

function _M.cleanup_expired_sessions(self, red)
    ngx.log(ngx.INFO, "[CLEANUP] Starting cleanup_expired_sessions")
    local expired_sessions_keys, err = red:keys("vwr:session:*")
    if err or not expired_sessions_keys then
        ngx.log(ngx.ERR, "[CLEANUP] Failed to get session keys: ", err)
        return
    end

    for _, key in ipairs(expired_sessions_keys) do
        local session_data, err = red:hgetall(key)
        if err then
            ngx.log(ngx.ERR, "[CLEANUP] failed to get session data for key " .. key .. ": " .. err)
            goto continue
        end

        local status = session_data and session_data[1] == "status" and session_data[2] or nil
        local last_seen_str = session_data and session_data[3] == "last_seen" and session_data[4] or nil

        if last_seen_str then
            local last_seen_num = tonumber(last_seen_str)
            if last_seen_num then
                if (ngx.time() - last_seen_num) > config.session_timeout then
                    ngx.log(ngx.INFO, "[CLEANUP] Deleting expired session: " .. key)
                    red:del(key)
                    if status == "active" then
                        red:decr("vwr:active_users")
                    end
                end
            else
                ngx.log(ngx.WARN, "[CLEANUP] Malformed last_seen value for key " .. key .. ": " .. tostring(last_seen_str) .. ". Deleting session.")
                red:del(key)
                if status == "active" then
                    red:decr("vwr:active_users")
                end
            end
        else
            ngx.log(ngx.WARN, "[CLEANUP] Missing last_seen field for key " .. key .. ". Deleting session.")
            red:del(key)
            if status == "active" then
                red:decr("vwr:active_users")
            end
        end
        ::continue::
    end
    ngx.log(ngx.INFO, "[CLEANUP] Finished cleanup_expired_sessions")
end

function _M.promote_waiting_users(self, red)
    ngx.log(ngx.INFO, "[PROMOTION] Starting promote_waiting_users")
    local active_users, err = red:get("vwr:active_users")
    active_users = tonumber(active_users) or 0
    if active_users < 0 then active_users = 0 end -- Defensive check
    ngx.log(ngx.INFO, "[PROMOTION] Current active_users: " .. active_users .. ", max_users: " .. config.max_users)

    while active_users < config.max_users do
        local session_id, err = red:lpop("vwr:waiting_queue") -- Get error as well
        if err then
            ngx.log(ngx.ERR, "[PROMOTION] Error popping from queue: " .. err)
            break
        end

        if session_id == ngx.null or session_id == nil then -- Explicitly check for ngx.null and nil
            ngx.log(ngx.INFO, "[PROMOTION] No more users in waiting queue.")
            break -- No one in the queue
        end

        -- Ensure session_id is a string before using it
        if type(session_id) ~= "string" then
            ngx.log(ngx.ERR, "[PROMOTION] Invalid session_id from queue (not a string): " .. tostring(session_id) .. ". Skipping.")
            goto continue_promotion
        end

        ngx.log(ngx.INFO, "[PROMOTION] Promoting user: " .. session_id)
        red:hset("vwr:session:" .. session_id, "status", "active")
        red:hset("vwr:session:" .. session_id, "last_seen", ngx.time())
        red:incr("vwr:active_users")
        active_users = active_users + 1
        ngx.log(ngx.INFO, "[PROMOTION] New active_users count: " .. active_users)
        ::continue_promotion::
    end
    ngx.log(ngx.INFO, "[PROMOTION] Finished promote_waiting_users")
end

function _M.handle(self)
    local session_id = self:get_or_create_session_id()
    ngx.log(ngx.INFO, "[HANDLE] Processing session_id: " .. session_id)

    local red, err = self:connect_to_redis()
    if not red then
        ngx.status = 503
        ngx.say("Service Unavailable: Cannot connect to Redis.")
        return
    end

    local user_status, err = red:hget("vwr:session:" .. session_id, "status")
    ngx.log(ngx.INFO, "[HANDLE] User status for " .. session_id .. ": " .. tostring(user_status))

    if user_status == "active" then
        ngx.log(ngx.INFO, "[HANDLE] User " .. session_id .. " is active. Updating last_seen.")
        red:hset("vwr:session:" .. session_id, "last_seen", ngx.time())
        return
    elseif user_status == "waiting" then
        ngx.log(ngx.INFO, "[HANDLE] User " .. session_id .. " is waiting. Redirecting to waiting-room.html.")
        return ngx.redirect("/waiting-room.html")
    else
        ngx.log(ngx.INFO, "[HANDLE] New user or unknown status for " .. session_id .. ". Checking for available slots.")
        local active_users, err = red:get("vwr:active_users")
        active_users = tonumber(active_users) or 0
        ngx.log(ngx.INFO, "[HANDLE] Current active_users: " .. active_users .. ", max_users: " .. config.max_users)

        if active_users < config.max_users then
            ngx.log(ngx.INFO, "[HANDLE] Granting access to " .. session_id)
            red:hset("vwr:session:" .. session_id, "status", "active")
            red:hset("vwr:session:" .. session_id, "last_seen", ngx.time())
            red:incr("vwr:active_users")
            return
        else
            ngx.log(ngx.INFO, "[HANDLE] Site full. Adding " .. session_id .. " to waiting queue.")
            red:hset("vwr:session:" .. session_id, "status", "waiting")
            red:rpush("vwr:waiting_queue", session_id)
            return ngx.redirect("/waiting-room.html")
        end
    end
end

function _M.handle_status_check(self)
    local session_id = self:get_or_create_session_id()
    ngx.log(ngx.INFO, "[STATUS_CHECK] Processing session_id: " .. session_id)
    local red, err = self:connect_to_redis()
    if not red then
        ngx.status = 503
        ngx.say(cjson.encode({status = "error", message = "Redis connection failed"}))
        return
    end

    local user_status, err = red:hget("vwr:session:" .. session_id, "status")
    ngx.log(ngx.INFO, "[STATUS_CHECK] User status for " .. session_id .. ": " .. tostring(user_status))

    if user_status == "active" then
        ngx.say(cjson.encode({status = "ready"}))
    else
        ngx.say(cjson.encode({status = "waiting"}))
    end
end

function _M.run_periodic_tasks()
    local wr = _M.new()
    local red, err = wr:connect_to_redis()
    if not red then
        ngx.log(ngx.ERR, "[PERIODIC_TASK] Failed to connect to Redis for periodic tasks: ", err)
        return
    end

    wr:cleanup_expired_sessions(red)
    wr:promote_waiting_users(red)

    local ok, err = ngx.timer.at(5, _M.run_periodic_tasks) -- Schedule next run in 5 seconds
    if not ok then
        ngx.log(ngx.ERR, "[PERIODIC_TASK] Failed to schedule next periodic task: ", err)
    end
end

return _M
