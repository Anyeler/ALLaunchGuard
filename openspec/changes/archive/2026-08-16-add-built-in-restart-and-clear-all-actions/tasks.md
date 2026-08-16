# 任务：add-built-in-restart-and-clear-all-actions

## 1. ALLaunchGuardRestartAction（TDD）

- [x] 1.1 先写测试（ALLaunchGuardFixActionTests.swift）：元数据断言（title/icon/isDestructive）；perform 时序——注入 exitHandler 记录调用次序，经编排层执行后断言"storage 粘滞标记已清零（reset 生效）先于 exitHandler 被调用"；exitHandler 恰好一次
- [x] 1.2 `Sources/ALLaunchGuard/ALLaunchGuardFixAction.swift` 追加 ALLaunchGuardRestartAction（按 design D1，completion 先行 + 主队列晚一拍 exitHandler，load-bearing 注释）

## 2. ALLaunchGuardClearAllCacheAction（TDD）

- [x] 2.1 先写测试：注入 sandboxRoot 构造 Documents/（含文件）、Library/Caches/（含文件）、Library/Preferences/（含文件）、tmp/（含文件）、SystemData/、.Trash/（含文件）、游离文件与游离目录的完整结构 → 执行后断言：Documents 与 SystemData 完整保留、Library/Preferences 保留、Library/Caches 内容清空、tmp 内容清空（目录在）、.Trash 清空、游离项删除；自定义 protectedTopLevelItems 生效；条目预置缺失场景幂等成功；单项失败（构造只读目录）继续清理且聚合 completion(false)
- [x] 2.2 实现 ALLaunchGuardClearAllCacheAction（按 design D2：删除循环内逐条白名单评估、Library→Caches 特判、fileExists 幂等、失败聚合、utility 队列 + autoreleasepool、internal init 注入）

## 3. 文档与验证

- [x] 3.1 README：内置动作清单更新（五动作）、全清范围表（保护/清理明细）、重启动作末位注册指引（代码示例）、与既有重启按钮关系说明、ClearCache vs ClearAllCache 档位选择建议
- [x] 3.2 swift test 全绿（55 存量 + 新增）；swift build 0 新增警告；xcodebuild -scheme ALLaunchGuard -destination 'generic/platform=iOS Simulator'（独立 derivedDataPath）0 错误 0 警告
- [x] 3.3 openspec validate 通过，tasks 勾选完成
