## MODIFIED Requirements

### Requirement: 动作菜单列表展示
安全模式页 SHALL 以列表（UITableView）展示修复动作：每项含图标（SF Symbol，未提供时用默认图标）、标题；破坏性动作（isDestructive）SHALL 以警示样式（红色系）区分。列表数据源 SHALL 为 ALLaunchGuard.fixActions 的页面加载时快照（注册顺序即展示顺序，页面存续期间数据源变更不影响已展示列表）；fixActions 为空时 SHALL 自动提供内置退出动作（标题如"重置安全模式"，执行安全模式重置，破坏性警示样式），保证安全模式始终存在用户出口。

#### Scenario: 展示已注册动作
- **WHEN** 宿主注册 3 个动作（其一标记破坏性）并进入安全模式页面
- **THEN** 列表按注册顺序展示 3 项，破坏性项呈红色警示样式，未提供图标的项使用默认图标

#### Scenario: 空动作列表
- **WHEN** fixActions 为空进入安全模式页面（如宿主未注册动作或升级残留计数首启触发）
- **THEN** 列表自动展示内置"重置安全模式"动作，用户点击并执行成功后安全模式退出（reset），不再是无出口的纯空态

#### Scenario: 页面存续期间数据源变更
- **WHEN** 页面展示期间宿主重新赋值 fixActions
- **THEN** 已展示列表与可执行动作保持页面加载时快照一致，无行数与内容错位
