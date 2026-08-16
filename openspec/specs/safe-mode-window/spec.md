# safe-mode-window Specification

## Purpose

定义安全模式界面接管能力：当检测到启动崩溃循环进入安全模式且宿主跳过正常启动流程时，库以独立 UIWindow 接管显示安全模式菜单页，覆盖或替代任何既有界面，并具备 scene 就绪等待与旧展示路径回退，确保用户始终能看到修复入口。

## Requirements
### Requirement: 独立窗口接管显示
安全模式激活且展示样式为专用窗口（默认）时，系统 SHALL 创建独立 UIWindow（windowLevel 高于常规窗口），以菜单式安全模式页为 rootViewController 并设为 key window 可见——不依赖宿主是否构建了自己的 window/root VC。

#### Scenario: 宿主跳过自身界面构建
- **WHEN** 宿主在启动入口返回 true 跳过全部启动任务（未创建任何 window/root VC），安全模式以窗口方式展示
- **THEN** 独立 UIWindow 成为 key window，菜单式安全模式页为唯一可见界面

#### Scenario: 宿主漏分流时覆盖兜底
- **WHEN** 宿主未按约定分流、正常构建了 root 页面，安全模式窗口展示
- **THEN** 安全模式窗口因更高 windowLevel 覆盖宿主界面之上

### Requirement: Scene 绑定与延迟挂载
窗口创建 SHALL 优先绑定当前 foregroundActive 的 UIWindowScene（UIWindow(windowScene:)）；无 foregroundActive scene 时 SHALL 接受任意 UIWindowScene（含 foregroundInactive/unattached——scene 激活后窗口自然可见）。启动早期 scene 尚未连接时 SHALL 在 install 调用时同步（不延迟派发）注册 scene 连接通知监听（UIScene.willConnectNotification）；应用未配置 scene manifest（经典 AppDelegate 生命周期）时 SHALL 跳过等待立即以全屏 frame 创建窗口；配置了 scene manifest 但 scene 在超时期内未连接时 SHALL 以全屏 frame 创建降级窗口作为临时兜底，且 SHALL 保留 scene 连接监听——后续 scene 连接时 SHALL 废弃未挂 scene 的降级窗口并以 UIWindow(windowScene:) 重新挂载。**scene 连接监听 SHALL 在协调器存续期间持续保持**（不因正式挂载成功而移除，仅协调器释放时清理）：当系统断连已挂载的 scene（window 层级被系统释放）后 scene 再次连接时，SHALL 以新 scene 重建窗口并迁移安全模式页，保证安全模式界面自愈。挂载逻辑 SHALL 幂等（重复调用、重复连接通知不产生多个窗口）。

#### Scenario: SceneDelegate 生命周期早期触发
- **WHEN** didFinishLaunching 阶段安全模式激活（install 先于 willConnect 通知执行），随后 scene 连接（连接时为 foregroundInactive）
- **THEN** 窗口立即或在该 scene 连接后挂载并随 scene 激活可见，无重复窗口，无黑屏超时等待

#### Scenario: scene manifest 存在但 scene 延迟连接
- **WHEN** scene 宿主中 scene 连接晚于超时期，降级 frame 窗口已创建（不可见），随后 scene 连接
- **THEN** 降级窗口被废弃，安全模式页以 UIWindow(windowScene:) 重新挂载并可见，无重复窗口

#### Scenario: 已挂载 scene 被系统断连后重连
- **WHEN** 安全模式窗口已正式挂载，用户切到后台较久导致 scene 被系统断连（window 层级释放），随后 scene 重连（willConnect 再次发出）
- **THEN** 协调器以新 scene 重建窗口并迁移安全模式页（监听因持续保持而收到通知），界面自愈，不产生重复窗口

#### Scenario: 经典 AppDelegate 生命周期
- **WHEN** 应用未配置 scene manifest（经典 UIApplicationDelegate），安全模式激活
- **THEN** 窗口以屏幕 bounds 立即创建并显示，无秒级黑屏等待

### Requirement: 展示样式配置
配置对象 SHALL 提供展示样式枚举：专用窗口（默认）或在宿主 root 上 present（旧行为）；安全模式激活的自动展示 SHALL 按该配置分流；present 回退路径 SHALL 保留可用。

#### Scenario: 配置回退旧样式
- **WHEN** 宿主配置 presentationStyle 为 .presentOnRoot 且安全模式激活（autoPresent 为 true）
- **THEN** 采用在宿主 key window rootVC 上 present 的旧路径（兼容行为）

### Requirement: 显式接管入口与窗口生命周期
系统 SHALL 提供显式接管方法（如宿主在 return 前手动调用）；窗口 SHALL 被强持有防释放；安全模式激活期间窗口 MUST NOT 自动关闭（等待用户执行修复并手动重启应用）；修复动作执行不依赖窗口状态。

#### Scenario: 手动接管
- **WHEN** 宿主在 didFinishLaunching 中调用显式接管方法
- **THEN** 安全模式窗口展示（与自动展示幂等，不重复创建）

#### Scenario: 窗口持续可见
- **WHEN** 安全模式页停留期间（无论是否已有动作修复成功）
- **THEN** 窗口保持可见直到进程结束（用户重启），不自动 dismiss

### Requirement: iOS 14 兼容
窗口与 scene 相关代码 MUST 仅使用 iOS 14 可用 API（UIScene.willConnectNotification、UIWindowScene 常规 API），SHALL 通过 iOS destination 编译验证。

#### Scenario: iOS 14 编译
- **WHEN** 以 iOS 14 deployment target 编译 UIKit 分支
- **THEN** 编译通过，无 availability 错误
