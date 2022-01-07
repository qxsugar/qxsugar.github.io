---
title: "基于traefik实现灰度系统"
date: "2022-01-06T13:56:48+08:00"
draft: "true"
tags: ["traefik"]
categories: ["traefik"]
---

在对产品进行发布时候，我们期望能对先小量发布，对一小部分用户生效，验证没问题了再扩大发布范围，直到全量发布。
目前市面上存在很多发布策略
1. 蓝绿部署
2. 灰度部署
3. 金丝雀发布
4. ab测试

## 背景
    traefik2.0以后支持自定义middleware插件，可以对请求做一些处理。
    所以

    目前市面上的发布策略有几种策略，
    1. 蓝绿部署
    2. 滚动发布
    3. 灰度发布
    4. 金丝雀发布
    灰度发布是对用户影响范围最小的，控制力度也是最灵活的。
    所以

    产品迭代时候，我们期望能对一部分用户做灰度，或者对版本做灰度，不希望一下子流量都切换到新的服务，那么这时候我们就需要灰度系统了。
    现在市面上的发布策略有几种
    但是市面上大多数灰度系统都是基于百分比的，对用户做控制的比较少，（istio也许可以做到，了解不深）。
    traefik2.0以后的版本支持了middleware插件，可以对流量做一些操作，所以插件写在这里是最合适的。

## 灰度系统需求功能

### 规则整理

1. 能基于用户ID做灰度。
2. 能基于用户版本做灰度。
3. 能基于百分比做灰度。
4. 能基于url关键字做灰度。

### 需求整理

1. 配置要简单，不需要每次都更新配置文件。
2. 性能要好，不能traefik影响性能。
3. 系统透明，不需要改动现有代码。

## 设计方案

目前traefik提供了middleware插件式开发，可以对流量做一些操作。

```go 
func (a *Abtest) ServeHTTP(rw http.ResponseWriter, req *http.Request) {}
```

### 技术方案

1. 设计一个转发插件，对满足标签的请求做转发
2. 设计一个标签插件，匹配请求规则，打上标签

*为什么要分开成两个系统？*

1. 标签插件并不一定是必须的，如果已有自己的系统，可以直接使用转发插件。
2. 转发插件只需要处理转发就好了，职责明确

### 依赖服务

1. 依赖redis，路由规则配置需要配置在redis，标签插件需要读取路由规则来做灰度

## 准备

### 服务准备，域名prod.ppapi.cn，beta.ppapi.cn，alpha.ppapi.cn，alpha1.ppapi.cn分别代表正式环境和灰度环境

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

## 插件地址

[根据标签转发请求插件](https://github.com/qxsugar/traefik-gray-forward)

[给请求打标签插件](https://github.com/qxsugar/traefik-gray-tag)
