---
title: 并发情况下MySQL事务重复写入问题
date: "2020-12-17T11:20:20+08:00"
draft: "false"
categories: ["MySQL"]
tags: ["MySQL"]
---

在进行数据分析时，我发现存在批量脏数据的问题，这是由于重复写入导致的。经过跟踪接口的调用，我发现尽管接口的外层使用了`@Transactional`进行事务控制，并且限流了接口的访问频率，但仍然出现了重复写入的情况。这个问题让我很困惑，因此我对这个问题进行了分析。

### 背景

```text
架构：Spring Boot
语言：Kotlin
背景描述：一个课程有12节课，用户学习完成后会调用接口/api/v1/course.finish。接口会判断课程是否已学习完成，如果是，则增加学分。
```

1. 接口进行了访问限流处理，每个uid在2秒内只能访问一次接口。
2. 接口使用了事务处理，在增加学分之前会先查询状态，如果已经增加过学分，则不再进行处理。
3. 数据库中没有设置唯一索引，在数据库中可以重复写入。
4. 接口的外层使用了`@Transactional`确保事务的唯一性，接口内使用了`select * from credit where user_id = xxx and course_id = xxx for update`来保证事务的唯一性。
5. 我使用了SQL分析来查看异常数据的分布情况，之前曾经出现过一次爆发，之后很少发生，但偶尔还会出现。这可能与添加了限流器有关。

### 场景模拟

```kotlin
// 主要代码
@Transactional
fun finishAccess(): CourseAccessInfoVO {
    // 对credit进行加锁
    val credit = studentCreditService.getCreditForUpdate()

    // ...
    // 如果课程还未开始
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

在代码中加入了`Thread.sleep`来模拟并发，进行了多次尝试发现，如果两个事务同时开启，第一个事务结束后，第二个事务仍然能够查询到旧的状态。如果去掉`@Transactional`，第二个请求则能够查询到最新的状态。这基本上可以确定是事务引起的问题。

按理说，使用`select for update`后，应该能够查询到最新的状态，为什么仍然获取到了旧的状态呢？

分析SQL执行顺序：

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

为什么`for update`没有生效呢？按理说`transaction + for update`应该可以解决并发问题。

问题出在`for update`锁对象的选择上。代码中判断的是`status`，而使用`for update`锁住的是`credit`对象，所以导致了锁失效。

### 解决方案

1. 去掉`@Transactional`。优点：修改简单。缺点：接口无法保证原子性。
2. 引入分布式锁。优点：保留事务，不用修改太多代码。缺点：需要实现一套分布式锁机制。
3. 将`for update`锁加在`course_access`表上。优点：修改简单，无需分布式锁。缺点：锁行，对该表的读写压力较大。

根据具体情况选择适合的解决方案。