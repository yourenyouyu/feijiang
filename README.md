# 飞将
一个基于openresty的花样限流的策略风控项目
## 项目介绍
该项目为一个简易的策略风控系统，简易的配置和灵活的拦截形式（多应用 多事件 多策略）

目前策略组合方式有两种：首次命中和权重模式

此为飞将系统的负载层（openresty代码），后端系统请移步[这里]()

## 部署方式
1. 命令行启动
```
git clone git@github.com:yourenyouyu/feijiang.git
cd feijiang/
openresty -p feijiang -c feijiang/nginx_prod.conf
```
2. docker方式 部署（推荐）
```
git clone git@github.com:yourenyouyu/feijiang.git
cd feijiang/
docker build -t feijiang .
# 单机部署 基于内存
docker run -d -p 9999:9999 feijiang 
# 集群部署 基于redis
docker run -p 9999:9999 -e "REDIS_HOST=10.101.177.37" -e "LIMIT_MODEL=redis"  feijiang
```

注意：基于redis做策略风控的时候，因为redis默认安全策略的问题，是不允许外部访问的，此处需要配置下其安全策略，允许飞将所在的机器可以远程访问并设置相应的密码。临时测试的话可以在redis-cli中输入如下命令即可
```
CONFIG SET protected-mode no
```
## 软件架构
负载层：OpenResty

后台系统：aspnetcore+mongodb

## 使用说明
### 配置说明

默认情况下飞将基于内存的方式进行策略风控的控制，但是如果你需要分布式部署的话，你可以通过redis等第三方内存型数据库来实现，飞将默认内置了redis策略风控的实现。并通过环境变量来读取相应的配置项。配置项列表如下

```
    LIMIT_MODEL         策略风控使用的存储形式，redis 或者 memory，默认值为 memory
    REDIS_HOST          redis 的 ip 地址 默认值为 127.0.0.1
    REDIS_PORT          redis 的端口号 默认值为 6379
    REDIS_DB            redis 的存储的db 默认值为 0
    REDIS_PASSWORD      redis 的数据库密码 默认不进行密码auth认证
    REDIS_KEEPALIVE     redis 指定连接在池中时的最大空闲超时（以毫秒为单位） 默认60000ms
    REDIS_POOL_SIZE     redis 的连接池的大小 默认值 100
```

### 配置飞将负载的后端管理策略
1. 新增策略
比如具体事件中的限制条件为同ip在2分钟内不能操作30次订单;手机号和ip组合在2分钟内变化次数不能超过10次

则调用飞将负载配置接口如下
```
uri:          http://127.0.0.1:9999/api/v1/policy
method:       POST
content-type: application/json
```
事件策略存储格式如下
```
{
    "app_name": "YSRC",
    "app_id"  : "xxx‐xxx‐xxx",
    "events"  : [
        {
            "event_name" : "用户登录",
            "event_code" : "login",
            "event_type" : "first_hit‐首次命中",
            "policy_list": [
                {
                    "field": [
                        "ip"
                    ],
                    "max_size"   : 30,
                    "time_slice" : 120,
                    "policy_type": "single‐单一策略"
                },
                {
                    "field": [
                        "mobile",
                        "ip"
                    ],
                    "max_size"   : 10,
                    "time_slice" : 120,
                    "policy_type": "group‐组合策略"
                }
            ]
        }
    ]
}
```
响应结果如下
```
{
    "success": true,
    "msg": "ok"
}
```
2. 查看策略

则调用飞将负载配置接口如下
```
uri:          http://127.0.0.1:9999/api/v1/policy
params:       app_id_event=xxx‐xxx‐xxx-login，（不传app_id_event则获取所有策略）
method:       GET
content-type: application/json
```
响应结果如下
```
{
    "success": true,
    "msg": {
        "xxx‐xxx‐xxx-login": [
            {
                "time_slice": 120,
                "max_size"  : 30,
                "field": [
                    "ip"
                ],
                "policy_type": "single‐单一策略"
            },
            {
                "time_slice": 120,
                "max_size": 10,
                "field": [
                    "mobile",
                    "ip"
                ],
                "policy_type": "group‐组合策略"
            }
        ]
    }
}
```
### 风控请求接口
则调用飞将负载配置接口如下
```
uri:          http://127.0.0.1:9999/api/v1/validate
method:       POST
content-type: application/json
```
请求体如下所示
```
{
    "app_id": "xxx‐xxx‐xxx",
    "event_code": "login",
    "data": {
        "mobile": "18605125200",
        "ip": "192.168.1.1"
    }
}
```
响应结果
```
{
    "success": true,
    "uuid": "45afb1c0-2b16-45fb-b181-2e788a52dcc5",
    "result": {
        "risk_level": "ACCEPT",
        "hit_rules": "",
        "hit_policy_code": "xxx‐xxx‐xxx-login"
    }
}
```
