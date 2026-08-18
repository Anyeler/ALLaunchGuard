## ADDED Requirements

### Requirement: 生命周期通知写入串行化
生命周期通知回调（进入后台 / 应用终止）对 storage 的写入 SHALL 经与其余核心状态相同的 stateLock 串行化，使任意线程锁内读的 shouldEnterSafeMode 与主队列通知写入不产生未经同一锁保护的数据竞争；临界区内 MUST NOT 触达宿主代码（与既有锁纪律红线一致）。

#### Scenario: 通知写入与并发读串行化
- **WHEN** 主队列通知回调写入后台标记或清零计数的同时，另一线程经 shouldEnterSafeMode 锁内读取 storage
- **THEN** 读路径观察到的是写入前或写入后的某一完整状态，无撕裂或中间态
