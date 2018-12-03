local lor = require("lor.index")
local app = lor()
local v1 = require("router.v1")

-- /api/v1
app:use("/api/v1", v1())

app:erroruse(function(err, req, res, next)
    if req:is_found() ~= true then
        res:status(404):json({
        	success = false,
        	msg = "404! page not found!"
        })
    else
        ngx.log(ngx.ERR, err)
        res:status(500):json({
        	success = false,
        	msg = "internal server error"
        })
    end
end)

app:run()