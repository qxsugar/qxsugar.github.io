---
title: "基于Traefik实现一个灰度发布系统"
date: "2022-01-06T13:56:48+08:00"
draft: false
tags: ["Traefik"]
categories: ["Traefik"]
---

最近我们切换到了Kubernetes，并选择了Traefik作为我们的网关。从Traefik 2.0版本开始，它支持自定义中间件功能，可以对请求进行处理。我们可以基于这个功能来实现一个灰度发布系统。

[开发Traefik插件](https://doc.traefik.io/traefik-pilot/plugins/plugin-dev/)

### 需求功能

1. 根据用户标识进行灰度发布。
2. 根据请求版本进行灰度发布。
3. 根据百分比进行灰度发布。
4. 根据URL关键字进行灰度发布。
5. 透明化系统，不需要修改业务代码。

### 设计方案

由于Traefik的中间件是串行的，因此我们将其分成多个步骤进行处理。

1. 使用一个中间件对流量进行识别和标记。
2. 使用一个中间件将不同标记的流量转发到不同的服务。

### 流程图

**默认系统流程**
{{< mermaid >}}
flowchart LR;
user(user)
traefik(traefik网关)
svc(prod-svc)
pod1(pod1)
pod2(pod2)
podX(pod...)
db[(db)]

    user--请求-->traefik-->svc
    svc-->pod1-->db
    svc-->pod2-->db
    svc-->podX-->db

{{< /mermaid >}}

**灰度系统流程**
{{< mermaid >}}
flowchart LR
user(user)
traefik(traefik网关)
prodSvc(prod-svc)
alphaSvc(alpha-svc)
betaSvc(beta-svc)
m1{中间件...}    
m2{请求标记中间件}
m3{请求转发中间件}
user--请求-->traefik
subgraph Traefik中间件
m1-- next -->m2--next-->m3
end
subgraph 正式环境
pod1(pod1)
pod2(pod...)
end
subgraph Alpha环境
pod3(pod3)
pod4(pod...)
end
subgraph Beta环境
pod5(pod5)
pod6(pod...)
end
traefik-->m1
m3--"正常请求"-->prodSvc
m3--"alpha 标记"-->alphaSvc
m3--"beta 标记"-->betaSvc
prodSvc-->pod1
prodSvc-->pod2
alphaSvc-->pod3
alphaSvc-->pod4
betaSvc-->pod5
betaSvc-->pod6
{{< /mermaid >}}

## 具体实现代码在GitHub上

1. [请求标记插件](https://github.com/qxsugar/request-mark)
2. [请求转发插件](https://github.com/qxsugar/request-dispatch)

### 测试使用

首先准备好域名，prod.ppapi.cn、beta.ppapi.cn、alpha.ppapi.cn分别代表正式环境、beta环境和alpha环境。

然后按照以下步骤进行操作：

1. 部署whoami服务。
2. 对Traefik启动参数进行配置。
3. 配置规则。
4. 测试请求。

具体操作和测试结果如下：

```yaml
# 部署whoami服务
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
spec:
  selector:
    matchLabels:
      app: whoami
  replicas: 2
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
        - name: app
          image: containous/whoami
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: whoami-svc
spec:
  ports:
    - port: 80
      protocol: TCP
  selector:
    app: whoami
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gray-ppapi.cn
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
    - host: prod.ppapi.cn
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: whoami-svc
                port:
                  number: 80
    - host: alpha.ppapi.cn
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: whoami-svc
                port:
                  number: 80
    - host: beta.ppapi.cn
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: whoami-svc
                port:
                  number: 80
```

对Traefik启动参数进行配置

```yaml
experimental:
  plugins:
    request-dispatch:
      moduleName: github.com/qxsugar/request-dispatch
      version: v0.0.3
    request-mark:
      moduleName: github.com/qxsugar/request-mark
      version: v1.0.1
```

配置规则

```yaml
http:
  routers:
    api1:
      rule: host(`test.ppapi.cn`)
      service: svc
      entryPoints:
        - web
      middlewares:
        - request-mark        # 对流量进行标记
        - request-dispatch    # 对标记进行转发

  services:
    svc:
      loadBalancer:
        servers:
          # 默认流量转发到prod环境
          - url: "http://prod.ppapi.cn"

  middlewares:
    # 请求转发
    request-dispatch:
      plugin:
        request-dispatch: # 转发插件
          logLevel: DEBUG
          markHeader: TAG               # 标记的header
          markHosts:
            alpha: # 如果TAG: alpha 转发到这里
              - http://alpha.ppapi.cn
              - http://alpha1.ppapi.cn
            beta:
              - http://beta.ppapi.cn

    #  请求标记
    request-mark:
      plugin:
        request-mark: # 标记插件
          serviceName: ppapi
          logLevel: DEBUG
          redisAddr: ""
          redisPassword: ""
          redisRulesKey: ""
          redisRuleMaxLen: 256
          redisLoadInterval: 15
          redisEnable: false
          markKey: TAG
          headerVersion: version
          headerIdentify: identify
          cookieIdentify: identify-cookie
          query_identify: identify-query
          rules:
            - serviceName: api
              name: beta
              enable: true
              priority: 100
              type: identify
              markValue: beta
              maxVersion: 3.3.3
              minVersion: 2.2.2
              userIds:
                - A001
                - A002
              weight: 10
              path: beta
            - serviceName: api
              name: alpha
              enable: true
              priority: 100
              type: identify
              markValue: alpha
              maxVersion: 3.3.3
              minVersion: 2.2.2
              userIds:
                - A003
                - A004
              weight: 10
              path: alpha
```

测试请求

```text
➜  ~ http test.ppapi.cn identify:A001
HTTP/1.1 200 OK
Content-Length: 416
Content-Type: text/plain; charset=utf-8
Date: Tue, 25 Jan 2022 02:34:42 GMT
Vary: Accept-Encoding

Hostname: whoami-6577b9784b-sh8zp
IP: 127.0.0.1
IP: 10.42.0.4
RemoteAddr: 10.42.0.213:47482
GET / HTTP/1.1
Host: beta.ppapi.cn                                 # 被转发到了beta环境
User-Agent: HTTPie/2.6.0
Accept: */*
Accept-Encoding: gzip, deflate
Identify: A001
Tag: beta                                           # 标记为beta
X-Forwarded-For: 127.0.0.1, 10.42.0.1
X-Forwarded-Host: prod.ppapi.cn
X-Forwarded-Port: 80
X-Forwarded-Proto: http
X-Forwarded-Server: traefik-758cd5fc85-r8fr4
X-Real-Ip: 127.0.0.1
```

```text 
➜  ~ http test.ppapi.cn identify:A003
HTTP/1.1 200 OK
Content-Length: 418
Content-Type: text/plain; charset=utf-8
Date: Tue, 25 Jan 2022 02:35:25 GMT
Vary: Accept-Encoding

Hostname: whoami-6577b9784b-95lnk
IP: 127.0.0.1
IP: 10.42.0.3
RemoteAddr: 10.42.0.213:49676
GET / HTTP/1.1
Host: alpha.ppapi.cn                                # 被转发到了alpha环境
User-Agent: HTTPie/2.6.0
Accept: */*
Accept-Encoding: gzip, deflate
Identify: A003
Tag: alpha                                          # 标记为alpha
X-Forwarded-For: 127.0.0.1, 10.42.0.1
X-Forwarded-Host: test.ppapi.cn
X-Forwarded-Port: 80
X-Forwarded-Proto: http
X-Forwarded-Server: traefik-758cd5fc85-r8fr4
X-Real-Ip: 127.0.0.1
```

```text 
# 没有被染色
➜  ~ http test.ppapi.cn identify:A005
HTTP/1.1 200 OK
Content-Length: 383
Content-Type: text/plain; charset=utf-8
Date: Tue, 25 Jan 2022 02:36:08 GMT

Hostname: ea823154ab9a
IP: 127.0.0.1
IP: 172.17.0.2
RemoteAddr: 172.17.0.1:61106
GET / HTTP/1.1
Host: test.ppapi.cn
User-Agent: HTTPie/2.6.0
Accept: */*
Accept-Encoding: gzip, deflate
Identify: A005
X-Forwarded-For: 127.0.0.1
X-Forwarded-Host: test.ppapi.cn
X-Forwarded-Port: 80
X-Forwarded-Proto: http
X-Forwarded-Server: sugardeMacBook-Pro.local
X-Real-Ip: 127.0.0.1
```