# 设计：add-safe-mode-launch-tasks

## Context

2.0 门控范式：安全模式下宿主 return true 跳过全部启动任务。日志等最小模块的初始化目前只能由宿主在安全模式分支手写，范式不显式。ALLaunchGuard 不依赖 MPLaunch（硬约束，用户明确）——本钩子为纯闭包，MPLaunch 桥接发生在宿主闭包内（MPLaunch 侧 runSafeModeTasks 为 mplaunch 仓库独立增量，见并行变更）。

## Goals / Non-Goals

**Goals:** 一等概念的最小任务钩子；三触发路径统一执行点；每进程一次幂等；零破坏。

**Non-Goals:** 任务依赖图/拓扑序（由宿主或 MPLaunch 侧负责）；异步任务（首期仅同步轻量）；任务失败重试。

## Decisions

### D1. 执行点：activateSafeMode() 首行
三个触发路径（start 阈值 L197、粘滞 L168、DEBUG 入口 L283）均汇合于 private `activateSafeMode()`（L324）。在其首行（isInSafeMode = true 之后、delegate 之前）执行，保证最小模块先于委托回调与窗口安装就绪。任务在 isInSafeMode 置位后执行，任务内可安全读取该状态。

### D2. 幂等：实例级 Bool 门控
`didRunSafeModeLaunchTasks` 实例属性，首次执行后置 true；同一进程内重复激活（如 DEBUG 入口叠加）不重复执行。进程重启即新实例，语义为"每进程一次"。

### D3. 同步顺序执行，不提供并发
最小任务约束为轻量同步（文档化）；并发/异步需求由宿主在闭包内自行派发，库不承担调度。

### D4. 依赖边界自检
Sources/ 内 grep "MPLaunch|LaunchSession" 零命中作为验证项；README 与 Example 中允许提及（宿主层桥接示例）。

## Risks / Trade-offs

- [任务阻塞主线程拖慢安全模式首帧] → 文档约束轻量；Example 演示正确用法。
- [任务抛错（Swift 无受检异常，仅 fatalError 类）] → 安全模式下 crash 由粘滞标记兜底（下次仍进安全模式），语义自洽；文档警示。
- [宿主把重量级初始化塞进钩子] → 文档明确边界；不做运行时防护。

## Migration Plan

实现 → swift test + iOS 构建 → 归档。纯增量，无迁移。

## Open Questions

（无。）
