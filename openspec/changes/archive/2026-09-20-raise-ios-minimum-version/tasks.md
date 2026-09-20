## 1. 发布配置与文档

- [x] 1.1 将 Package.swift 的 iOS 平台基线更新为 15.0。
- [x] 1.2 将 ALLaunchGuard.podspec 的 deployment target 与支持说明更新为 15.0。
- [x] 1.3 将 README 的 iOS 徽章、环境要求及 iOS 14 相关兼容说明更新为 iOS 15 基线。
- [x] 1.4 更新 README 的展示与扩展协议文档，移除已删除公共 API 的用法，并明确 MLaunch 相关 Example 不在本次范围。
- [x] 1.5 将 BasicExample 的 Xcode deployment target 更新为 15.0，且不添加或修改 MLaunch 相关 Example。

## 2. UIKit 兼容层清理

- [x] 2.1 移除菜单展示路径中 iOS 14 的 key-window 回退和运行时可用性检查，直接使用 iOS 15 scene key window API。
- [x] 2.2 移除 `.presentOnRoot` 展示样式、展示路由和菜单 present 入口，仅保留独立窗口展示。
- [x] 2.3 移除存储协议和委托协议的历史默认实现，并使库内测试替身完整遵守协议。
- [x] 2.4 更新受影响的源码注释，使其不再声明 iOS 14 或历史 API 兼容性。

## 3. 验证

- [x] 3.1 全文检查发布配置、源码和 README，确认不再有 iOS 14 支持声明、目标历史 API 或运行时兼容分支，并确认未修改 MLaunch 相关 Example。
- [x] 3.2 运行 Swift Package 构建与全部单元测试，确认 iOS 15 基线迁移不影响现有行为。
