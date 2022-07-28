---
title: "解读Traefik源码-准备"
date: "2022-02-25T18:45:10+08:00"
draft: "false"
tags: ["traefik"]
categories: ["traefik"]
---

最近接触了traefik，写了几个traefik middle，感觉traefik很棒。

所以找了个时间看下traefik源码，学习一下。

以后出问题了也好解决。

### clone代码，这里使用v2.6版本

```bash
git clone --depth 1 --branch v2.6 git@github.com:traefik/traefik.git
```

### 配置traefik

在`cmd/traefik`目录下增加两个文件`traefik.yaml`和`http.yaml`

```yaml
# traefik.yaml
# traefik启动配置文件
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
# http.yaml
# traefik动态配置文件，这个修改后traefik会热加载
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

**这里我是本地调试，所以配置了个`prod.ppapi.cn`指向`127.0.0.1`**

```bash
# 启动一个service作为endpoint
docker run -d -p 8999:80 -it containous/whoami
```

### 启动traefik

```bash
cd cmd/traefik
go run traefik.go 
```

等待依赖下载完成启动traefik，输入`curl prod.ppapi.cn(prod.ppapi.cn的host是127.0.0.1)` 可以看到`whoami`输出信息。

到这一步，traefik代码环境就完成了，接下来就可以调试分析traefik代码了。