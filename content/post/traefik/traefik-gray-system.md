---
title: "基于traefik实现一个灰度发布系统"
date: "2022-01-06T13:56:48+08:00"
draft: "true"
tags: ["traefik"]
categories: ["traefik"]
mermaid: true
---

在对feature进行发布时候，我们期望feature能逐步发布，产生的bug影响访问缩小，或者只对小部分用户生效，有问题能够及时回滚，就需要设计一套灰度发布系统了。

## 背景

    traefik2.0以后支持自定义middleware插件，可以对请求做一些处理。
    所以我们可以通过在middleware层控制流量来实现灰度发布系统

## 功能需求整理

### 规则整理

1. 能基于用户identify做灰度。
2. 能基于用户版本做灰度。
3. 能基于百分比做灰度。
4. 能基于url关键字做灰度。

### 需求整理

1. 配置要简单，能热更新。
2. 性能要好，不能traefik影响性能。
3. 系统透明，不需要改动业务代码。

## 设计方案

1. 设计一个根据策略对流量进行染色的middleware。
2. 设计一个根据表示进行转发的middleware。

默认traefik处理流程
![](https://static-1252018492.cos.ap-nanjing.myqcloud.com/uPic/FdBwfN.png)

增加插件后的流程
![](https://static-1252018492.cos.ap-nanjing.myqcloud.com/uPic/9uKZNf.png)

*为什么要分开成两个插件？*

1. 分开能更好的解耦，染色不一定要用插件，可以在其他Gateway层染色。
2. 转发和染色无关系，职责明确

## 实现

[流量染色插件](https://github.com/qxsugar/request-mark)

[流量转发插件](https://github.com/qxsugar/request-dispatch)

## 使用

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

部署插件
