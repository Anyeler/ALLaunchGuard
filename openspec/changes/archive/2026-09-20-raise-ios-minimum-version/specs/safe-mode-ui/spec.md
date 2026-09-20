## REMOVED Requirements

### Requirement: iOS 14 兼容
**Reason**: 库的最低支持版本已提升至 iOS 15，安全模式 UI 不再支持 iOS 14。
**Migration**: 使用 iOS 15.0 或更高版本集成库。

## ADDED Requirements

### Requirement: iOS 15 UI 基线
安全模式页面的 UIKit 代码 MUST 以 iOS 15 为最低可用版本，并 SHALL 通过 iOS 15 deployment target 编译验证。

#### Scenario: iOS 15 编译
- **WHEN** 以 iOS 15 deployment target 编译库的 UIKit 分支
- **THEN** 编译通过，无 availability 错误
