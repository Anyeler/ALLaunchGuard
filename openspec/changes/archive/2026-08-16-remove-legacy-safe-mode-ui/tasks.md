# 任务：remove-legacy-safe-mode-ui

## 1. 删除与文档

- [x] 1.1 删除 `Sources/ALLaunchGuard/ALLaunchGuardViewController.swift`；全库 grep 确认无残留引用（源码/测试/pbxproj 均无）
- [x] 1.2 README：Migration 第 2 条改为"已移除"（removed）并给出 FixAction 迁移示例；清理"仅作回退保留/deprecated"相关表述；确认 presentOnRoot/markLaunchSuccessful 描述不受影响
- [x] 1.3 检查 ALLaunchGuard.swift 注释中指向旧页的表述并修正

## 2. 验证

- [x] 2.1 swift test 全绿（50 个）；swift build 0 新增警告
- [x] 2.2 xcodebuild -scheme ALLaunchGuard -destination 'generic/platform=iOS Simulator'（独立 derivedDataPath）0 错误 0 警告（确认删除后 UIKit 分支完整）
- [x] 2.3 openspec validate 通过
