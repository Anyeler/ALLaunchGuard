# 设计：add-safe-mode-menu-ui

## Context

现有 ALLaunchGuardViewController（192 行，#if canImport(UIKit)）为单按钮页：fixHandler 闭包（L16）→ didTapFix（L153-157）reset + dismiss；presentSafeModeUIIfNeeded（L162-190）在 key window rootVC 上 modal present；L71-79 使用 UIButton.Configuration（iOS 15+ API，部署目标 iOS 14，从未经 iOS 编译验证）。ALLaunchGuardConfig 有 title/message/fixButtonTitle/tintColor/autoPresent 五字段 + ALColor 占位模式（L51-66，Linux 测试关键）。Change 2 已提供 fixActions + perform(_:completion:) 编排 + didFinishFixAction 委托回调。本变更只做 UI 消费层，窗口接管（独立 UIWindow）属 add-window-takeover-presentation，本变更沿用 present 路径。

## Goals / Non-Goals

**Goals:**
- 菜单式页面：动作列表 + 执行状态机（idle/running/success/failed）+ 底部重启提示，纯系统控件、iOS 14 安全 API。
- Config 字段迁移 fixButtonTitle → restartHint（唯一 BREAKING，随 2.0.0）。
- 旧 VC deprecated 保留 + 修复 iOS 15+ API 隐患（使其真正 iOS 14 安全）。

**Non-Goals:**
- 独立 UIWindow 接管 / scene 绑定策略——下一变更。
- SwiftUI 版本、暗黑模式深度定制、动态字体审计——非本次。
- 修复动作的进度百分比 UI（微信式进度条）——completion(Bool) 契约下不可表达，演进项。

## Decisions

### D1. 新 VC 独立文件而非改造旧 VC
新建 `ALLaunchGuardSafeModeViewController`，旧 VC 原样保留（仅 deprecated 标注 + 按钮修复）——回退路径零风险，diff 清晰。备选（就地改造旧 VC）被否决：破坏回退能力且 diff 混杂。

### D2. cell 状态机与交互约束
每 cell 独立状态枚举（idle/running/success/failed）：running 显示 UIActivityIndicatorView（isUserInteractionEnabled 整表关闭而非单 cell——实现"同一时间至多一个动作"最简且防误触）；success 显示 checkmark + textLabel 置灰；failed 显示 exclamationmark 红色 + 可重试。执行入口统一走 `ALLaunchGuard.perform(_:completion:)`（编排层已保证主队列回调），VC 的 completion 回调驱动 cell 状态刷新。

### D3. 布局：沿用旧页头部风格 + UITableView + 底部提示条
头部复用旧 VC 的 icon（exclamationmark.triangle.fill + tintColor）/title（26 bold）/message（16 secondary）布局（AutoLayout 约束风格一致）；中部 UITableView(plain)；底部 restartHint 常驻 UILabel（修复成功后 isHighlighted/加粗强调 + tintColor）。整页 UIStackView(vertical) 或分段约束皆可，取分段约束（与旧文件风格一致、少嵌套）。

### D4. autoPresent 分流点在 activateSafeMode()
`ALLaunchGuard.activateSafeMode()` 中 autoPresent 分支改为展示新菜单页（present 方式暂用旧扩展方法重构出的通用 present 逻辑）；保留 `presentSafeModeUIIfNeeded(fixHandler:)` 旧签名 deprecated。空 fixActions：页面仍可展示（空态文案 + 重启提示），不强制注册动作。

### D5. Config 迁移方式：直接删字段（不保留 deprecated 过渡字段）
struct 字段删除即编译期暴露所有使用点（库早期、2.0 主版本切换点，适合硬切）；init 参数 fixButtonTitle 移除、restartHint 带默认值加入。测试断言同步迁移。

### D6. iOS 14 安全 API 清单
按钮：`UIButton(type: .system)` + setImage/setTitle + layer.cornerRadius；图标：UIImage(systemName:)（iOS 13+）；spinner/tableView 常规 API；禁用 UIButton.Configuration、scene.keyWindow（iOS 15+）——keyWindow 查找沿用旧文件 L177-181 的 iOS 15/14 分支写法（`if #available(iOS 15.0, *)` 是合法的可用性检查，非违规）。

## Risks / Trade-offs

- [swift test 无法编译 UIKit 分支] → 用 Xcode MCP（BuildProject）以 iOS Simulator destination 编译整包验证 UIKit 分支；本变更是首个引入该验证的节点。
- [fixActions 在 start() 前未赋值导致空列表] → README/注释强调"didFinishLaunching 首行先赋 fixActions 再 start()"（与 uiConfig 同约定）；空态文案兜底。
- [修复成功后用户不重启、继续点其他动作] → 已成功项置灰，其他项仍可执行（reset 幂等无害），提示条保持强调。
- [旧 VC 修复引入回归] → 修复仅限按钮构造（Configuration → 系统 UIButton + 手动样式），行为与布局不变，iOS 构建验证覆盖。

## Migration Plan

1. 实现 + swift test（Config 部分）+ Xcode MCP iOS 构建通过 → 归档。
2. 下一变更（window takeover）在其之上做窗口接管，present 路径降级为回退。
3. 回滚 revert 即可。

## Open Questions

（无。）
