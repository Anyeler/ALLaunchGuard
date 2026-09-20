## Purpose

定义库所承诺的最低 iOS 运行环境，并确保各分发渠道对该支持基线作出一致声明。

## ADDED Requirements

### Requirement: iOS 15 最低支持基线
库 MUST 仅支持 iOS 15.0 及以上系统；其 Swift Package Manager 清单和 CocoaPods podspec SHALL 均声明 15.0 作为 iOS deployment target。

#### Scenario: 通过 Swift Package Manager 集成
- **WHEN** 使用者解析库的 Swift Package Manager 清单
- **THEN** 清单声明的最低 iOS 版本为 15.0

#### Scenario: 通过 CocoaPods 集成
- **WHEN** 使用者解析库的 CocoaPods podspec
- **THEN** podspec 声明的 iOS deployment target 为 15.0

#### Scenario: 构建 BasicExample
- **WHEN** 使用者构建仓库内的 BasicExample
- **THEN** 其 Xcode 项目声明的 iOS deployment target 为 15.0

### Requirement: 支持基线文档一致性
公开 README SHALL 将 iOS 15.0 标示为最低系统版本，且不得再声称库支持 iOS 14。

#### Scenario: 查阅环境要求
- **WHEN** 使用者查阅 README 的徽章或环境要求
- **THEN** 可见的最低 iOS 版本为 15.0，且没有 iOS 14 支持声明
