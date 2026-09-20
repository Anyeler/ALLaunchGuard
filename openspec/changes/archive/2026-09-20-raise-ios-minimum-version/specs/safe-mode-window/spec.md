## MODIFIED Requirements

### Requirement: 展示样式配置
安全模式激活且自动展示开启时，系统 SHALL 始终以独立 UIWindow 接管安全模式界面。配置对象不得提供在宿主 root 上 present 的展示样式，库不得保留该展示路径。

#### Scenario: 自动展示安全模式
- **WHEN** 安全模式激活且 autoPresent 为 true
- **THEN** 系统创建独立 UIWindow 接管界面，不依赖宿主是否已经构建 root view controller

#### Scenario: 配置回退旧样式
- **WHEN** 宿主尝试配置已移除的 present-on-root 展示样式
- **THEN** 该展示样式不再是库的公开 API，宿主必须迁移至独立 UIWindow 接管

## REMOVED Requirements

### Requirement: iOS 14 兼容
**Reason**: 库的最低支持版本已提升至 iOS 15，iOS 14 不再是受支持平台。
**Migration**: 使用 iOS 15.0 或更高版本集成库。

## ADDED Requirements

### Requirement: iOS 15 窗口 API 基线
窗口与 scene 相关代码 MUST 以 iOS 15 作为最低可用版本，并 SHALL 通过 iOS 15 deployment target 编译验证。独立窗口展示路径不得保留用于 iOS 14 的运行时 API 可用性分支。

#### Scenario: iOS 15 deployment target 编译
- **WHEN** 以 iOS 15 deployment target 编译 UIKit 分支
- **THEN** 编译通过，且不存在用于 iOS 14 的运行时 API 可用性分支
