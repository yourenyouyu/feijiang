local env = os.getenv('RUN_MODE') or "dev"
local baseConfig = {
	-- redis的相关配置
	redis = {
		host 		= os.getenv('REDIS_HOST') or '127.0.0.1',
		port 		= tonumber(os.getenv('REDIS_PORT')) or 6379,
		db 			= tonumber(os.getenv('REDIS_DB')) or 0,
	    password 	= os.getenv('REDIS_PASSWORD') or nil,
	    keepalive 	= tonumber(os.getenv('REDIS_KEEPALIVE')) or 60000,
	    pool_size 	= tonumber(os.getenv('REDIS_POOL_SIZE')) or 100,
	},
	limit_model = os.getenv('LIMIT_MODEL') or "memory",
}

return baseConfig