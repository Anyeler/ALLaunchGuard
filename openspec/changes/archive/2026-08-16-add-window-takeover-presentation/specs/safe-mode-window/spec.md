## Purpose

定义安全模式界面接管能力：当检测到启动崩溃循环进入安全模式且宿主跳过正常启动流程时，库以独立 UIWindow 接管显示安全模式菜单页，覆盖或替代任何既有界面，并具备 scene 就绪等待与旧展示路径回退，确保用户始终能看到修复入口。

## ADDED Requirements

### Requirement: 独立窗口接管显示
安全模式激活且展示样式为专用窗口（默认）时，系统 SHALL 创建独立 UIWindow（windowLevel 高于常规窗口），以菜单式安全模式页为 rootViewController 并设为 key window 可见——不依赖宿主是否构建了自己的 window/root VC。

#### Scenario: 宿主跳过自身界面构建
- **WHEN** 宿主在启动入口返回 true 跳过全部启动任务（未创建任何 window/root VC），安全模式以窗口方式展示
- **THEN** 独立 UIWindow 成为 key window，菜单式安全模式页为唯一可见界面

#### Scenario: 宿主漏分流时覆盖兜底
- **WHEN** 宿主未按约定分流、正常构建了 root 页面，安全模式窗口展示
- **THEN** 安全模式窗口因更高 windowLevel 覆盖宿主界面之上

### Requirement: Scene 绑定与延迟挂载
窗口创建 SHALL 优先绑定当前 foregroundActive 的 UIWindowScene（UIWindow(windowScene:)）；启动早期 scene 尚未连接时 SHALL 监听 scene 连接通知（UIScene.willConnectNotification），在首个可用 scene 就绪后完成挂载；无法获取任何 scene（经典 AppDelegate 生命周期）时 SHALL 以全屏 frame 创建窗口。挂载逻辑 SHALL 幂等（重复调用不产生多个窗口）。

#### Scenario: SceneDelegate 生命周期早期触发
- **WHEN** didFinishLaunching 阶段 scene 尚未连接，安全模式激活
- **THEN** 窗口在 scene 连接通知回调后自动挂载并可见，无重复窗口

#### Scenario: 经典 AppDelegate 生命周期
- **WHEN** 应用无 scene 配置（经典 UIApplicationDelegate），安全模式激活
- **THEN** 窗口以屏幕 bounds 创建并显示

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
