## Why

项目仍处于测试阶段，不需要承担 iOS 14 的兼容成本。将最低系统版本统一提升至 iOS 15.0，可移除过时的运行时可用性分支，并让所有分发与文档声明保持一致。

## What Changes

- **BREAKING** 将 Swift Package Manager 与 CocoaPods 的 iOS deployment target 从 14.0 提升至 15.0。
- **BREAKING** 库仅支持在 iOS 15.0 及以上系统中集成和运行。
- 移除安全模式菜单展示路径中仅为 iOS 14 保留的 key-window 查找回退，统一使用 iOS 15 的 `UIWindowScene.keyWindow` API。
- **BREAKING** 移除仅用于保持历史公共 API 可用的展示样式、存储协议与委托协议默认实现；宿主必须使用独立窗口展示，并完整实现存储与委托协议。
- 更新 README 和源码注释中的最低系统版本与兼容性表述。
- 不修改任何 MLaunch 相关 Example。

## Capabilities

### New Capabilities

- `platform-support`: 定义库的最低 iOS 系统支持版本及分发配置一致性要求。

### Modified Capabilities

- `safe-mode-window`: 将窗口展示相关 API 的可用性要求从 iOS 14 提升至 iOS 15，并移除低版本回退路径。
- `safe-mode-ui`: 将安全模式 UI 的最低系统版本要求提升至 iOS 15。
- `crash-detection`: 要求自定义存储完整实现全部持久化字段，移除纯计数降级路径。
- `fix-actions`: 要求安全模式委托完整实现动作完成回调，移除默认空实现。

## Impact

- 受影响的分发配置：`Package.swift`、`ALLaunchGuard.podspec`、`Examples/BasicExample` 的 Xcode deployment target。
- 受影响的 UIKit 实现：`Sources/ALLaunchGuard/ALLaunchGuard.swift`。
- 受影响的公共 API：展示样式类型和配置字段、存储协议默认实现、委托协议默认实现。
- 受影响的文档：`README.md` 及相关源码注释；不修改 MLaunch 相关 Example。
- iOS 14 用户以及依赖上述历史 API 兼容路径的宿主将无法使用本版本；Swift 语言版本和非 UIKit 平台的单元测试支持不变。
