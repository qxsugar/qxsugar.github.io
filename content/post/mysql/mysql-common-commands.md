---
title: mysql常用命令整理
date: "2019-08-24 05:11:00"
draft: "false"
categories: ["mysql"]
tags: ["mysql"]
---

从事后台开发，打交道最多的就是mysql了。所以记录一下常用的mysql指令，就当是笔记吧!

<!-- more -->


#### MySql 锁表操作
一般在做迁移，要保留读时候用，会阻塞其他的写操作，不影响读

1. 锁表，只能读
> FLUSH TABLES WITH READ LOCK
	
2. 解锁
> UNLOCK TABLES


#### MySql备份
1. 备份库中的表结构
> mysqldump -u{user} -p{pass} -d db > db_bk.sql
	
2. 备份某一张表
> mysqldump -u{user} -p{pass} {db} {tbl} > bk.sql
	
3. 按条件备份一张表
> mysqldump -u{user} -p{pass} {db} {tbl} -w 'id=1' > bk.sql
	
4. 恢复	
> mysql -u{user} -p{pass} < bk.sql

#### Mysql Rename 操作
1. 移动表，把表从一个库移动到另一个库
> rename table db1.tbl1 to db2.tbl2

2. 修改表名字
> rename table old_name to new_name

3. 替换表 t1 --- t2
> rename table t1 to tmp, t2 to t1, tmp to t2;

#### MySql 事务等级
1. 查看当前事务等级
> select @@global.tx_isolation,@@tx_isolation;
    
1. 修改成读未提交 RU
> set [global | session] transaction isolation level read uncommitted;
	
2. 修改成读已提交 RC
> set [global | session] transaction isolation level read committed;
	
3. 修改成可重复读
> set  [global | session] transaction isolation level repeatable read;
	
4. 修改成窜行
> set [global | session] transaction isolation level serializable;

*[global | session] 这个修改对当前session生效还是全局生效*

#### MySql 修改表库引擎
1. 修改成Innodb
> alter table xxx engine=innodb;

### MySql autocommit 配置
1. 查看自动提交开关
> show [global | session] variables like 'autocommit';

1. 设置自动提交开关
> set [global | session] autocommit = [0 | 1]
