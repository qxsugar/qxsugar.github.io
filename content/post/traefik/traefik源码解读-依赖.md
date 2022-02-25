---
title: "Traefik源码解读-依赖"
date: "2022-02-25T18:45:10+08:00"
draft: "false"
tags: ["traefik"]
categories: ["traefik"]
---


traefik底层依赖了几个库，阅读之前有必要了解下，不然解读时候容易脑壳疼

### [Alice](https://github.com/containous/alice)

    这个库内容很少，但是traefik用了挺多的，一不留神就绕进去了 这个库很小，核心是把
    
    Middleware1(Middleware2(Middleware3(App)))
    
    改变成
    
    > alice.New(Middleware1, Middleware2, Middleware3).Then(App)
    
    形式，减少嵌套。

### [yaegi](https://github.com/traefik/yaegi)

    traefik 团队实现的go语言动态解析器

### [httputil.ReverseProxy](https://pkg.go.dev/net/http/httputil)

    go 的http的反向代理库，很强大

### [mux.Router](https://github.com/containous/mux)

    traefik 底层路由调度