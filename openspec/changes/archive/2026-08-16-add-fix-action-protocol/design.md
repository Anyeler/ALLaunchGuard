# 设计：add-fix-action-protocol

## Context

Change 1（已归档）建立了判定核心：安全模式为粘滞状态，仅 `reset()` 可退出（清计数 + 清粘滞标记 + 退出回调）。现有 UI 层仅一个 `fixHandler` 闭包 + 单按钮（属后续变更替换对象）。本变更是修复动作的非 UI 层：协议、注册、编排、内置动作，为 add-safe-mode-menu-ui 的 UITableView 菜单提供数据源与执行通道。约束：Swift 5 / iOS 14+；纯 Foundation 可测（清缓存动作用 FileManager，无需 UIKit）；不与 MPLaunch 或任何启动编排器耦合（入口级门控范式不变）。

## Goals / Non-Goals

**Goals:**
- 动作协议最小面（4 个成员）；编排语义明确（首个成功 → reset 一次；失败 → 可重试不退出）。
- 委托追加回调零破坏；`fixActions` 默认空数组。
- 内置动作仅清缓存一个（其余由宿主接入，避免过度设计）。

**Non-Goals:**
- 菜单 UI（ UITableView、spinner/打勾状态）——属 add-safe-mode-menu-ui。
- 修复完成提示重启文案——属 Config/UI 变更。
- 两级分级修复、远端配置动作下发——演进项。
- 自动串行执行全部动作（静默修复模式）——演进项。

## Decisions

### D1. 编排放 ALLaunchGuard 上而非独立协调器
`perform(_ action:completion:)` 作为 ALLaunchGuard 的方法：成功路径复用现有 `reset()`（幂等，天然满足"仅一次退出语义"），失败路径不动状态。备选（独立 FixActionCoordinator 类）被否决：单例已是状态汇聚点，多一个类只增加接线成本；UI 变更后 VC 直接调 guard 的编排方法即可。

### D2. completion(Bool) 而非 Result<Void, Error>
失败原因由宿主动作自己呈现（UI 层失败只显示可重试），库编排只关心成败——保持协议面最小，OC 互操作场景也更友好。备选 Result 被否决：当前无错误消费方。

### D3. 动作在调用线程执行，completion 任意线程回、编排内部统一派发主队列
`perform` 可能是耗时 IO（清缓存）——由宿主/内置动作自行决定后台队列；编排层在收到 completion 后统一 `DispatchQueue.main.async` 处理 reset 与委托回调（委托大概率触发 UI 更新）。测试中主队列 async 通过 XCTest expectation 处理。

### D4. 内置动作直接清 Caches 根内容
遍历 contentsOfDirectory 删除各项（含子目录），目录不存在 → 成功；单项删除失败整体失败。不做白名单/黑名单（属宿主自定义动作职责）。元数据默认中文（与现有 Config 默认中文文案一致）。

### D5. fixActions 为 `public var` 数组而非注册函数
宿主在 didFinishLaunching 首行直接赋值（与 uiConfig 同风格）；提供 `add(_:)` 便捷方法非必需——赋值即可，不增加 API 面。

## Risks / Trade-offs

- [动作执行中宿主再次触发同一动作（连点）] → UI 层（后续变更）以 cell 状态置灰防连点；编排层幂等（重复 reset 无害），本层不做并发锁。
- [fixActions 强引用宿主对象图] → 动作为 class 协议（AnyObject），生命周期与 guard 单例同长，安全模式下本就要保活；文档注明动作应轻持有依赖。
- [清缓存误删宿主关键文件] → 仅清 Caches（系统本可随时回收的目录），语义安全；不碰 Documents/Library 其他目录。

## Migration Plan

1. 实现 + swift test 全绿 → 归档。
2. 后续 add-safe-mode-menu-ui 以 fixActions 为菜单数据源；旧 `fixHandler` 路径在 UI 变更中标 deprecated（本变更不动旧 VC，保持每步可独立验证）。
3. 回滚：revert 即可，无持久化/数据迁移。

## Open Questions

（无。）
