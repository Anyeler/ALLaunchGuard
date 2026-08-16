## Purpose

定义安全模式菜单式修复页的 UI 行为契约：以可扩展动作列表（fixActions 数据源）呈现修复能力，用户点击单项才执行并得到明确的执行状态反馈，修复完成后获得重启提示；页面配置化（文案/颜色/提示语）且兼容 iOS 14。

## ADDED Requirements

### Requirement: 动作菜单列表展示
安全模式页 SHALL 以列表（UITableView）展示已注册的修复动作：每项含图标（SF Symbol，未提供时用默认图标）、标题；破坏性动作（isDestructive）SHALL 以警示样式（红色系）区分。列表数据源 SHALL 为 ALLaunchGuard.fixActions（注册顺序即展示顺序）；fixActions 为空时 SHALL 展示空态提示（无可用的修复项）。

#### Scenario: 展示已注册动作
- **WHEN** 宿主注册 3 个动作（其一标记破坏性）并进入安全模式页面
- **THEN** 列表按注册顺序展示 3 项，破坏性项呈红色警示样式，未提供图标的项使用默认图标

#### Scenario: 空动作列表
- **WHEN** fixActions 为空进入安全模式页面
- **THEN** 页面展示空态提示而非空白列表

### Requirement: 点击执行与状态反馈
用户点击动作项时 SHALL 立即进入执行态（spinner，防重复点击），调用库编排执行该动作；执行完成 SHALL 按结果反馈：成功 → 该项打勾（checkmark）并置灰不可再点；失败 → 该项呈失败标记且保持可点击（允许重试）。执行期间其他项 MUST NOT 被触发（串行，同一时间至多一个动作在执行）。

#### Scenario: 执行成功
- **WHEN** 用户点击动作 A，其 completion(true)
- **THEN** 该项显示成功打勾并置灰，其他项保持可点击

#### Scenario: 执行失败可重试
- **WHEN** 用户点击动作 B，其 completion(false)
- **THEN** 该项显示失败标记，用户可再次点击重试

#### Scenario: 执行中防连点
- **WHEN** 动作 A 执行中用户再次点击 A 或其他项
- **THEN** 不产生新的执行调用

### Requirement: 重启提示
页面 SHALL 在底部常驻展示重启提示文案（restartHint，默认"修复完成后，请退出应用重新打开"）；任一动作修复成功后提示 SHALL 强调（如高亮/加粗），页面 MUST NOT 自动关闭且 MUST NOT 调用 exit 终止进程。

#### Scenario: 修复成功后提示
- **WHEN** 任一动作修复成功
- **THEN** 底部重启提示强调展示，页面保持可见等待用户手动重启应用

### Requirement: 页面配置
安全模式页文案与样式 SHALL 由配置对象提供：标题、正文、主题色沿用既有字段；修复按钮文案字段（fixButtonTitle）SHALL 移除并替换为重启提示文案（restartHint），构造参数带默认值。

#### Scenario: 自定义提示文案
- **WHEN** 宿主设置 restartHint 为自定义文案
- **THEN** 页面底部展示该自定义文案

### Requirement: 旧页面废弃与回退
既有单按钮安全模式页 SHALL 标记废弃（编译期 deprecated 提示）但完整保留可用；新安全模式页 SHALL 成为自动展示（autoPresent）的默认页面。旧页面 MUST NOT 再使用 iOS 15+ 专属 API（与 iOS 14 部署目标一致）。

#### Scenario: 默认展示新页面
- **WHEN** 安全模式激活且 autoPresent 为 true
- **THEN** 自动展示菜单式新页面（而非废弃的单按钮页面）

#### Scenario: 旧页面仍可编译
- **WHEN** 宿主代码直接使用废弃的单按钮页面
- **THEN** 产生废弃编译警告但正常编译运行，页面在 iOS 14 设备上不因 API 版本崩溃

### Requirement: iOS 14 兼容
新页面全部 UI 代码 MUST 仅使用 iOS 14 可用 API（如 UIButton(type:)、UITableView 常规 API），并 SHALL 通过 iOS destination 编译验证。

#### Scenario: iOS 14 编译
- **WHEN** 以 iOS 14 deployment target 编译库的 UIKit 分支
- **THEN** 编译通过，无 availability 错误
