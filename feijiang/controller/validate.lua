local limit_count = require "resty.limit.count"
local cjson      = require "cjson.safe"
local limit_count_config_dict = ngx.shared.limit_count_config
local limit_count_policy_dict = ngx.shared.limit_count_policy
local uuid = require 'resty.jit-uuid'
local _M = {}
local function check_group_limit_status( shared_dict, limit_count_group_key, limit_count_group_set_key, limit_num, limit_window)
    -- 检测组合模式的策略状态，看看是否需要限制
    local set_value_str, err = shared_dict:get(limit_count_group_key)
    local set_value, err = {}, nil
    if set_value_str then
        set_value, err = cjson.decode(set_value_str)
        if not set_value then
            return nil, string.format("could not decode limit count group set value str: [%s]", err)
        end
        ngx.log(ngx.ERR, type(set_value))
        if type(set_value) ~= "table" then
            return nil, string.format("limit count group set value is not table")
        end
    end

    local key_num = 0
    for k,v in pairs(set_value) do
        key_num = key_num + 1
    end

    if key_num > limit_num then
        return nil, "rejected"
    end

    set_value[limit_count_group_set_key] = true
    local json, err = cjson.encode(set_value)
    if not json then
        return nil, string.format("could not encode limit count group set value : [%s]", err)
    end

    local success, err = shared_dict:set(limit_count_group_key, json, limit_window)
    if not success then
        return nil, string.format("policy shared dict set [%s] occur: [%s]", limit_count_group_key, err)
    end

    local key_num = 0
    for k,v in pairs(set_value) do
        key_num = key_num + 1
    end

    if key_num > limit_num then
        return nil, "rejected"
    end

    return 0, limit_num - key_num
end

function _M.validate( req, res, next )
    local result = req.body
    if type(result) ~= "table" then
    	return res:json({
    		uuid 	= uuid(),
            success = false,
            result 	= {
            	risk_level 		= "ACCEPT",
            	hit_policy_code = "",
            	hit_rules		= "request body is not json",
        	}
        })
    end

    local app_id = result["app_id"]
    local event_code = result["event_code"]
    -- 1. 客户端传入 app_id与 event_type，先根据app_id-event_type去策略字典里面找到所有的策略
    local app_event_key = string.format("%s-%s", app_id, event_code)
    local app_event_config_str = limit_count_config_dict:get(app_event_key)
    local app_event_config, err = cjson.decode(app_event_config_str)
    if not app_event_config then
        return res:json({
    		uuid 	= uuid(),
            success = false,
            result 	= {
            	risk_level 		= "ACCEPT",
            	hit_policy_code = "",
            	hit_rules		= string.format("could not decode [%s] config", app_event_key),
        	}
        })
    end
    -- 2.解析出客户端传入的data下面的key
    --[[
        "data": {
            "mobile": "18605125200",
            "ip": "192.168.1.1"
        }
    ]]
    local data = result["data"]
    
    -- 3.循环对应的策略，并验证此策略
    for i, policy in ipairs(app_event_config) do
        -- 依据策略设置限流字典
        local limit_num = tonumber(policy["max_size"])
        local limit_window = tonumber(policy["time_slice"])

        local fields = policy["field"]
        local policy_type = #fields > 1 and "group" or "single" 
        local limit_count_key_prefix = string.format("%s_%s", app_event_key, policy_type)
        
        local skip = false
        local group_key = ""
        for i, field in ipairs(fields) do
            if not data[field] then
                -- 如果发现客户端请求没有策略中需要的字段，就设置不走这个策略
                skip = true
                break
            end
            group_key = string.format("%s_%s", group_key, data[field])
        end

        -- 如果要走这个策略的话，看下是group还是single
        if not skip then
            local limit_count_group_key = string.format("%s_%s", limit_count_key_prefix, table.concat(fields, "_"))  
            if policy_type == "group" then
                -- 组合模式
                local limit_count_group_set_key = string.format("%s_%s", limit_count_key_prefix, group_key)  
                
                local delay, err = check_group_limit_status(limit_count_policy_dict, limit_count_group_key, limit_count_group_set_key, limit_num, limit_window) 
                if not delay then
                    -- 此处不能退出，只是专门用来计数是否是第一次进入，limit_count_group_key
                    if err == "rejected" then
                    	return res:json({
							uuid 	= uuid(),
					        success = false,
					        result 	= {
					        	risk_level 		= "REJECT",
					        	hit_policy_code = limit_count_group_key,
					        	hit_rules		= err,
					    	}
					    })
                    end

                    ngx.log(ngx.ERR, "failed to limit count: ", err)
                    return res:json({
						uuid 	= uuid(),
				        success = false,
				        result 	= {
				        	risk_level 		= "ACCEPT",
				        	hit_policy_code = limit_count_group_key,
				        	hit_rules		= err,
				    	}
				    })
                end

            elseif policy_type == "single" then
                local lim, err = limit_count.new("limit_count_policy", limit_num, limit_window)
                if not lim then
                	return res:json({
						uuid 	= uuid(),
				        success = false,
				        result 	= {
				        	risk_level 		= "ACCEPT",
				        	hit_policy_code = limit_count_group_key,
				        	hit_rules		= err,
				    	}
				    })
                end

                for i, field in ipairs(fields) do
                    local limit_count_group_field_key = string.format("%s_%s", limit_count_key_prefix, data[field])  
                    local delay, err = lim:incoming(limit_count_group_field_key, true)
                    if not delay then
                        if err == "rejected" then
                            return res:json({
								uuid 	= uuid(),
						        success = false,
						        result 	= {
						        	risk_level 		= "REJECT",
						        	hit_policy_code = limit_count_group_key,
						        	hit_rules		= err,
						    	}
						    })
                        end
						return res:json({
							uuid 	= uuid(),
					        success = false,
					        result 	= {
					        	risk_level 		= "ACCEPT",
					        	hit_policy_code = limit_count_group_key,
					        	hit_rules		= err,
					    	}
					    })
                    end
                end
            end
        end

    end
	return res:json({
		uuid 	= uuid(),
        success = true,
        result 	= {
        	risk_level 		= "ACCEPT",
        	hit_policy_code = app_event_key,
        	hit_rules		= "",
    	}
    })
end

return _M
