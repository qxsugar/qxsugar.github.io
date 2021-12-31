---
title: "你真的会用mysql的锁吗"
date: "2020-12-17T11:20:20+08:00"
draft: "true"
categories: ["mysql"]
tags: ["mysql"]
---

高并发情况下学分重复写入问题分析 起因 最近在分析用户学分问题时候遇到一些奇怪的数据，明明只有24节课，用户听完课后切产生了13.5学分。按道理来说，最高学分应该是12分的

提取了异常用户的详细学分流水信息分析，发现有部分课程出现了重复拿学分的情况！ 这个问题有点严重！！！

看了数据库表结构，没有唯一索引。明显是重复写入了

问了其他小伙伴，这个接口以前爆发过问题。后来修了一遍。

写了个SQL分析了下异常数据分布情况

发现10月底11月修了一遍。后面断断续续还是有这种情况 2020-1-2 就出现了17次

问题分析 拉了Athena的最新代码，定位到了写记录的接口 /api/v1/course.finish

分析接口，发现有三个地方对并发做了限制 接口限流了，通过user_id实行限流 接口加了@Transactional保证事物唯一性 credit的查询加了 select * from update 锁

初步怀疑是限流导致处理量变小了，并发下降，以至于重复量变小量。因为限制时间是2s，很有可能已经处理完修改完状态了。但极端情况下还是会出现

场景复现

1. 先去掉限流限制
2. 在代码中加入sleep代码，模拟高并发（这样本地不用很快的请求）

结果发现。如果第一个请求没处理完，再请求一次的话。第二个请求拿到的access.status还是CourseAccessStatus.Started状态。 即使第一个请求已经执行了access.status =
CourseAccessStatus.OnTimeFinished，第二个请求拿到的还是旧的状态

而且 select * from update 也没有生效，并没有成功阻止重复写入问题。

会不会是事物出了问题，尝试把@Transactional渠掉再模拟并发请求 测试发现，第二个请求竟然拿到了最新的状态

基本已经可以确定是事物出了问题了！

具体原因分析 主要代码 @Transactional fun finishAccess
(
currentUser: Student, course: Course, isFinished: Boolean = true, isFinalTestAdd2: Boolean = false
): CourseAccessInfoVO { val major = majorService.getById(course.majorId!!)

// lock credit val credit = studentCreditService .getCreditForUpdate(
Application.newBuilder()
.setId(major.applicationId!!)
.build(), currentUser
)
...... // 课程未开始 if (access.status != CourseAccessStatus.Started) { throw ContextException(CourseAccessNotStartedError())
} // 修改学分逻辑 .... println("=========================修改完成，sleep 5s")
Thread.sleep(5000)
println("=========================修改完成, return")

return access .let(coursePresenter::presentAccessInfo)
} sql执行日期 | 提取事物执行顺序 事物1 begin 事物1 sleep 事物2 begin 事物2 sleep 事物1 end 事物2 end 可以看到@Transactional
会在整个func执行完成后太commit，如果这时候开启了第二个事物，那么第二个事物看到还是事物1没有commit的状态，所以事物2会认为没有给过学分，又重复执行了一次给学分逻辑。

为啥 for update 没效？ 其实 @Transactional + for update 是可以解决并发问题的。 问题出现在for update 锁的是credit表。而判断course_access的逻辑读到的是旧的逻辑。
数据库的隔离级别是重复读。导致第二个事物读到的是旧的course_access状态 精简后的事物顺序。 txn[1009] Begin txn[1009] select t0.id, t0.application_id,
t0.student_id, t0.amount, t0.created_at, t0.updated_at from student_credit t0 where t0.student_id = 12 and
t0.application_id = 1 for update txn[1009] select t0.id, t0.major_id, t0.course_id, t0.student_id, t0.status,
t0.started_at, t0.finished_at, t0.msg_batch_id, t0.msg_progress, t0.duration, t0.created_at, t0.updated_at from
course_access t0 where student_id = 12 and course_id = 43 txn[1009] insert into student_credit_transaction (
application_id, student_id, credit_id, object_id, `change`, amount, `type`, remark, created_at) values (
1,12,12,43,1.0,92.0,6,"当日选修课程(id=43)学习获得学分",now())
txn[1009] update student_credit set amount=amount+1, updated_at=now() where id=12 txn[1009] update course_access set
status=4, finished_at=now(), updated_at=now() where id=1 txn[1012] Begin txn[1009] Commit txn[1012] select t0.id,
t0.application_id, t0.student_id, t0.amount, t0.created_at, t0.updated_at from student_credit t0 where t0.student_id =
12 and t0.application_id = 1 for update txn[1012] select t0.id, t0.major_id, t0.course_id, t0.student_id, t0.status,
t0.started_at, t0.finished_at, t0.msg_batch_id, t0.msg_progress, t0.duration, t0.created_at, t0.updated_at from
course_access t0 where student_id = 12 and course_id = 43 txn[1012] insert into student_credit_transaction (
application_id, student_id, credit_id, object_id, `change`, amount, `type`, remark, created_at) values (
1,12,12,43,1.0,92.0,6,"当日选修课程(id=43)学习获得学分",now())
txn[1012] update student_credit set amount=amount+1, updated_at=now() where id=12 txn[1012] update course_access set
status=4, finished_at=now(), updated_at=now() where id=1 txn[1012] Commit 实验补充 如果按照 tx1 begin tx1 select * table_a for
update tx1 update table_b tx2 begin tx2 select * table_a for update tx2 select * from table_b 这种操作去模拟的话。tx2拿到的是最新数据 tx1
begin tx1 select * table_a for update tx1 update table_b tx2 begin tx2 select * from table_c tx2 select * table_a for
update tx2 select * from table_b 这样拿到的表B的数据是旧的。 初步怀疑，是select时候，会带上一个tx_version的东西，如果在 for
update之后再select，拿到的version是最新的，所以拿到的数据版本也是最新的， 如果是for update之前拿到，那么就拿到了旧的version，理所当然拿到了旧的数据。 解决方案

1. 去掉@Transactional 优点：修改快 缺点：接口无法保证原子性

2. 分布式锁 引入分布式锁 好处：可以保留事物 缺点：需要实现一套分布式锁支持
3. For update 锁加在 course_access 表 好处：修改快，不需要分布锁 缺点：锁行

