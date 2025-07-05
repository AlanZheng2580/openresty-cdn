local redis_util = require("redis_util")
local cjson = require("cjson")

local MAX_ACTIVE_USERS = 3 -- For testing purposes
local ACTIVE_USER_TTL = 60 -- seconds, how long a user is considered active
local QUEUE_USER_TTL = 300 -- seconds, how long a user stays in queue

local REDIS_ACTIVE_USERS_KEY = "waiting_room:active_users"
local REDIS_QUEUE_KEY = "waiting_room:queue"

local function get_user_id()
    local wr_session_id = ngx.var.cookie_wr_session_id
    if not wr_session_id then
        -- Generate a simple UUID (not cryptographically secure, but sufficient for this purpose)
        wr_session_id = ngx.md5(ngx.now() .. ngx.var.remote_addr .. ngx.var.request_time .. math.random())
        -- Set the cookie for 1 day
        ngx.header["Set-Cookie"] = "wr_session_id=" .. wr_session_id .. "; Path=/; Max-Age=" .. (24 * 60 * 60) .. "; HttpOnly"
        ngx.log(ngx.INFO, "[get_user_id] New wr_session_id generated and cookie set: ", wr_session_id)
    else
        ngx.log(ngx.INFO, "[get_user_id] Existing wr_session_id: ", wr_session_id)
    end
    return wr_session_id
end

local function get_active_users_count()
    local red, err = redis_util.new()
    if not red then
        ngx.log(ngx.ERR, "[get_active_users_count] Failed to get redis connection: ", err)
        return 0
    end
    local count, err = red:zcard(REDIS_ACTIVE_USERS_KEY)
    redis_util.close(red)
    if not count then
        ngx.log(ngx.ERR, "[get_active_users_count] Failed to get active users count from redis: ", err)
        return 0
    end
    ngx.log(ngx.INFO, "[get_active_users_count] Active users count: ", count)
    return count
end

local function is_user_active(user_id)
    local red, err = redis_util.new()
    if not red then
        ngx.log(ngx.ERR, "[is_user_active] Failed to get redis connection: ", err)
        return false
    end
    local score, err_zscore = red:zscore(REDIS_ACTIVE_USERS_KEY, user_id)
    redis_util.close(red)

    ngx.log(ngx.INFO, "[is_user_active] User " .. user_id .. " raw zscore result: score_val=" .. tostring(score) .. ", err_val=" .. tostring(err_zscore) .. ", type_score=" .. type(score))

    if score == nil or score == false then -- Explicitly check for nil and false
        if err_zscore then
            ngx.log(ngx.ERR, "[is_user_active] Failed to get zscore for user " .. user_id .. ": " .. tostring(err_zscore))
        else
            ngx.log(ngx.INFO, "[is_user_active] User " .. user_id .. " is NOT active (not found or false).")
        end
        return false
    end
    -- If we reach here, score is not nil or false, so it's a valid score (could be 0)
    ngx.log(ngx.INFO, "[is_user_active] User " .. user_id .. " IS active (score: " .. tostring(score) .. ").")
    return true
end

local function is_user_in_queue(user_id)
    local red, err = redis_util.new()
    if not red then
        ngx.log(ngx.ERR, "[is_user_in_queue] Failed to get redis connection: ", err)
        return false
    end
    local score, err = red:zscore(REDIS_QUEUE_KEY, user_id)
    redis_util.close(red)
    if not score then
        ngx.log(ngx.INFO, "[is_user_in_queue] User ", user_id, " is NOT in queue.")
        return false
    end
    ngx.log(ngx.INFO, "[is_user_in_queue] User ", user_id, " IS in queue (score: ", score, ").")
    return true
end

local function add_active_user(user_id)
    local red, err = redis_util.new()
    if not red then
        ngx.log(ngx.ERR, "[add_active_user] Failed to get redis connection: ", err)
        return
    end
    local ok, err_zadd = red:zadd(REDIS_ACTIVE_USERS_KEY, ngx.now(), user_id)
    redis_util.close(red)
    if not ok then
        ngx.log(ngx.ERR, "[add_active_user] Failed to add active user " .. user_id .. " to redis: " .. tostring(err_zadd))
    else
        ngx.log(ngx.INFO, "[add_active_user] User " .. user_id .. " added to active users. ZADD result: " .. tostring(ok))
    end
end

local function add_user_to_queue(user_id)
    local red, err = redis_util.new()
    if not red then
        ngx.log(ngx.ERR, "[add_user_to_queue] Failed to get redis connection: ", err)
        return
    end
    local ok, err_zadd = red:zadd(REDIS_QUEUE_KEY, ngx.now(), user_id)
    redis_util.close(red)
    if not ok then
        ngx.log(ngx.ERR, "[add_user_to_queue] Failed to add user " .. user_id .. " to queue in redis: " .. tostring(err_zadd))
    else
        ngx.log(ngx.INFO, "[add_user_to_queue] User " .. user_id .. " added to queue. ZADD result: " .. tostring(ok))
    end
end

local function remove_user_from_queue(user_id)
    local red, err = redis_util.new()
    if not red then
        ngx.log(ngx.ERR, "[remove_user_from_queue] Failed to get redis connection: ", err)
        return
    end
    local ok, err = red:zrem(REDIS_QUEUE_KEY, user_id)
    redis_util.close(red)
    if not ok then
        ngx.log(ngx.ERR, "[remove_user_from_queue] Failed to remove user ", user_id, " from queue in redis: ", err)
    else
        ngx.log(ngx.INFO, "[remove_user_from_queue] User ", user_id, " removed from queue.")
    end
end

local function get_queue_position(user_id)
    local red, err = redis_util.new()
    if not red then
        ngx.log(ngx.ERR, "[get_queue_position] Failed to get redis connection: ", err)
        return nil
    end
    local rank, err = red:zrank(REDIS_QUEUE_KEY, user_id)
    redis_util.close(red)
    if not rank then
        ngx.log(ngx.INFO, "[get_queue_position] User ", user_id, " not found in queue.")
        return nil
    end
    ngx.log(ngx.INFO, "[get_queue_position] User ", user_id, " rank in queue: ", rank + 1)
    return rank + 1 -- ZRANK is 0-indexed
end

local function handle_main_site_access()
    ngx.log(ngx.INFO, "[handle_main_site_access] Handling main site access.")
    local user_id = get_user_id()

    -- Check if user is already active
    local user_is_active = is_user_active(user_id)
    ngx.log(ngx.INFO, "[handle_main_site_access] User ", user_id, " user_is_active: ", tostring(user_is_active))
    if user_is_active then
        ngx.log(ngx.INFO, "[handle_main_site_access] User ", user_id, " is already active. Allowing access.")
        ngx.exec("@proxy_to_httpbin")
        return
    end

    -- Check if user is in queue and should be redirected to waiting room
    local user_in_queue = is_user_in_queue(user_id)
    ngx.log(ngx.INFO, "[handle_main_site_access] User ", user_id, " user_in_queue: ", tostring(user_in_queue))
    if user_in_queue then
        ngx.log(ngx.INFO, "[handle_main_site_access] User ", user_id, " is in queue. Redirecting to waiting room.")
        return ngx.redirect("/waiting_room.html", ngx.HTTP_MOVED_TEMPORARILY)
    end

    local active_users_count = get_active_users_count()
    ngx.log(ngx.INFO, "[handle_main_site_access] Current active users: ", active_users_count, ", Max: ", MAX_ACTIVE_USERS)

    if active_users_count < MAX_ACTIVE_USERS then
        add_active_user(user_id)
        ngx.log(ngx.INFO, "[handle_main_site_access] User ", user_id, " added to active users. Allowing access.")
        ngx.exec("@proxy_to_httpbin")
    else
        add_user_to_queue(user_id)
        ngx.log(ngx.INFO, "[handle_main_site_access] User ", user_id, " added to queue. Redirecting to waiting room.")
        return ngx.redirect("/waiting_room.html", ngx.HTTP_MOVED_TEMPORARILY)
    end
end

local function handle_waiting_room_status()
    ngx.log(ngx.INFO, "[handle_waiting_room_status] Handling waiting room status.")
    ngx.header["Content-Type"] = "application/json"
    local user_id = get_user_id()

    if is_user_active(user_id) then
        ngx.log(ngx.INFO, "[handle_waiting_room_status] User ", user_id, " is active. Sending ready status.")
        remove_user_from_queue(user_id)
        ngx.say(cjson.encode({ status = "ready", redirect_url = "/" }))
    else
        local position = get_queue_position(user_id)
        local estimated_time = "正在計算中..." -- Placeholder for now
        if position then
            ngx.log(ngx.INFO, "[handle_waiting_room_status] User ", user_id, " is in queue at position ", position, ". Sending waiting status.")
            ngx.say(cjson.encode({ status = "waiting", position = position, estimated_time = estimated_time }))
        else
            ngx.log(ngx.INFO, "[handle_waiting_room_status] User ", user_id, " not found in queue or active users. Sending error status.")
            -- User not found in queue or active users, maybe they refreshed or came directly
            ngx.say(cjson.encode({ status = "error", message = "User not found in queue." }))
        end
    end
end

-- Determine which function to call based on the request URI
local uri = ngx.var.uri
ngx.log(ngx.INFO, "[waiting_room.lua] Request URI: ", uri)
if uri == "/waiting_room_status" then
    handle_waiting_room_status()
else
    handle_main_site_access()
end