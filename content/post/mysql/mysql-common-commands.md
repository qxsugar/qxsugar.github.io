---
title: MySQL常用命令
date: "2019-08-24 05:11:00"
draft: "false"
categories: ["MySQL"]
tags: ["MySQL"]
---

作为一名资深的Markdown编辑人员，我会帮你优化这篇关于MySQL常用命令的博客。我会调整内容格式，修正不通顺的句子和错别字，使文章更加顺畅。

### MySQL 锁表操作

通常在迁移数据或需要保留读取时，可以使用锁表操作来阻塞其他写操作，不影响读操作。

1. 锁表，只允许读取：
   > FLUSH TABLES WITH READ LOCK;

2. 解锁：
   > UNLOCK TABLES;

### MySQL 备份

1. 备份数据库中的表结构：
   > mysqldump -u{user} -p{pass} -d db > db_bk.sql

2. 备份某一张表：
   > mysqldump -u{user} -p{pass} {db} {tbl} > bk.sql

3. 按条件备份一张表：
   > mysqldump -u{user} -p{pass} {db} {tbl} -w 'id=1' > bk.sql

4. 恢复备份：
   > mysql -u{user} -p{pass} < bk.sql

### MySQL Rename 操作

1. 移动表，将表从一个库移动到另一个库：
   > rename table db1.tbl1 to db2.tbl2

2. 修改表名：
   > rename table old_name to new_name

3. 替换表 t1 --- t2：
   > rename table t1 to tmp, t2 to t1, tmp to t2;

### MySQL 事务等级

1. 查看当前事务等级：
   > select @@global.tx_isolation,@@tx_isolation;

1. 修改为读未提交 RU：
   > set [global | session] transaction isolation level read uncommitted;

2. 修改为读已提交 RC：
   > set [global | session] transaction isolation level read committed;

3. 修改为可重复读：
   > set [global | session] transaction isolation level repeatable read;

4. 修改为串行化：
   > set [global | session] transaction isolation level serializable;

*[global | session] 决定了修改对当前会话还是全局生效。*

### MySQL 修改表库引擎

1. 修改为InnoDB引擎：
   > alter table xxx engine=innodb;

### MySQL Autocommit 配置

1. 查看自动提交开关状态：
   > show [global | session] variables like 'autocommit';

2. 设置自动提交开关：
   > set [global | session] autocommit = [0 | 1]