# 设计：fix-pr-review-comments

## Context

PR #2 Copilot 评审意见 2 条：install() 的 Release 致命断言（与 D1 决策原则不一致的漏网点）；Example rootViewController 未包导航控制器（navigationItem 调试入口不可达）。

## Goals / Non-Goals

**Goals:** 两处一行级修复 + 回归验证 + 冒烟证据；归档后追加提交并回复评审意见。

**Non-Goals:** install 增加运行时主队列自动派发（其调用方 activateSafeModeWindow 已负责派发，加锁/派发属过度设计）；Example UI 重构。

## Decisions

### D1. install 断言降级为 assert（与 start()/reset() 同策略）
Debug 暴露误用、Release 容忍；注释同步说明"公共入口已保证主线程，此断言防御未来新增调用点"。备选（保留 precondition）被否决：与库使命矛盾（Release 崩溃面），且评审已两次指出同类问题。

### D2. Example 包 UINavigationController
最小改动：`UINavigationController(rootViewController: HomeViewController())` 作为 root。导航栏标题与右上角 DEBUG 入口恢复。

## Risks / Trade-offs

- [assert 在 Release 容忍后台线程调用 install 的数据竞争] → 与 start() 同口径：Debug 断言 + 文档约束，现有调用链保证主线程。
- [导航栏遮挡首页内容布局] → HomeViewController 布局用 safeAreaLayoutGuide（需核对），冒烟截图验证。

## Migration Plan

修复 → 验证 → 归档 → 追加提交（scan gate 后推送）→ 回复 PR 评审意见。

## Open Questions

（无。）
