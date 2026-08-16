# 任务：add-safe-mode-menu-ui

## 1. 配置迁移（TDD：先改测试再改实现）

- [x] 1.1 更新 Tests 中 Config 相关断言：testConfigDefaultValues / testConfigCustomValues 的 fixButtonTitle 断言迁移为 restartHint（默认值非空断言 + 自定义值断言）
- [x] 1.2 修改 `Sources/ALLaunchGuard/ALLaunchGuardConfig.swift`：移除 fixButtonTitle 字段与 init 参数，新增 `restartHint: String`（默认"修复完成后，请退出应用重新打开"）与 init 参数；其余字段与 ALColor 模式不动
- [x] 1.3 运行 swift test 确认 Config 迁移全绿（UIKit 文件在 macOS 测试下不编译，旧 VC 的 fixButtonTitle 引用需同步处理——若旧 VC 引用了该字段则一并替换为 restartHint 或删除引用）

## 2. 菜单式安全模式页（新文件）

- [x] 2.1 新建 `Sources/ALLaunchGuard/ALLaunchGuardSafeModeViewController.swift`（#if canImport(UIKit)）：头部 icon/title/message（沿用旧页布局风格与约束写法）+ UITableView 菜单 + 底部 restartHint 常驻 UILabel；数据源 ALLaunchGuard.shared.fixActions（init 可注入 launchGuard 以便测试），空列表空态文案；cell 含图标（iconSystemName，nil 用默认 "wrench.and.screwdriver"）/标题/isDestructive 红色样式/右侧状态视图（idle 无 / running spinner / success checkmark+置灰 / failed 红色感叹+可重试）
- [x] 2.2 交互逻辑：didSelectRow → 全表 isUserInteractionEnabled=false（执行中）→ 调 launchGuard.perform(action)（completion 主队列回调）→ 刷新 cell 状态 + 恢复交互（failed 时该项可再点）；任一成功 → restartHint 强调样式（tintColor + bold）；页面不自动 dismiss、不调 exit
- [x] 2.3 全部使用 iOS 14 安全 API：UIButton(type:.system)、UIImage(systemName:)、UIActivityIndicatorView、UITableView 常规 API；严禁 UIButton.Configuration

## 3. 展示分流与旧页废弃

- [x] 3.1 修改 `Sources/ALLaunchGuard/ALLaunchGuard.swift` activateSafeMode() 的 autoPresent 分支：默认展示新菜单页（present 方式）；新增便捷方法 `public func presentSafeModeMenu()`（keyWindow rootVC present，iOS 15/14 keyWindow 兼容写法沿用旧文件 L177-181 模式）
- [x] 3.2 修改 `Sources/ALLaunchGuard/ALLaunchGuardViewController.swift`：类与 presentSafeModeUIIfNeeded 标 `@available(iOS, deprecated: 2.0, message: "Use ALLaunchGuardSafeModeViewController")`；L70-83 的 UIButton.Configuration 替换为 iOS 14 安全构造（UIButton(type:.system) + title/tint/cornerRadius），行为布局不变
- [x] 3.3 swift test 全绿（43 存量 + Config 迁移调整）；确认无公共 API 意外删除（旧 VC/旧方法 deprecated 保留）

## 4. iOS 编译验证（UIKit 分支）

- [x] 4.1 使用 Xcode MCP BuildProject 或 xcodebuild 以 iOS Simulator destination（deployment target iOS 14）编译库 target，确认 UIKit 分支 0 错误 0 警告（含旧 VC 修复后的按钮代码与新 VC 全部代码）；如 Xcode MCP 不可用，回退 `xcodebuild build -scheme ALLaunchGuard -destination 'generic/platform=iOS Simulator'`（在临时生成或现有 scheme 下，如实报告所选方式）
