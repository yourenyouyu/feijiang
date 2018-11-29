local limit_count_config_dict = ngx.shared.limit_count_config
local cjson = require("cjson.safe")
local _M = {
    
}
function _M.create_policy( req, res, next )
    -- 新增一个接入业务
    local result = req.body

    if type(result) ~= "table" then
        return res:json({
            success = false,
            msg = "request body is not json"
        })
    end
    -- todo     参数验证
    local app_id = result["AppId"]
    for i, event in ipairs(result["Events"]) do
        local key = string.format("%s-%s", app_id, event["EventCode"])
        local policy_str, err = cjson.encode(event["PolicyList"])
        if not policy_str then
            return res:json({
                success = false,
                msg = string.format("could not encode limit count group set value : [%s]", err)
            })
        end

        local success, err = limit_count_config_dict:set(key, policy_str)
        if not success then
            return res:json({
                success = false,
                msg = string.format("config shared dict set [%s] occur: [%s]", key, err)
            }) 
        end
    end

    return res:json({
        success = true,
        msg = "ok"
    }) 
end

function _M.get_policy( req, res, next )
    -- 要查询的项目id，不存在就查询所有
    local app_id_event = req.query.app_id_event
    
    if not app_id_event then
        local config_dict = {}
        -- 获取当前shared dict 中所有存在的key 
        local keys = limit_count_config_dict:get_keys(0)
        for _, key in pairs(keys) do
            local str = limit_count_config_dict:get(key)
            if not str then
                return res:json({
                    success = false,
                    msg = string.format("limit_count_config_dict key[%s] is not exists", key)
                })
            end

            local dict, err = cjson.decode(str)
            if not dict then
                return res:json({
                    success = false,
                    msg = string.format("decode [%s] occur error [%s]", key, err)
                }) 
            end
            config_dict[key] = dict
        end

        return res:json({
            success = true,
            msg = config_dict
        })
    end
    -- 单一查询
    local config_str, err = limit_count_config_dict:get(app_id_event)
    if not config_str then
        -- 如果要查询的项目id不存在 报错
        ngx.log(ngx.ERR, string.format("%s already exists, error is %s", projid, err))

        return res:json({
            success = false,
            msg = string.format("%s is not found", app_id_event)
        })
    end
    local config_dict, err = cjson.decode(config_str)
    if not config_dict then
        return res:json({
            success = false,
            msg = err
        }) 
    end

    return res:json({
        success = true,
        msg = config_dict
    })
end

return _M