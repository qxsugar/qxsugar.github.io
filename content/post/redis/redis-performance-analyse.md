---
title: "一次Redis内存分析记录"
date: "2019-08-14 00:00:00"
draft: false
categories: ["redis"]
tags: ["Redis"]
---

我们公司使用的是自建的Redis机器。最近，我们迁移了一次机房，并顺便使用了第三方的Redis存储。然而，没过多久，Redis的内存就满了。

### 事情的起因

一开始，我们购买了4G的内存，迁移过程中一切正常。然而，过了几天，内存慢慢地涨到了4G。于是我们又扩展到了8G，但过了几天之后，内存又满了。为了不影响服务，我们只能将内存增加到12G。没想到过了一个周末，12G的内存也快满了。这已经到了无法容忍的地步，我们必须查找原因！

### 分析rdb

首先，我们备份了一份rdb文件进行分析。这里推荐一个开源工具[rdr](https://github.com/xueqiu/rdr)。虽然这个工具没有redis-rdb-tools那么强大，但它可以快速分析大概的内容和各种类型的占比，而且是可视化的。rdr的原本下载链接已经失效，这是[新的下载链接](https://github.com/gohouse/rdr/releases/tag/v0.1.0)。

#### 运行

```bash 
./rdr-amd64-v0.1-linux.bin show -p 8080 redis.rdb
# 生成好之后，我们在8080端口打开，就可以看到分析结果了。
```

![result](https://blog-1252018492.cos.ap-nanjing.myqcloud.com/misc/NOqC6S.png)

从这里可以看到，我们主要的内存使用了3.5G，那么为什么12G都快满了呢？我们并没有使用那么多，只能找售后了。

后来与服务方的技术交流才让我们知道，原来是内存碎片率太高了。mem_fragmentation_ratio都快到2.5了。默认的内存回收机制和我们自己搭建的集群有所区别，导致内存一直在涨，不释放。

查明原因后，这个问题就交给运维哥哥去处理了～

### 虽然解决了内存的问题，但是我还是想继续分析下Redis，总感觉有人在代码里留下了秘密

```bash
# 我们先安装redis-rdb-tools
pip install rdbtools

# 把rdb文件转成csv文件
rdb -c memory redis.rdb -f redis.csv

# 看一下csv的格式
less redis.csv
# database 数据库
# type key类型
# key key
# size_in_bytes key的内存大小(byte)
# encoding value的存储编码形式
# num_elements key中的value的个数
# len_largest_element key中的value的长度
# expiry key过期时间

# 我们过滤出csv里没有时间的key，放到tmp.log里
cat redis.csv | awk -F ',' '{ if($NF == ""){print $3} }' > tmp.log

# 然后按同种类型key排序。
cat tmp.log | sort | more
# 现在可以more一下，分析一下这些不会过期的key是什么了。
```

### 结束

忙活了一早上，Redis的事情终于可以告一段落了。Redis的数据是容易丢的，而且里面的数据可读性也很差。有时候，数据还是msgpack或者pickle处理过的。我感觉如果没有过期时间的缓存是很危险的！！主从出问题容易丢，且长期占用内存。线上的东西一定要规范好才行，囧。