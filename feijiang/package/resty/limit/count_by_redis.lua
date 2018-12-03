-- Copyright (C) youyu岁月
local ngx_shared = ngx.shared
local setmetatable = setmetatable
local assert = assert


local _M = {
   _VERSION = '0.0.1'
}


local mt = {
    __index = _M
}

function _M.new(redis_instance, limit, window)
    if not redis_instance then
        return nil, "redis_instance not found"
    end

    assert(limit > 0 and window > 0)

    local self = {
        dict = redis_instance,
        limit = limit,
        window = window,
    }

    return setmetatable(self, mt)
end

_M.redis_limit_single_script_sha = nil
_M.redis_limit_single_script = [==[
local remaining, ok
local key   = KEYS[1]
local limit = tonumber(KEYS[2])
local expire= tonumber(KEYS[3])
local commit = KEYS[4]
if commit then
    local res = redis.pcall('EXISTS', key)
    if type(res) == "table" and res.err then
        return {err=res.err}
    end
    local has_key = res
    -- key不存在，设置初始化值
    if has_key ~= 1 then
        local res = redis.pcall('SET', key, limit)
        if type(res) == "table" and res.err then
            return {err=res.err}
        end
    end

    local res = redis.pcall('DECR', key)
    if type(res) == "table" and res.err then
        return {err=res.err}
    end

    remaining = res
    if remaining == limit - 1 then
        local res = redis.pcall('EXPIRE', key, expire)
        if type(res) == "table" and res.err then
            return {err=res.err}
        end

        ok = res
        if ok ~= 1 then
            if type(ok) ~= "number" then
                return {err=tostring(ok)}
            end

            if ok == 0 then
                -- retry 一次
                local res = redis.pcall('EXISTS', key)
                if type(res) == "table" and res.err then
                    return {err=res.err}
                end

                local has_key = res
                -- key不存在，设置初始化值
                if has_key ~= 1 then
                    local res = redis.pcall('SET', key, limit)
                    if type(res) == "table" and res.err then
                        return {err=res.err}
                    end
                end

                local res = redis.pcall('DECR', key)
                if type(res) == "table" and res.err then
                    return {err=res.err}
                end

                remaining = res
                local res = redis.pcall('EXPIRE', key, expire)
                if type(res) == "table" and res.err then
                    return {err=res.err}
                end
                ok = res 
                if ok ~= 1 then
                    return {err=tostring(ok)}
                end
            end
        end
    end
else    
    local res = redis.pcall('GET', key)
    if type(res) == "table" and res.err then
        return {err=res.err}
    end
    local redis_value = res 
    remaining = (tonumber(redis_value) or limit) - 1
end

return {remaining}
]==]

local function redis_commit(redis_instance, key, limit, expire, commit, redis_limit_script, redis_limit_script_sha)
    if not _M[redis_limit_script_sha] then
        local ok, err = redis_instance:script("LOAD", _M[redis_limit_script])
        if not ok then
            return nil, err
        end

        _M[redis_limit_script_sha] = ok
    end

    local res, err = redis_instance:evalsha(_M[redis_limit_script_sha], 4, key, limit, expire, commit)
    if not res then
        _M[redis_limit_script_sha] = nil
        return nil, err
    end

    return res
end

function _M.incoming(self, key, commit)
    local dict = self.dict
    local limit = self.limit
    local window = self.window

    local res, err = redis_commit(dict, key, limit, window, commit, "redis_limit_single_script", "redis_limit_single_script_sha")
    if not res then
        return nil, err
    end

    if type(res) ~= "table" then
        return nil, "redis should return a table"
    end

    if res.err then
        return nil, res.err
    end

    local remaining = tonumber(#res > 0 and res[1] or nil)
    if not remaining then
        return nil, "remaining is not a number"        
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

_M.redis_limit_group_script_sha = nil
_M.redis_limit_group_script = [==[
local remaining, ok
local limit_count_group_key     = KEYS[1]
local limit_count_group_set_key = KEYS[2]
local expire= tonumber(KEYS[3])
local commit = KEYS[4]
local key_num
if commit then
    local res = redis.pcall('EXISTS', limit_count_group_key)
    if type(res) == "table" and res.err then
        return {err=res.err}
    end
    local has_key = res
    -- key不存在，设置初始化值
    if has_key ~= 1 then
        -- 新的值
        local res = redis.pcall('HSET', limit_count_group_key, limit_count_group_set_key, 1)
        if type(res) == "table" and res.err then
            return {err=res.err}
        end

        local res = redis.pcall('EXPIRE', limit_count_group_key, expire)
        if type(res) == "table" and res.err then
            return {err=res.err}
        end
    end

    local res = redis.pcall('HSET', limit_count_group_key, limit_count_group_set_key, 1)
    if type(res) == "table" and res.err then
        return {err=res.err}
    end

    local res = redis.pcall('HLEN', limit_count_group_key)
    if type(res) == "table" and res.err then
        return {err=res.err}
    end

    key_num= tonumber(res)

    if not key_num then
        return {err="key is not a number"}
    end
else
    local res = redis.pcall('HLEN', limit_count_group_key)
    if type(res) == "table" and res.err then
        return {err=res.err}
    end

    key_num = tonumber(res)

    if not key_num then
        return {err="key is not a number"}
    end
end

return {key_num}
]==]

function _M.incoming_group(self, key, sub_key)
    local dict = self.dict
    local limit = self.limit
    local window = self.window

    local res, err = redis_commit(dict, key, sub_key, window, true, "redis_limit_group_script", "redis_limit_grooup_script_sha")
    if not res then
        return nil, err
    end

    if type(res) ~= "table" then
        return nil, "redis should return a table"
    end

    if res.err then
        return nil, res.err
    end

    local key_num = tonumber(#res > 0 and res[1] or nil)
    if not key_num then
        return nil, "remaining is not a number"        
    end

    if key_num > limit then
        return nil, "rejected"
    end

    return 0, limit - key_num
end

return _M
