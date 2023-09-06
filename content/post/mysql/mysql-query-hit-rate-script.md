---
title: "分析MySQL命中率"
date: "2019-08-27 14:45:26"
draft: "false"
categories: ["MySQL"]
tags: ["MySQL"]
---

在MySQL查询量很高时，有很多种优化方案可供选择，如分库分表、主从分离等。

在主从分离的情况下，我们如何判断一个读取库的性能是否得到了最大效率的利用呢？

通常，我们会选择查询缓存命中率作为评估读库性能的指标。

目前，InnoDB是主要的MySQL存储引擎，以下内容也是以InnoDB为角度进行讨论。

### 什么是MySQL缓存命中率?

MySQL从磁盘读取数据的成本很高，因此希望MySQL尽可能地从缓存中读取数据。

缓存命中率指的是查询MySQL时，直接从内存中获取结果的次数与总查询次数的比率。
计算公式为：缓存命中率 = 读取内存次数 / 查询总次数。一般而言，我们希望读库的缓存命中率达到99.95%以上。

### MySQL缓存参数配置

#### 查看当前缓存配置大小

```text
show variables like 'innodb_buffer_pool_size';
-- +-------------------------+------------+
-- | Variable_name           | Value      |
-- +-------------------------+------------+
-- | innodb_buffer_pool_size | 8589934592 |
-- +-------------------------+------------+
```

#### 控制台修改缓存大小

```sql
SET GLOBAL innodb_buffer_pool_size = 6442450944;
```

#### 修改缓存大小的方案

1. 修改MySQL配置文件并重启MySQL服务。
2. 在MySQL控制台中修改配置，并同时修改MySQL配置文件，无需重启。

### 计算缓存命中率

根据公式：缓存命中率 = 读取内存次数 / 查询总次数，我们可以计算出缓存命中率。

其中：
- 读取内存次数为"Innodb_buffer_pool_reads"的值。
- 查询总次数为"Innodb_buffer_pool_read_requests"的值。

```sql
show status like '%pool_read%';
-- +---------------------------------------+-------------+
-- | Variable_name                         | Value       |
-- +---------------------------------------+-------------+
-- | Innodb_buffer_pool_read_ahead_rnd     | 0           |
-- | Innodb_buffer_pool_read_ahead         | 91335272    |
-- | Innodb_buffer_pool_read_ahead_evicted | 1457864     |
-- | Innodb_buffer_pool_read_requests      | 99533847127 |
-- | Innodb_buffer_pool_reads              | 626998882   |
-- +---------------------------------------+-------------+
```

然而，这些值表示的是总的数量，并不是一段时间内的差值，因此参考价值不大。
因此，我们需要取一段时间内的差值来计算缓存命中率。

### Bash脚本

为了避免重复性的计算过程，可以使用下面的Bash脚本来计算缓存命中率：

```bash
#!/bin/bash

echo "MySQL缓存命中查询脚本"
read -p "请输入MySQL用户/root： " user
read -p "请输入MySQL密码/''： " pass
read -p "请输入MySQL域名/localhost： " host
read -p "请输入MySQL端口/3306： " port
read -p "请输入查询间隔/60s： " interval

user=${user:-"root"}
pass=${pass:-""}
host=${host:-"localhost"}
port=${port:-"3306"}
interval=${interval:-"60"}

echo "开始提取打点信息"
info=$(mysql -u${user} -p${pass} -h${host} -P${port} -e "show status" 2>/dev/null | egrep 'Innodb_buffer_pool_reads|Innodb_buffer_pool_read_requests' | awk '{print $2}')
if [[ ${info} == "" ]]; then
    echo "提取MySQL配置信息失败"
    exit 1
fi

read -a info1 <<< ${info}
echo "第一次打点信息：请求数 - ${info1[0]}, 读磁盘数 - ${info1[1]}"
echo "休眠${interval}s"
sleep ${interval}

info=$(mysql -u${user} -p${pass} -h${host} -P${port} -e "show status" 2>/dev/null | egrep 'Innodb_buffer_pool_reads|Innodb_buffer_pool_read_requests' | awk '{print $2}')
read -a info2 <<< ${info}
if [[ ${info} == "" ]]; then
    echo "提取MySQL配置信息失败"
    exit 1
fi
echo "第二次打点信息：请求数 - ${info2[0]}, 读磁盘数 - ${info2[1]}"

requests=$((${info2[0]} - ${info1[0]}))
reads=$((${info2[1]} - ${info1[1]}))
echo | awk "{ print \"命中率：\", ($requests-$reads) / $requests * 100.0 }"
```

**使用方法**

```bash
MySQL缓存命中查询脚本
请输入MySQL用户/root： xxx
请输入MySQL密码/''： xxx
请输入MySQL域名/localhost： 
请输入MySQL端口/3306： 
请输入查询间隔/60s： 10
开始提取打点信息
第一次打点信息：
请求数 - 42766927561, 读磁盘数 - 566510284
休眠10s
第二次打点信息：请求数 - 42767040750, 读磁盘数 - 566511295
命中率： 99.1068
```
