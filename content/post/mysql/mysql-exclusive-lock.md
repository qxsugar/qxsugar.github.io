---
title: "并发情况下MySql事务重复写入问题"
date: "2020-12-17T11:20:20+08:00"
draft: "false"
categories: ["mysql"]
tags: ["mysql"]
---

在做数据分析时候，发现有批脏数据，重复写入导致的。

跟踪接口发现，虽然接口最外层套了`@Transactional`，而且接口也限流了，但是还是发生了重复写入。

很奇怪，所以把这个问题拿出来分析了一番。

### 背景

```text
架构：spring boot
语言：kotlin
背景描述：一个课程有12节课，用户学习完成之后会请求/api/v1/course.finish接口，接口里面会判断是否学习完成，如果学习完成之后会增加学分。
```

1. 接口外面做了限流处理，每个uid 2s内只能访问一次接口。
2. 接口里面开了事务处理，加学分之前先查询状态，如果加过学分了就不加学分处理。
3. 数据库没有唯一索引，所以数据库可以重复写入。
4. 接口外面套了`@Transactional保证事物唯一性`，接口里面使用了`select * from credit where user_id = xxx and course_id = xxx for update`来保证唯一。
5. 写个SQL分析了下异常数据分布情况，以前爆发过一次。 后面就很少了，但是断断续续还有。 应该是加了限流器的原因。

### 场景模拟

```kotlin 
// 主要代码
@Transactional 
fun finishAccess(): CourseAccessInfoVO { 
    // lock credit 
    val credit = studentCreditService.getCreditForUpdate()

    // ...
    // 课程未开始 
    if (access.status != CourseAccessStatus.Started) { 
        throw ContextException()
    } 
    
    // 修改学分逻辑 .... 
    println("=========================修改完成，sleep 5s")
    Thread.sleep(5000)
    println("=========================修改完成, return")

    return access.let(coursePresenter::presentAccessInfo)
} 
```

在代码中加入sleep代码（这样本地方便模拟并发），模拟高并发

试了多次发现，如果两个事务同时开启，第一个事务结束了，第二个事务查到的还是旧的状态。

如果去掉`@Transactional`，那么第二个请求能拿到最新的状态。

基本可以确定是事务引起的问题了。

**按道理来说在select for update 应该是最新状态啊？为什么还能拿到旧的？**

分析sql执行顺序

```text 
详细日志
txn[1009] Begin 
txn[1009] select xxx from student_credit where xxx for update 
txn[1009] select xxx from course_access where xxx 
txn[1009] insert into student_credit_transaction (xxx) values (xxx)
txn[1009] update student_credit set amount=amount+1, updated_at=now() where id=12 
txn[1009] update course_access set status=4, finished_at=now(), updated_at=now() where id=1 
txn[1012] Begin 
txn[1009] Commit 
txn[1012] select xxx from student_credit where xxx for update
txn[1012] select xxx from course_access where xxx
txn[1012] insert into student_credit_transaction (xxx) values (xxx)
txn[1012] update student_credit set amount=amount+1, updated_at=now() where id=12 
txn[1012] update course_access set status=4, finished_at=now(), updated_at=now() where id=1 
txn[1012] Commit 
```

为啥`for update`没生效？
按道理`transaction + for update`是可以解决并发问题的。

**问题出在`for update`锁错对象了。代码里判断是的`status`，`for update`锁的是`credit`，所以造成了锁失效。**

### 解决方案

1. 去掉`@Transactional`.优点：修改快 缺点：接口无法保证原子性。
2. `引入分布式锁`.好处：可以保留事物，缺点：需要实现一套分布式锁支持。
3. `for update`锁加在`course_access`表。好处：修改快，不需要分布锁。缺点：锁行，这个表读写大。

