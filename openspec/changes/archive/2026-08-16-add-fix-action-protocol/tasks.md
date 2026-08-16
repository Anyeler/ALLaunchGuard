# 任务：add-fix-action-protocol

## 1. 协议与内置动作（TDD：先写失败测试再实现）

- [x] 1.1 新增 `Tests/ALLaunchGuardTests/` 中的动作层测试：MockFixAction（可控制 completion 成败）、闭包包装执行断言、内置清缓存动作（临时目录注入或基于 Caches 真实目录构造内容后清理验证；Caches 不存在的成功路径用注入目录路径实现可测）
- [x] 1.2 新建 `Sources/ALLaunchGuard/ALLaunchGuardFixAction.swift`：`public protocol ALLaunchGuardFixAction: AnyObject`（title / iconSystemName: String? / isDestructive（协议扩展默认 false）/ perform(completion: @escaping (Bool) -> Void)）；`public final class ALLaunchGuardClosureAction`（标题/图标/破坏性/执行闭包构造）；`public final class ALLaunchGuardClearCacheAction`（internal 可注入 cachesDirectoryURL 以便测试，默认 FileManager Caches；遍历删除内容，目录不存在视为成功，任一项失败整体 false；默认中文标题与 SF Symbol 图标名）

## 2. 注册与编排

- [x] 2.1 `Sources/ALLaunchGuard/ALLaunchGuard.swift`：新增 `public var fixActions: [ALLaunchGuardFixAction] = []`；新增编排方法 `public func perform(_ action: ALLaunchGuardFixAction, completion: ((Bool) -> Void)? = nil)`——调用 action.perform，收到结果后统一 DispatchQueue.main.async：成功 → 复用 reset()（幂等）+ 委托成功回调；失败 → 状态不动 + 委托失败回调
- [x] 2.2 `Sources/ALLaunchGuard/ALLaunchGuardDelegate.swift`：追加 `func launchGuard(_ launchGuard: ALLaunchGuard, didFinishFixAction action: ALLaunchGuardFixAction, success: Bool)`，extension 默认空实现
- [x] 2.3 测试：mock 动作成功 → isInSafeMode 变 false、storage 计数与粘滞标记清零、exit 回调一次、didFinishFixAction(success: true) 触发；失败 → 状态全部不变、无 exit 回调、success: false 触发；多次成功动作 reset 幂等（exit 回调仅在曾处于安全模式时触发一次）；fixActions 默认空数组且赋值保序；MockDelegate（现有）无需改动即可编译（默认实现验证）

## 3. 验证与收口

- [x] 3.1 `swift test` 全绿（30 个存量 + 新增约 8-10 个），输出测试摘要
- [x] 3.2 `swift build` 0 新增警告；确认旧 `fixHandler` 路径未动（ALLaunchGuardViewController 不改）
- [x] 3.3 顺手修复（验证报告遗留项）：Tests/ALLaunchGuardTests/ALLaunchGuardTests.swift 中注释错别字“兑底清零”改为“兜底清零”（仅注释，不改逻辑）
