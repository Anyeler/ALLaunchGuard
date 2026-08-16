# 任务：cleanup-unused-code

## 1. 删除与简化（先按当前代码逐项核实再动手）

- [x] 1.1 删除 Examples/BasicExample/BasicExample/CrashSimulator.swift 的 disarmIfFinished()（grep 确认零调用）
- [x] 1.2 删除 Sources/ALLaunchGuard/ALLaunchGuardConfig.swift 的 ALPlaceholderColor.label/secondaryLabel/systemBackground（grep 确认非 UIKit 构建下仅 systemOrange 被引用）
- [x] 1.3 start() 内 1b/1c 两处清零合并为一个条件表达式（在锁改造后的当前结构上定位，注释保留两条裁决依据）；若锁改造已改变该结构则按现状最小合并
- [~] 1.4 survivalScheduler 声明处被 init 覆盖的默认值处理——**跳过**：声明默认值是 init 中闭包捕获 self 重赋的前置条件（全部存储属性须先完成初始化，代码注释已说明）；去除后编译失败，改 IUO 可选型仅换形态无收益，属结构必要性保留

## 2. 注释压缩（保留 design 索引追溯）

- [x] 2.1 ALLaunchGuardSafeModeViewController.swift：快照语义三连注释（类文档/属性注释/viewDidLoad 内）合并为属性注释一处
- [x] 2.2 ALLaunchGuardSafeModeWindow.swift：willConnect 观察者保留 rationale 的重复处（类文档/install/show/分支①/cancelFallbackTimeout）压缩至类文档+分支①两处，保留 "design/fix-lifecycle-review-findings" 索引（install 核实无重复 rationale，无需处理）

## 3. 测试精简

- [x] 3.1 testSuccessfulLaunchResetsCrashCounter 与幂等/阈值测试重叠部分合并（保留全部断言语义）：并入 testSafeModeNotActivatedBelowThreshold，原用例删除（65 → 64）
- [x] 3.2 testAutoPresentFalseDoesNotChangeGuardBehaviour 缩减为 uiConfig setter 冒烟（更名 testAutoPresentFalseUiConfigSetterSmoke）
- [x] 3.3 MockDelegate exitedSafeMode/exitCount 双状态合一：仅保留 exitCount，全部引用点改 exitCount 断言

## 4. 验证与收口

- [x] 4.1 README 残留错别字修正（grep "兑底" 全库应为零或仅历史归档）：README 两处已改，其余命中均在 openspec/changes/archive 历史归档
- [x] 4.2 swift test 全绿：64/64（基线 65，因 3.1 合并减少 1 个用例，断言语义不减）；swift build 0 警告；xcodebuild -scheme ALLaunchGuard -destination 'generic/platform=iOS Simulator'（derivedDataPath /tmp/ag-c4-dd）BUILD SUCCEEDED，0 错误 0 警告
- [x] 4.3 净减行数：8 files changed, 39 insertions(+), 74 deletions(-)，净减 35 行；openspec validate 通过；tasks 已勾选
