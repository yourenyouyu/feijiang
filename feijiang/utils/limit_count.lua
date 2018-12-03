local limit_count_memory = require "resty.limit.count_by_memory"   
local limit_count_redis  = require "resty.limit.count_by_redis"
local redis              = require "utils.redis"

local _M = {

}

_M.get_limit_count_info = function (limit_model)
	if limit_model == "memory" then
		-- 内存限流
		local limit_count_module = limit_count_memory
		local limit_count_story  = ngx.shared.limit_count_policy
		return limit_count_module, limit_count_story

	elseif limit_model == "redis" then
	    -- redis限流
		local limit_count_module = limit_count_redis
		local limit_count_story  = redis:new()
		return limit_count_module, limit_count_story
	else 
		error("limit_model is not exists", 2)
	end
end

return _M