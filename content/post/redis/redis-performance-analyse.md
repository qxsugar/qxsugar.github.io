---
title: "一次Redis内存分析记录"
date: "2019-08-14 00:00:00"
draft: "false"
categories: ["redis"]
tags: ["Redis"]
---

公司用的是自建Redis机器。 最近迁移了一次机房。 顺便用上了第三方的Redis存储。 然后，过了不久，redis内存就满了。

<!-- more -->

### step1 事情起因

一开始我们买了4G内存，迁移过程还好好的 过了几天，就慢慢的涨到了4G，然后我们又扩到了8G， 过几天之后，又满了，为了不影响服务，只能开到12G， 没想到过了一个周末，12G也快满了。 已经到了无法容忍的地步了，必须要查一下原因了！

### step2 分析rdb

我们先备份了一份rdb文件回来分析. 这里推荐一个开源工具[rdr](https://github.com/xueqiu/rdr)
这个工具没有redis-rdb-tools那么强大， 但是却可以快速分析大概内容，各种类型占比，而且是可视化的
rdr原本的下载链接失效了。[新的下载链接](https://github.com/gohouse/rdr/releases/tag/v0.1.0)

运行
> ./rdr-amd64-v0.1-linux.bin show -p 8080 redis.rdb

生成好之后。我们打开8080端口，就可以看到分析结果了

![](https://blog-1252018492.cos.ap-nanjing.myqcloud.com/misc/NOqC6S.png)

从这里可以看到，我们主要内存才用了3.5G，那么为什么12G都快满了呢， 后来和服务方技术交流才知道是内存碎片率太高了，mem_fragmentation_ratio都快2.5了。 默认的内存回收机制和我们自己搭建的集群有区别。
导致内存一直在涨，不释放。

查明原因有 后面这个事情就交给运维哥哥去处理了～

### step3 虽然解决了内存的问题。但是还是想继续分析下redis，总感觉有人在代码里留下了秘密

我们先装个redis-rdb-tools
> pip install rdbtools

把rdb文件转成csv文件
> rdb -c memory redis.rdb -f redis.csv

看一下csv的格式
> less redis.csv

列含义如下

```
database 数据库
type key类型
key key
size_in_bytes key的内存大小(byte)
encoding value的存储编码形式
num_elements key中的value的个数
len_largest_element key中的value的长度
expiry key过期时间
```

我们过滤出csv里没有时间的key，放到tmp.log里
> cat redis.csv | awk -F ',' '{ if($NF == ""){print $3} }' > tmp.log

然后按同种类型key排序。
> cat tmp.log | sort | more

现在可以more一下，分析一下这些不会过期的key是啥了。

### step4 END

忙活了一早上。redis的事情终于可以告一段落了。 redis的数据是容易丢的。 而且里面的数据可读性也很差。有时候还是msgpack或者pickle处理过的。 感觉如果没有过期时间的缓存是很危险的！！！主从出问题容易丢，且长期占内容
线上的东西一定要规范好才行，囧