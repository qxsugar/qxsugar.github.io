---
title: "Traefik源码解读-基础准备"
date: "2022-02-25T18:45:10+08:00"
draft: "false"
tags: ["traefik"]
categories: ["traefik"]
---

最近写了几个traefik中间键，感觉traefik作为Gateway很棒。

而且是纯go开发的，所以找了个时间解读了下traefik v2.6的源码，顺便学习一下大佬们的技术。

正式解读之前，需要做一些准备，包括有些依赖库，不然解读起来很费脑子。

## 本地环境准备

### console 代码

```bash
git clone --branch v2.6 git@github.com:traefik/traefik.git
```

### 配置traefik

在`cmd/traefik`目录下增加两个文件`traefik.yaml`和`http.yaml`

```yaml
//traefik.yaml
global:
  checkNewVersion: true
  sendAnonymousUsage: true
entryPoints:
  web:
    address: :80
  websecure:
    address: :443
log:
  level: DEBUG
providers:
  file:
    filename: ./http.yaml
```

```yaml
// http.yaml
http:
  routers:
    api:
      rule: host(`prod.ppapi.cn`)
      service: svc1
      entryPoints:
        - web
  services:
    svc1:
      loadBalancer:
        servers:
          - url: "http://localhost:8999"
```

这里我是本地调试，所以配置了个`prod.ppapi.cn`指向`127.0.0.1`
启动一个service作为endpoint

```bash
docker run -d -p 8999:80 -it containous/whoami
```

启动traefik

```bash
cd cmd/traefik
go run traefik.go 
```

等待依赖下载完成就可以启动traefik了。

接下来`curl prod.ppapi.cn` 就可以看到`whoami`的输出信息了。

到这里为主，traefik环境就搭建好了。接下来就可以调试了。

下一章讲会介绍traefik用到的几个依赖。