---
title: "Traefik源码解读-基础准备"
date: "2022-02-25T18:45:10+08:00"
draft: "true"
tags: ["traefik"]
categories: ["traefik"]
---

1. yaegi 的index错误和go的错误不一致
2. 在插件里使用reverseProxy会有context canceled问题。导致499变成了500