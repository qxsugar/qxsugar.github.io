---
title: "Traefik配置限流"
date: "2021-12-31T13:56:21+08:00"
draft: "false"
tags: ["Traefik"]
categories: ["Traefik"]
---

Traefik是一个使用纯Go编写的网关，它不仅内置了许多常用的插件，还支持自定义插件。

今天我们来配置Traefik的限流功能。

### 环境准备

我将使用K3s来演示，并且K3s默认使用的Ingress控制器就是Traefik。你需要准备一个域名，指向安装了K3s的服务器。

### 配置服务

1. 首先，我们部署一个NGINX的Deployment。

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.14.2
          ports:
            - containerPort: 80
```

2. 接着，配置一个Service将流量指向NGINX的Deployment。

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-svc
spec:
  ports:
    - port: 80
      protocol: TCP
  selector:
    app: nginx
```

3. 然后，我们配置一个Rate Limit的中间件。

```yaml
# 参考文档 https://doc.traefik.io/traefik-middleware/rate-limiter/
# 参数解析：
# average: 最大速率，默认情况下是每秒请求数，默认值为0，表示没有限制。该速率实际上是用average除以period来定义的。因此，对于每秒请求低于1的速率，需要定义一个数值大于1秒的period。
# burst: 是在任意短的同一时间段内允许通过的最大请求数，默认为1。
# period: 与average一起定义了实际的最大速率。例如：r = average / period，默认为1。
# 以下配置定义每3秒允许通过一个请求
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: z-rate
spec:
  rateLimit:
    average: 1
    burst: 1
    period: 3
```

4. 最后，配置一个Ingress规则。

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: nginx
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`rate.ppapi.cn`)
      kind: Rule
      services:
        - name: nginx
          port: 80
      # 使用限流中间件
      middlewares:
        - name: z-rate
```

### 使用ab工具进行并发请求测试

```text
ab -n 100 -c 10 "http://rate.ppapi.cn/"
```

我们可以看到100次请求用了0.534秒，其中有99次失败了，只有一次请求成功，说明限流成功了。