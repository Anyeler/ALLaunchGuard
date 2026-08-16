# AGENTS.md

本文件是 ALLaunchGuard 仓库的 AI 协作规范单一来源（CLAUDE.md 通过 `@AGENTS.md` 引用，请勿在 CLAUDE.md 中重复维护）。

## 项目概述

ALLaunchGuard 是一个 iOS 启动安全模式库（Swift 5.0+ / iOS 14.0+）：通过持久化的连续启动崩溃计数（默认阈值 3）检测崩溃循环，达到阈值后进入安全模式并弹出可选的内置修复页面，帮助用户恢复应用。

- 源码：`Sources/ALLaunchGuard/`（单 target，无第三方运行时依赖）
- 测试：`Tests/ALLaunchGuardTests/`
- 双分发：`Package.swift`（SPM）与 `ALLaunchGuard.podspec`（CocoaPods）指向同一份源码
- 架构要点：`ALLaunchGuard` 单例为核心；`ALLaunchGuardStorage` 协议解耦持久化（默认 UserDefaults）；UIKit 代码用 `#if canImport(UIKit)` 条件编译隔离，保证库可在非 Apple 平台跑单元测试

## 常用命令

```bash
swift build          # 构建库 target
swift test           # 运行全部单元测试（基于 xctest，可在 macOS/Linux 执行）
```

- 无 Example App / xcodeproj；涉及 UI 行为验证时优先编写可在 `swift test` 下运行的单元测试（利用存储协议注入内存实现）。
- 发布流程涉及 podspec 版本与 Git tag，未经用户明确要求不要执行 `pod trunk push` / `git tag` / push。

## 研发流程（重要）

### 主流程：OpenSpec（所有变更默认走此流程）

任何功能性变更（新功能、行为修改、缺陷修复）都必须通过 `openspec/` 目录下的 OpenSpec 流程管理，不允许直接改代码：

1. **探索（可选）**：需求不清晰时先用 explore 流程澄清。
2. **提案**：使用 openspec-propose 流程创建变更，产出 `proposal.md`、`specs/<capability>/spec.md`（增量 spec）、`design.md`、`tasks.md`。注意：propose 阶段只产出规划产物，不改代码。
3. **实施**：由用户明确发起 openspec-apply-change，按 `tasks.md` 逐项实现并勾选进度。
4. **归档**：实现完成且测试通过后，用 openspec-archive-change 将增量 spec 合并回主 spec 并归档变更。

约定：

- 变更目录位于 `openspec/changes/`，主 spec 位于 `openspec/specs/`，schema 为 `spec-driven`（见 `openspec/config.yaml`）。
- 每个变更保持小而聚焦；实施完成后必须归档，避免长期悬挂的 changes。
- 修改公共 API 时，同步检查 README.md 中的用法文档是否需要更新。

### 辅助流程：Superpowers（可选增强）

若当前环境安装了 superpowers 插件，可在 OpenSpec 各阶段配合使用对应技能提升质量；**未安装时跳过即可，主流程不受影响**：

- propose/设计阶段 → `brainstorming`
- apply 实施阶段 → `test-driven-development`（先写失败测试再实现）
- 排查缺陷时 → `systematic-debugging`
- 声明完成前 → `verification-before-completion`（必须实际运行命令验证，不得凭推断宣称通过）

### 工具使用

- **Xcode MCP**：`.mcp.json` 已配置 `xcode` MCP server（`xcrun mcpbridge`）。当会话中该 MCP 可用时，涉及构建、测试、模拟器运行等操作应优先自动使用 Xcode MCP 工具（而非手写长 xcodebuild 命令）；MCP 不可用时回退到 `swift build` / `swift test`。
- 涉及 Xcode 工程操作（构建诊断、模拟器、UI 验证）而命令行难以覆盖时，主动检查 Xcode MCP 是否可用并使用。

## 代码规范

- 语言版本 Swift 5，避免使用更高版本特性；新公共 API 需考虑 OC 互操作场景下的可用性说明。
- 保持 UIKit 依赖隔离：非 UI 代码不得直接 import UIKit；平台相关类型沿用现有 `#if canImport(UIKit)` / `ALColor` 模式。
- 公共 API 变化保持向后兼容或走 OpenSpec 变更明确说明破坏性。
- 注释与文档使用中文，代码标识符使用英文；提交信息遵循 Conventional Commits。
- 测试中使用内存版 `ALLaunchGuardStorage` 注入，不依赖 UserDefaults 真实持久化。
