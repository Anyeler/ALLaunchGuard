## REMOVED Requirements

### Requirement: 旧页面废弃与回退
**Reason**: 2.0 已交付新菜单式安全模式页；用户确认旧单按钮页（ALLaunchGuardViewController 及 presentSafeModeUIIfNeeded(fixHandler:)）无任何存量使用方，deprecated 过渡保留失去保护对象，直接移除以简化代码面。
**Migration**: 直接使用菜单式安全模式页（安全模式激活后由 presentationStyle 控制展示：dedicatedWindow 独立窗口接管 或 presentOnRoot 在宿主 rootVC 上 present 新页）；原 fixHandler 清理逻辑迁移为 ALLaunchGuardFixAction（推荐 ALLaunchGuardClosureAction 一行包装）并注册到 fixActions；空列表时库自动提供"重置安全模式"兜底动作。
