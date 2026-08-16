## MODIFIED Requirements

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
