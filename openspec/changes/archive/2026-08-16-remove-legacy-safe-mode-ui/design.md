# 设计：remove-legacy-safe-mode-ui

## Context

旧 VC 文件（ALLaunchGuardViewController.swift）仅被自身引用（grep 证实无其他源码引用点）；新菜单页 + 窗口接管已完整承担安全模式 UI 职责；presentationStyle 枚举的两条路径均不依赖旧页（presentOnRoot 走 presentSafeModeMenu 展示新页）。

## Goals / Non-Goals

**Goals:** 删除旧页文件与相关文档表述；swift test 与 iOS 构建回归；README 迁移指引准确。

**Non-Goals:** 移除 presentationStyle/markLaunchSuccessful/存储 no-op 默认实现（均非旧页兼容层）；API 重命名。

## Decisions

### D1. 整文件删除（而非清空保留）
无引用即删，避免僵尸文件。podspec glob 与 SPM 自动少收一个文件，无需改清单。

### D2. README 迁移章节语义更新
"已废弃（deprecated 保留）"改为"已移除（removed）"，迁移路径指向 FixAction + 新页；删除"仅作回退保留"表述。

### D3. 保留项确认口径
presentOnRoot 展示的是新菜单页（功能选项）；markLaunchSuccessful 为有效提前确认 API；两者不在本次删除范围，README 不改其描述。

## Risks / Trade-offs

- [隐藏引用方（用户未知）编译失败] → 用户明确确认无使用方；编译期显性失败、迁移路径文档化。
- [无其他风险] → 纯删除，无逻辑改动。

## Migration Plan

删除 → swift test（50）+ xcodebuild iOS 构建 → README 核对 → 归档 → 追加提交至 CR 分支。

## Open Questions

（无。）
