---
title: "Traefik配置限流"
date: "2021-12-31T13:56:21+08:00"
draft: "false"
tags: ["traefik"]
categories: ["traefik"]
---

traefik是一个纯go写的Gateway，不仅内置了很多常用的插件，还支持自定义插件。

今天就来配置一下traefik的限流

## 环境准备

这里我是用k3s来测试的，只需要安装好k3s就可以了。

准备一个域名指向安装了k3s的服务器。

## 配置服务

1. 部署一个nginx的deployment

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

2. 配置service

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

3. 配置一个rateLimit的middleware

```yaml
# ref https://traefik.tech/middlewares/ratelimit/
# 参数解析
# average 最大速率，默认情况下是每s请求数，默认值为0，表示没有限制，该速率实际上是用average除以period来定义的。因此，对于低于1 req/s的速率，需要定义一个大于一秒的period
# burst 是在任意短的同一时间段内允许通过的最大请求数，默认为1
# period period与average一起定义了实际的最大速率，例如：r = average / period，默认为1
# 下面这个配置定义，每3s允许一个请求通过
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

4. 配置一个ingress解析

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
      # 使用限流插件
      middlewares:
        - name: z-rate
```

## 执行ab test 来并发请求

```shell
ab -n 100 -c 10 "http://rate.ppapi.cn/"
This is ApacheBench, Version 2.3 <$Revision: 1879490 $>
Copyright 1996 Adam Twiss, Zeus Technology Ltd, http://www.zeustech.net/
Licensed to The Apache Software Foundation, http://www.apache.org/

Benchmarking rate.ppapi.cn (be patient).....done


Server Software:        nginx/1.14.2
Server Hostname:        rate.ppapi.cn
Server Port:            80

Document Path:          /
Document Length:        612 bytes

Concurrency Level:      10
Time taken for tests:   0.534 seconds
Complete requests:      100
Failed requests:        99
   (Connect: 0, Receive: 0, Length: 99, Exceptions: 0)
Non-2xx responses:      99
Total transferred:      19735 bytes
HTML transferred:       2295 bytes
Requests per second:    187.18 [#/sec] (mean)
Time per request:       53.424 [ms] (mean)
Time per request:       5.342 [ms] (mean, across all concurrent requests)
Transfer rate:          36.07 [Kbytes/sec] received

Connection Times (ms)
              min  mean[+/-sd] median   max
Connect:       14   22   5.2     20      37
Processing:    13   25  27.9     21     293
Waiting:       13   22   6.5     21      37
Total:         28   47  28.9     44     318

Percentage of the requests served within a certain time (ms)
  50%     44
  66%     48
  75%     52
  80%     54
  90%     58
  95%     62
  98%     64
  99%    318
 100%    318 (longest request)
```

可以看到100次请求用了0.534s，100次请求只有一次成功了，failed了99次，说明限流成功了