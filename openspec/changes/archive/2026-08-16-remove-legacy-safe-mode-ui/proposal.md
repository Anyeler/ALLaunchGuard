# 提案：remove-legacy-safe-mode-ui

## Why

2.0 已将旧单按钮安全模式页标 deprecated 完整保留作兼容回退。用户确认旧版本无存量使用方，兼容层无保护对象，直接移除以简化代码面（SemVer 上 2.0 本就是主版本切换点，无需再留过渡期）。

## What Changes

- **删除** `Sources/ALLaunchGuard/ALLaunchGuardViewController.swift` 整个文件（含 `fixHandler`、`didTapFix`、`presentSafeModeUIIfNeeded(fixHandler:)` 扩展——全文件唯一引用点为自身，无其他源码引用）。
- README Migration 章节第 2 条改写：旧页面与 `presentSafeModeUIIfNeeded(fixHandler:)` 已在 2.0 **移除**（不再是 deprecated 保留），依赖者直接迁移 FixAction + 新菜单页；全文清理对旧页的"回退保留"表述。
- **保留不动**：`presentationStyle = .presentOnRoot`（现实现为在宿主 rootVC 上 present 新菜单页，是正当的展示方式选项而非旧页兼容）、`markLaunchSuccessful()`（有效 API 而非兼容层）、存储协议 no-op 默认实现（协议演进机制）、`start()` 返回值。
- 顺带清理：ALLaunchGuard.swift 中如存在指向旧页的注释表述则同步修正。

## Capabilities

### New Capabilities

（无。）

### Modified Capabilities

- `safe-mode-ui`：移除"旧页面废弃与回退"需求（REMOVED——旧页及其展示扩展已从代码库删除，不再存在废弃保留物）。

## Impact

- 删除 1 个源文件（约 200 行）；README 迁移章节更新；测试无影响（旧 VC 在 macOS swift test 下本就不编译，无测试引用）。
- 破坏性：仅影响直接引用旧页类型的代码（用户确认不存在）。
