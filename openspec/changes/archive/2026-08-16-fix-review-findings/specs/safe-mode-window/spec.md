## MODIFIED Requirements

### Requirement: Scene 绑定与延迟挂载
窗口创建 SHALL 优先绑定当前 foregroundActive 的 UIWindowScene（UIWindow(windowScene:)）；无 foregroundActive scene 时 SHALL 接受任意 UIWindowScene（含 foregroundInactive/unattached——scene 激活后窗口自然可见）。启动早期 scene 尚未连接时 SHALL 在 install 调用时同步（不延迟派发）注册 scene 连接通知监听（UIScene.willConnectNotification）；应用未配置 scene manifest（经典 AppDelegate 生命周期）时 SHALL 跳过等待立即以全屏 frame 创建窗口；配置了 scene manifest 但 scene 在超时期内未连接时 SHALL 以全屏 frame 创建降级窗口作为临时兜底，且 SHALL 保留 scene 连接监听——后续 scene 连接时 SHALL 废弃未挂 scene 的降级窗口并以 UIWindow(windowScene:) 重新挂载（保证 scene 宿主中界面最终可见），重新挂载后清理监听。挂载逻辑 SHALL 幂等（重复调用不产生多个窗口）。

#### Scenario: SceneDelegate 生命周期早期触发
- **WHEN** didFinishLaunching 阶段安全模式激活（install 先于 willConnect 通知执行），随后 scene 连接（连接时为 foregroundInactive）
- **THEN** 窗口立即或在该 scene 连接后挂载并随 scene 激活可见，无重复窗口，无黑屏超时等待

#### Scenario: scene manifest 存在但 scene 延迟连接
- **WHEN** scene 宿主中 scene 连接晚于超时期，降级 frame 窗口已创建（不可见），随后 scene 连接
- **THEN** 降级窗口被废弃，安全模式页以 UIWindow(windowScene:) 重新挂载并可见，监听清理，无重复窗口

#### Scenario: 经典 AppDelegate 生命周期
- **WHEN** 应用未配置 scene manifest（经典 UIApplicationDelegate），安全模式激活
- **THEN** 窗口以屏幕 bounds 立即创建并显示，无秒级黑屏等待

## SPEC-ADDITION Notes

（无——example-apps / crash-detection / fix-actions 主 spec 不变。）
