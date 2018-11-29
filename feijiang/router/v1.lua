local lor 		= require("lor.index")
local router 	= lor:Router() -- 生成一个group router对象
local validate 	= require("controller.validate")
local policy 	= require("controller.policy")

-- 风险验证接口
router:post("/validate", validate.validate)

-- 设置项目风控策略
router:get("/policy", policy.get_policy)

router:post("/policy", policy.create_policy)

-- router:put("/policy", function(req, res, next)
-- end)

-- router:delete("/policy", function(req, res, next)
-- end)
return router
