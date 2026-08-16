#if canImport(UIKit)
import UIKit

/// 菜单式安全模式页：以 UITableView 列表展示已注册的修复动作
///（数据源为 viewDidLoad 时的 `fixActions` 快照，完整快照语义见
/// `snapshotActions` 属性注释），
/// 用户点击单项才执行修复；执行期间整表禁用交互（同一时间至多一个动作），
/// 按结果反馈状态：成功打勾置灰不可再点 / 失败红色警示且可重试。
///
/// 空动作列表兜底（design D2 / spec: safe-mode-ui MODIFIED）：快照时
/// `fixActions` 为空则自动注入内置重置动作
/// （`ALLaunchGuardResetSafeModeAction`），保证安全模式始终存在
/// 用户退出出口（覆盖宿主忘记注册与升级残留计数场景），
/// 故列表恒非空、无纯空态展示。
///
/// 页面底部常驻重启提示（`config.restartHint`），任一动作修复成功后
/// 提示强调展示（tintColor + 加粗），且当 `config.allowRestartExit == true`
/// 时同步展示“重启应用”按钮（文案 `config.restartButtonTitle`）：用户
/// 点击后经系统 Alert 二次确认才终止进程（exit(0)），下次冷启动恢复
/// 正常流程——修复流程本身 MUST NOT 自动关闭页面、MUST NOT 自动调用
/// exit（spec: safe-mode-ui MODIFIED）。
///
/// 全部使用 iOS 14 安全 API（spec: safe-mode-ui / design D2、D3、D6）。
public final class ALLaunchGuardSafeModeViewController: UIViewController {

    // MARK: - 动作项状态机（design D2）

    /// 单个修复动作的执行状态。
    private enum ActionState {
        /// 初始：可点击执行
        case idle
        /// 执行中：右侧 spinner，整表禁用交互
        case running
        /// 成功：打勾并置灰，不可再点
        case success
        /// 失败：红色警示标记，保持可点击允许重试
        case failed
    }

    // MARK: - Private

    private weak var launchGuard: ALLaunchGuard?
    private let config: ALLaunchGuardConfig

    /// 页面存续期间的唯一动作数据源：viewDidLoad 快照一次
    ///（design D4，spec: safe-mode-ui MODIFIED）——注册顺序即展示顺序，
    /// 行数 / 渲染 / 执行统一使用快照，页面展示期间宿主重新赋值
    /// fixActions 不影响已展示列表；
    /// 快照时 fixActions 为空则注入内置重置动作兜底（design D2）。
    private var snapshotActions: [ALLaunchGuardFixAction] = []

    /// 各动作项执行状态（索引与 `snapshotActions` 对齐）
    private var states: [ActionState] = []

    private let cellReuseIdentifier = "ALLaunchGuardFixActionCell"

    // MARK: - UI

    /// 头部警示图标（沿用旧页布局风格：exclamationmark.triangle.fill + tintColor）
    private lazy var iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = config.tintColor
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 72, weight: .regular)
        iv.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: symbolConfig)
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    /// 头部标题（沿用旧页：26 bold）
    private lazy var titleLabel: UILabel = {
        let l = UILabel()
        l.text = config.title
        l.font = .systemFont(ofSize: 26, weight: .bold)
        l.textColor = .label
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    /// 头部正文（沿用旧页：16 secondary）
    private lazy var messageLabel: UILabel = {
        let l = UILabel()
        l.text = config.message
        l.font = .systemFont(ofSize: 16, weight: .regular)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    /// 中部动作菜单列表（plain 样式，常规 UITableView API）
    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.dataSource = self
        tv.delegate = self
        tv.rowHeight = 52
        tv.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    /// 底部常驻重启提示；任一动作成功后强调（tintColor + bold）
    private lazy var hintLabel: UILabel = {
        let l = UILabel()
        l.text = config.restartHint
        l.font = .systemFont(ofSize: 15, weight: .regular)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    /// “重启应用”按钮（design D1）：初始隐藏，任一动作修复成功且
    /// `config.allowRestartExit == true` 时展示；点击后经系统 Alert
    /// 二次确认才 exit(0)（避免误触杀进程）。
    /// iOS 14 安全 API：系统 UIButton + layer.cornerRadius。
    private lazy var restartButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle(config.restartButtonTitle, for: .normal)
        b.setTitleColor(config.tintColor, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        b.tintColor = config.tintColor
        b.layer.cornerRadius = 10
        b.layer.borderWidth = 1
        b.layer.borderColor = config.tintColor.cgColor
        b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        // 按钮文案不可被多行提示 Label 压缩；隐藏时由 stack 自动移出布局
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.isHidden = true
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(restartButtonTapped), for: .touchUpInside)
        return b
    }()

    /// 底部水平容器（提示 Label + 重启按钮，design D1）：
    /// 隐藏的 arrangedSubview 会被 stack 自动移出布局，
    /// 提示 Label 自动占满全宽（旧行为视觉不变）。
    private lazy var bottomStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [hintLabel, restartButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Init

    /// Creates the menu-style safe-mode page.
    ///
    /// - Parameters:
    ///   - launchGuard: The `ALLaunchGuard` instance providing the fix-action
    ///                  data source and execution orchestration. Defaults to `.shared`.
    ///   - config:      Display configuration. Defaults to `ALLaunchGuardConfig.default`.
    public init(
        launchGuard: ALLaunchGuard = .shared,
        config: ALLaunchGuardConfig = .default
    ) {
        self.launchGuard = launchGuard
        self.config = config
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // 数据源快照：完整语义（一次快照 / 空时注入兜底）见 `snapshotActions`
        // 属性注释（design D2/D4，spec: safe-mode-ui MODIFIED）。
        var actions = launchGuard?.fixActions ?? []
        if actions.isEmpty {
            actions = [ALLaunchGuardResetSafeModeAction()]
        }
        snapshotActions = actions
        states = Array(repeating: .idle, count: snapshotActions.count)

        setupLayout()
    }

    // MARK: - Layout（分段约束，风格与旧页一致，design D3）

    private func setupLayout() {
        view.addSubview(iconView)
        view.addSubview(titleLabel)
        view.addSubview(messageLabel)
        view.addSubview(tableView)
        view.addSubview(bottomStackView)

        let inset: CGFloat = 24

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.heightAnchor.constraint(equalToConstant: 88),
            iconView.widthAnchor.constraint(equalToConstant: 88),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            tableView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor, constant: -16),

            bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            bottomStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            bottomStackView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - 状态反馈

    /// 任一动作修复成功后强调重启提示（tintColor + 加粗）；
    /// 配置允许时同步展示“重启应用”按钮（spec: safe-mode-ui MODIFIED：
    /// 未修复成功前或 `allowRestartExit == false` 恒不展示）。
    private func emphasizeRestartHint() {
        hintLabel.textColor = config.tintColor
        hintLabel.font = .systemFont(ofSize: 16, weight: .bold)
        if config.allowRestartExit {
            restartButton.isHidden = false
        }
    }

    // MARK: - 一键重启（design D1）

    /// 点击“重启应用”：先弹系统 Alert 二次确认（避免误触杀进程，
    /// 同时为宿主提供可替换行为的清晰锚点），确认后终止进程——
    /// iOS 无真正热重启，exit(0) 后由用户下次冷启动恢复正常流程。
    @objc private func restartButtonTapped() {
        let alert = UIAlertController(
            title: config.restartButtonTitle,
            message: "确认现在重启应用吗？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重启", style: .destructive) { _ in
            exit(0)
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource / UITableViewDelegate

extension ALLaunchGuardSafeModeViewController: UITableViewDataSource, UITableViewDelegate {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        states.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: cellReuseIdentifier, for: indexPath)
        configure(cell, at: indexPath)
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        // 状态与快照双重越界保护（完整快照语义，design D4）
        guard indexPath.row < states.count,
              indexPath.row < snapshotActions.count else { return }
        let action = snapshotActions[indexPath.row]
        // 仅 idle / failed 可触发；running 已被整表禁交互拦截，success 不可再点
        guard states[indexPath.row] == .idle || states[indexPath.row] == .failed else { return }

        states[indexPath.row] = .running
        // 执行中整表禁用交互：同一时间至多一个动作执行，且防连点
        tableView.isUserInteractionEnabled = false
        tableView.reloadRows(at: [indexPath], with: .none)

        // 执行入口统一走编排层（completion 保证主队列回调）
        launchGuard?.perform(action) { [weak self] success in
            guard let self = self else { return }
            self.states[indexPath.row] = success ? .success : .failed
            self.tableView.isUserInteractionEnabled = true
            self.tableView.reloadRows(at: [indexPath], with: .none)
            if success {
                // 成功后强调重启提示；页面保持可见，不自动 dismiss、不调 exit
                self.emphasizeRestartHint()
            }
        }
    }

    // MARK: - Cell 配置（四态：idle / running / success / failed）

    private func configure(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard indexPath.row < states.count,
              indexPath.row < snapshotActions.count else { return }
        let action = snapshotActions[indexPath.row]
        let state = states[indexPath.row]

        // 图标：未提供时用默认图标
        let iconName = action.iconSystemName ?? "wrench.and.screwdriver"
        cell.imageView?.image = UIImage(systemName: iconName)
        cell.textLabel?.text = action.title

        // 先复位为默认样式（cell 复用）；破坏性动作以红色警示样式区分
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default
        cell.textLabel?.textColor = action.isDestructive ? .systemRed : .label
        cell.imageView?.tintColor = action.isDestructive ? .systemRed : config.tintColor

        switch state {
        case .idle:
            break
        case .running:
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.accessoryView = spinner
        case .success:
            // 打勾 + 整体置灰，不可再点
            cell.textLabel?.textColor = .secondaryLabel
            cell.imageView?.tintColor = .secondaryLabel
            cell.selectionStyle = .none
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            let check = UIImageView(
                image: UIImage(systemName: "checkmark", withConfiguration: symbolConfig))
            check.tintColor = .systemGreen
            check.contentMode = .scaleAspectFit
            cell.accessoryView = check
        case .failed:
            // 红色警示标记，保持可点击允许重试
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            let warn = UIImageView(
                image: UIImage(systemName: "exclamationmark.circle.fill",
                               withConfiguration: symbolConfig))
            warn.tintColor = .systemRed
            warn.contentMode = .scaleAspectFit
            cell.accessoryView = warn
        }
    }
}
#endif
