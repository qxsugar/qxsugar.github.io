---
title: "分析MySql命中率"
date: "2019-08-27 14:45:26"
draft: "false"
categories: ["mysql"]
tags: ["mysql"]
---

当一个mysql的查询量很高时候，有很多种优化方案。

分库分表，主从分离等都是不错的选择。

主从分离情况下，我们怎么权衡一个DB的性能有没有被最大效率的利用呢？

通常我们会选择查询缓存命中率来作为读库的一个指标。

由于现在DB引擎都是Innodb居多。 所以下面都是以Innodb的角度来说。

### MySql 缓存命中率是什么?

    MySql查询读取磁盘的代价是很高的。
    所以我们希望MySql尽可能的读取缓存。
    缓存命中就是查询MySql的时候，直接从内存中得到结果返回。
    计算公式：缓存命中率 = 读内存次数 / 查询总数。一般来说。我们希望读库的缓存命中率达到99.95%以上。

### MySql 缓存参数配置

#### 查看当前缓存配置大小

```mysql
show variables like 'innodb_buffer_pool_size';
-- +-------------------------+------------+
-- | Variable_name           | Value      |
-- +-------------------------+------------+
-- | innodb_buffer_pool_size | 8589934592 |
-- +-------------------------+------------+
```

#### 控制台修改缓存大小

```mysql
SET GLOBAL innodb_buffer_pool_size = 6442450944;
```

#### 修改缓存大小方案

1. 修改mysql配置文件并重启mysql
2. 在mysql控制台修改配置，同时修改配置，不用重启

### 缓存命中率计算

    根据公式 缓存命中率 = 读内存次数 / 查询总数 我们很容易算出命中率
    读内存次数 = "Innodb_buffer_pool_reads"
    查询总次数 = "Innodb_buffer_pool_read_requests"

```mysql
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

>

    但是这两个值是总的数量,并不是一段时间内的，参考价值不大，所以我们要取一段时间内的差值来算
    命中率 = (第二次读内存次数 - 第一次读内存次数) / (第二次查询总数 - 第一次查询总数)

### bash脚本

算了好多次，都是重复性的，有点繁琐，所以写了个脚本来算

```bash
echo "MYSQL缓存命中查询脚本"
read -p "请输入 mysql 用户/root              " user
read -p "请输入 mysql 密码/''                " pass
read -p "请输入 mysql 域名/localhost         " host
read -p "请输入 mysql 端口/3306              " port
read -p "请输入       间隔/60s               " slp

user=${user:-"root"}
pass=${pass:-""}
host=${host:-"localhost"}
port=${port:-"3306"}
slp=${slp:-"60"}

echo "开始提取打点信息"
info=`mysql -u${user} -p${pass} -h${host} -P${port} -e "show status" 2>/dev/null | egrep 'Innodb_buffer_pool_reads|Innodb_buffer_pool_read_requests' | awk '{print $2}'`
if [[ ${info} == "" ]]; then
    echo "提取mysql配置信息失败"
    exit 1
fi

read -a info1 <<< ${info}
echo "第一次打点信息 请求数: ${info1[0]}, 读磁盘数: ${info1[1]}"
echo "休眠${slp}s"
sleep ${slp}

info=`mysql -u${user} -p${pass} -h${host} -P${port} -e "show status" 2>/dev/null | egrep 'Innodb_buffer_pool_reads|Innodb_buffer_pool_read_requests' | awk '{print $2}'`
read -a info2 <<< ${info}
if [[ ${info} == "" ]]; then
    echo "提取mysql配置信息失败"
    exit 1
fi
echo "第二次打点信息 请求数: ${info2[0]}, 读磁盘数: ${info2[1]}"

requests=`expr ${info2[0]} - ${info1[0]}`
reads=`expr ${info2[1]} - ${info1[1]}`
echo | awk "{ print \"命中率:\", ($requests-$reads) / $requests * 100.0 }"
```

**使用方法**

```bash
MYSQL缓存命中查询脚本
请输入 mysql 用户/root              xxx
请输入 mysql 密码/''                xxx
请输入 mysql 域名/localhost
请输入 mysql 端口/3306
请输入       间隔/60s               10
开始提取打点信息
第一次打点信息 请求数: 42766927561, 读磁盘数: 566510284
休眠10s
第二次打点信息 请求数: 42767040750, 读磁盘数: 566511295
命中率: 99.1068
```

~~只需要很简单的一个计算，就能知道我们的mysql内存使用率有没有达到最高效了。~~

目前大部分生产的MySql都已经上云了，这些脚本意义已经不是很大了。