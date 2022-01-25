---
title: "基于traefik实现一个灰度发布系统"
date: "2022-01-06T13:56:48+08:00"
draft: "false"
tags: ["traefik"]
categories: ["traefik"]
---

最近切换到了k8s，用了traefik作为Gateway。

traefik2.0以后支持了自定义middleware功能，可以对请求做一些处理。基于这个功能我们可以实现一个灰度系统。

[developing traefik plugins](https://doc.traefik.io/traefik-pilot/plugins/plugin-dev/)

## 需求功能

1. 能基于用户identify做灰度。
2. 能基于请求版本做灰度。
3. 能基于百分比做灰度。
4. 能基于url关键字做灰度。
5. 系统透明，不需要改动业务代码。

## 设计方案

由于middleware是串行，所以我们可以分成多个middleware来设计。

1. 设计一个middleware根据策略对流量进行染色。
2. 设计一个middleware对不同标记的请求进行转发

## 流程

没有插件流程
{{< mermaid >}}
flowchart LR;
    user(user)
    traefik(traefik gateway)
    svc(prod-svc)
    pod1(pod1)
    pod2(pod2)
    podX(pod...)
    db[(db)]

    user--request-->traefik-->svc
    svc-->pod1-->db
    svc-->pod2-->db
    svc-->podX-->db
{{< /mermaid >}}

灰度系统流程
{{< mermaid >}}
flowchart LR
    user(user)
    traefik(traefik gateway)
    prodSvc(prod-svc)
    alphaSvc(alpha-svc)
    betaSvc(beta-svc)
    m1{middles...}    
    m2{请求染色}
    m3{请求转发}
    user--request-->traefik
    subgraph traefik middlewares
        m1-- next -->m2--next-->m3
    end
    subgraph prod env
        pod1(pod1) 
        pod2(pod...)
    end
    subgraph alpha env
        pod3(pod3)
        pod4(pod...)
    end
    subgraph beta env
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

## 具体实现

具体实现放在了github

[流量染色插件](https://github.com/qxsugar/request-mark)

[流量转发插件](https://github.com/qxsugar/request-dispatch)

## 测试使用

域名准备，域名prod.ppapi.cn，beta.ppapi.cn，alpha.ppapi.cn，alpha1.ppapi.cn分别代表正式环境和其他环境。

部署whoami服务

```yaml
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
    - host: alpha1.ppapi.cn
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

配置traefik启动参数

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

配置解析规则

```yaml
http:
  routers:
    api1:
      rule: host(`prod.ppapi.cn`)
      service: svc
      entryPoints:
        - web
      middlewares:
        - request-mark        # 对流量染色
        - request-dispatch    # 对染色流量进行转发

  services:
    svc:
      loadBalancer:
        servers:
          - url: "http://localhost:8999"

  middlewares:
    request-dispatch:
      plugin:
        request-dispatch:               # 转发插件
          logLevel: DEBUG
          markHeader: TAG               # 染色标记header
          markHosts:
            alpha:                      # 如果TAG: alpha 转发到这里
              - http://alpha.ppapi.cn
              - http://alpha1.ppapi.cn
            beta:
              - http://beta.ppapi.cn

    request-mark:
      plugin:
        request-mark: # 染色插件
          serviceName: api
          logLevel: DEBUG
          redisAddr: redis.com
          redisPassword: "***"
          redisRulesKey: "abc"
          redisRuleMaxLen: 256
          redisLoadInterval: 15
          redisEnable: false
          markKey: TAG                    # 如果匹配规则则设置 TAG: [markValue]
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
              markvalue: beta
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
              markvalue: alpha
              maxVersion: 3.3.3
              minVersion: 2.2.2
              userIds:
                - A003
                - A004
              weight: 10
              path: alpha
```

测试

```text
➜  ~ http prod.ppapi.cn identify:A001
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
Host: beta.ppapi.cn                                 # 被转发到了beta
User-Agent: HTTPie/2.6.0
Accept: */*
Accept-Encoding: gzip, deflate
Identify: A001
Tag: beta                                           # beta染色
X-Forwarded-For: 127.0.0.1, 10.42.0.1
X-Forwarded-Host: prod.ppapi.cn
X-Forwarded-Port: 80
X-Forwarded-Proto: http
X-Forwarded-Server: traefik-758cd5fc85-r8fr4
X-Real-Ip: 127.0.0.1
```

```text 
➜  ~ http prod.ppapi.cn identify:A003
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
Host: alpha.ppapi.cn                                # 被转发到了alpha
User-Agent: HTTPie/2.6.0
Accept: */*
Accept-Encoding: gzip, deflate
Identify: A003
Tag: alpha                                          # alpha 染色
X-Forwarded-For: 127.0.0.1, 10.42.0.1
X-Forwarded-Host: prod.ppapi.cn
X-Forwarded-Port: 80
X-Forwarded-Proto: http
X-Forwarded-Server: traefik-758cd5fc85-r8fr4
X-Real-Ip: 127.0.0.1
```

```text 
# 没有被染色
➜  ~ http prod.ppapi.cn identify:A005
HTTP/1.1 200 OK
Content-Length: 383
Content-Type: text/plain; charset=utf-8
Date: Tue, 25 Jan 2022 02:36:08 GMT

Hostname: ea823154ab9a
IP: 127.0.0.1
IP: 172.17.0.2
RemoteAddr: 172.17.0.1:61106
GET / HTTP/1.1
Host: prod.ppapi.cn
User-Agent: HTTPie/2.6.0
Accept: */*
Accept-Encoding: gzip, deflate
Identify: A005
X-Forwarded-For: 127.0.0.1
X-Forwarded-Host: prod.ppapi.cn
X-Forwarded-Port: 80
X-Forwarded-Proto: http
X-Forwarded-Server: sugardeMacBook-Pro.local
X-Real-Ip: 127.0.0.1
```