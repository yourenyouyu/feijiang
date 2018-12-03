local ngx_shared = ngx.shared
local lock = require "resty.lock"
local cjson = require "cjson.safe"
local setmetatable = setmetatable
local assert = assert


local _M = {
   _VERSION = '0.06'
}


local mt = {
    __index = _M
}


-- the "limit" argument controls number of request allowed in a time window.
-- time "window" argument controls the time window in seconds.
function _M.new(dict, limit, window)
    if not dict then
        return nil, "shared dict not found"
    end

    assert(limit > 0 and window > 0)

    local self = {
        dict = dict,
        limit = limit,
        window = window,
    }

    return setmetatable(self, mt)
end


function _M.incoming(self, key, commit)
    local dict = self.dict
    local limit = self.limit
    local window = self.window

    local remaining, ok, err

    if commit then
        remaining, err = dict:incr(key, -1, limit)
        if not remaining then
            return nil, err
        end

        if remaining == limit - 1 then
            ok, err = dict:expire(key, window)
            if not ok then
                if err == "not found" then
                    remaining, err = dict:incr(key, -1, limit)
                    if not remaining then
                        return nil, err
                    end

                    ok, err = dict:expire(key, window)
                    if not ok then
                        return nil, err
                    end

                else
                    return nil, err
                end
            end
        end

    else
        remaining = (dict:get(key) or limit) - 1
    end

    if remaining < 0 then
        return nil, "rejected"
    end

    return 0, remaining
end


-- uncommit remaining and return remaining value
function _M.uncommit(self, key)
    assert(key)
    local dict = self.dict
    local limit = self.limit

    local remaining, err = dict:incr(key, 1)
    if not remaining then
        if err == "not found" then
            remaining = limit
        else
            return nil, err
        end
    end

    return remaining
end

local function _incoming_group(dict, key, sub_key, limit, window)
    -- 检测组合模式的策略状态，看看是否需要限制
    local set_value_str, err = dict:get(key)
    local set_value, err = {}, nil
    if set_value_str then
        set_value, err = cjson.decode(set_value_str)
        if not set_value then
            return nil, string.format("could not decode limit count group set value str: [%s]", err)
        end

        if type(set_value) ~= "table" then
            return nil, string.format("limit count group set value is not table")
        end
    end

    local key_num = 0
    for k,v in pairs(set_value) do
        key_num = key_num + 1
    end

    if key_num > limit then
        return nil, "rejected"
    end

    set_value[sub_key] = true
    local json, err = cjson.encode(set_value)
    if not json then
        return nil, string.format("could not encode limit count group set value : [%s]", err)
    end

    local success, err = dict:set(key, json, window)
    if not success then
        return nil, string.format("policy shared dict set [%s] occur: [%s]", key, err)
    end

    local key_num = 0
    for k,v in pairs(set_value) do
        key_num = key_num + 1
    end

    if key_num > limit then
        return nil, "rejected"
    end

    return 0, limit - key_num
end

function _M.incoming_group(self, key, sub_key)
    local dict = self.dict
    local limit = self.limit
    local window = self.window
    local delay, _err

    local mutex_locks, err = lock:new("mutex_locks")
    if not mutex_locks then
        return nil, err
    end

    local elapsed, err = mutex_locks:lock(key)
    if not elapsed then
        return nil, string.format("failed to acquire the lock: %s", err)
    end

    delay, _err = _incoming_group(dict, key, sub_key, limit, window)

    local ok, err = mutex_locks:unlock()
    if not ok then
        return nil, string.format("failed to unlock: %s", err)
    end

    return delay, _err
end
return _M
