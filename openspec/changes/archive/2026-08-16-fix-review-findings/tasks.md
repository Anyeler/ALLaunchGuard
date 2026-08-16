# 任务：fix-review-findings

## 1. 窗口超时可恢复（缺陷 ①）

- [x] 1.1 修改 `Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift`：超时创建降级 frame 窗口时不移除 willConnect 观察者（仅取消超时任务）；willConnect 回调改为三分支——已挂 scene → 清理返回；降级 frame 窗口（windowScene == nil）或 nil → 以新 scene 创建 UIWindow(windowScene:)、迁移同一 rootViewController、废弃旧降级窗口、makeKeyAndVisible、清理观察者；对外幂等语义保持（同一时刻仅一个有效窗口）
- [x] 1.2 代码走查自查单：三种状态迁移（未创建→挂载 / 降级→迁移 / 已挂载→忽略）互斥且无泄漏；deinit 兜底清理仍覆盖

## 2. 空动作兜底与菜单页加固（缺陷 ②③④）

- [x] 2.1 `Sources/ALLaunchGuard/ALLaunchGuardFixAction.swift` 新增 `public final class ALLaunchGuardResetSafeModeAction`（标题“重置安全模式”、图标 arrow.counterclockwise、isDestructive true、perform 直接 completion(true)，成功后经编排层 reset）
- [x] 2.2 `Sources/ALLaunchGuard/ALLaunchGuardSafeModeViewController.swift`：viewDidLoad 快照 `snapshotActions`（fixActions 为空时注入 ALLaunchGuardResetSafeModeAction），numberOfRows/configure/didSelect 全部使用快照；移除旧空态纯提示逻辑（空列表现在必有兜底动作）；注释更新快照语义
- [x] 2.3 `Sources/ALLaunchGuard/ALLaunchGuard.swift` 的 `presentSafeModeMenu()`：present 闭包内检查 key window rootVC 的 presented 链顶层是否已是 ALLaunchGuardSafeModeViewController，是则跳过
- [x] 2.4 `start()` 首行加 `dispatchPrecondition(condition: .onQueue(.main))` + doc comment 主线程约束；`markLaunchSuccessful()` 增加 `guard didStart` 防御

## 3. 测试与验证

- [x] 3.1 新增测试：ALLaunchGuardResetSafeModeAction 编排（成功触发 reset 退出安全模式 + 委托回调）；perform 编排层已有回归覆盖确认
- [x] 3.2 swift test 全绿（47 + 新增）；swift build 0 新增警告
- [x] 3.3 xcodebuild -scheme ALLaunchGuard iOS Simulator 构建（独立 derivedDataPath）0 错误 0 警告
- [x] 3.4 BasicExample 常规冒烟复验：正常启动 → 进入安全模式（闪退链路或 DEBUG 直入）→ 菜单页展示（含注册动作）→ 修复动作成功 + 重启提示（截图存 /tmp）

## 4. README 补齐（缺陷 ⑥）

- [x] 4.1 新增"自定义存储"小节（协议三新字段说明、no-op 默认实现向后兼容、降级后果——safeModeActive 不持久化则粘滞防护失效、自定义存储升级示例代码）
- [x] 4.2 Migration 章节修正：升级首启可能立即触发安全模式场景说明 + 必须至少注册一个 fixAction（注明空列表自动兜底重置动作）；§3 .presentOnRoot 仅回退挂载方式（页面仍为菜单式，依赖 fixHandler 者须迁移 FixAction）；§4 补 markLaunchSuccessful 不退出安全模式；§2 补旧 VC 按钮文案不可配
- [x] 4.3 How It Works 计数表补 didEnterBackground 边界说明行（进后台后回前台 5 秒内崩溃漏计一次，宁漏报不误报取舍）
