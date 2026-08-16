## MODIFIED Requirements

### Requirement: 重启提示
页面 SHALL 在底部常驻展示重启提示文案（restartHint，默认"修复完成后，请退出应用重新打开"）；任一动作修复成功后提示 SHALL 强调（如高亮/加粗），页面 MUST NOT 自动关闭且 MUST NOT 在修复流程内自动调用 exit 终止进程。修复成功后，当配置允许进程终止（`allowRestartExit`，默认 true）时，页面 SHALL 展示"重启应用"按钮（文案可配 `restartButtonTitle`，默认"重启应用"）；用户点击该按钮 SHALL 先弹系统二次确认弹窗，确认后终止进程（exit(0)）——下次冷启动恢复正常流程。配置禁止（allowRestartExit = false）时按钮 SHALL 不展示（保留纯提示行为）。

#### Scenario: 修复成功后提示
- **WHEN** 任一动作修复成功
- **THEN** 底部重启提示强调展示，页面保持可见等待用户重启应用

#### Scenario: 一键重启
- **WHEN** 修复成功后"重启应用"按钮展示，用户点击并确认弹窗
- **THEN** 进程终止，用户下次打开 App 即恢复正常启动流程

#### Scenario: 关闭重启按钮
- **WHEN** 宿主配置 allowRestartExit = false 且修复成功
- **THEN** 不展示"重启应用"按钮，仅保留文字提示（兼容旧行为）

#### Scenario: 未修复前不可重启
- **WHEN** 尚无任何动作修复成功
- **THEN** "重启应用"按钮不展示（重启会再次进入安全模式，无意义且误导）
