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
docker run -d -p 9999:9999 feijiang
```
## 软件架构
负载层：OpenResty

后台系统：aspnetcore+mongodb

## 使用说明
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
    "AppName": "YSRC",
    "AppId": "xxx‐xxx‐xxx",
    "Events": [
        {
            "EventName": "用户登录",
            "EventCode": "login",
            "EventType": "FirstHit‐首次命中",
            "PolicyList": [
                {
                    "field": [
                        "ip"
                    ],
                    "maxSize": 30,
                    "timeSlice": 120,
                    "policyType": "single‐单一策略"
                },
                {
                    "field": [
                        "mobile",
                        "ip"
                    ],
                    "maxSize": 10,
                    "timeSlice": 120,
                    "policyType": "group‐组合策略"
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
                "timeSlice": 120,
                "maxSize": 30,
                "field": [
                    "ip"
                ],
                "policyType": "single‐单一策略"
            },
            {
                "timeSlice": 120,
                "maxSize": 10,
                "field": [
                    "mobile",
                    "ip"
                ],
                "policyType": "group‐组合策略"
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
    "appid": "xxx‐xxx‐xxx",
    "eventCode": "login",
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
        "RiskLevel": "ACCEPT",
        "HitRules": "",
        "HitPolicyCode": "xxx‐xxx‐xxx-login"
    }
}
```
