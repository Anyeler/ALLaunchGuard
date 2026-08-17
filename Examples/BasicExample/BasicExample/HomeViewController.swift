import UIKit
import ALLaunchGuard

/// 首页：展示"本次启动已执行的启动任务"清单与调试入口。
///
/// 注意：本 VC 仅在正常启动路径下被构建——
/// 安全模式启动时 AppDelegate 直接 return，本页不会出现。
///
/// DEBUG 限定入口（spec: example-apps MODIFIED）：
/// - 顶部"模拟连续启动闪退"开关：开启后接下来几次启动在存活窗口内
///   自动崩溃，达到闪退阈值后下次启动进入安全模式并自动结束演示
///   （默认阈值 3：前两次启动自动崩溃、第三次启动接管；一键闭环）；
/// - 底部"模拟启动闪退"按钮：单次手动崩溃（旧入口，保留）；
/// - 右上角"直接进入安全模式"：跳过闪退链路直连（旧入口，保留）。
final class HomeViewController: UITableViewController {

    // MARK: - 模拟的启动任务清单

    private let launchTasks: [(icon: String, title: String, detail: String)] = [
        ("network", "初始化网络", "URLSession 配置 / DNS 预热"),
        ("externaldrive.badge.timemachine", "加载数据库", "打开 SQLite / 执行迁移"),
        ("paintbrush", "准备主题资源", "解析主题色与图标"),
        ("house", "渲染首页", "构建根视图层级"),
    ]

    private let cellID = "LaunchTaskCell"

    /// 安全模式最小任务一次性横幅的 UserDefaults key（与 AppDelegate 步骤 2
    /// 注册的演示豁免标记一致）：展示后清零，不常驻
    private static let safeModeTaskRanKey = "BasicExample.safeModeMinimalTaskRan"

    // MARK: - 连续闪退演示开关（DEBUG 限定）

    #if DEBUG
    /// "模拟连续启动闪退"开关：状态绑定剩余自动崩溃次数（remaining > 0）
    private let autoCrashSwitch = UISwitch()
    #endif

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ALLaunchGuard · BasicExample"
        view.backgroundColor = .systemBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellID)
        tableView.rowHeight = 60

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                title: "直接进入安全模式",
                style: .plain,
                target: self,
                action: #selector(enterSafeModeTapped)
            ),
        ]

        let crashButton = UIButton(type: .system)
        crashButton.setTitle("模拟启动闪退（连续触发后进入安全模式）", for: .normal)
        crashButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        crashButton.setTitleColor(.white, for: .normal)
        crashButton.backgroundColor = .systemRed
        crashButton.layer.cornerRadius = 12
        crashButton.translatesAutoresizingMaskIntoConstraints = false
        #if DEBUG
        crashButton.addTarget(self, action: #selector(simulateCrashTapped), for: .touchUpInside)
        #else
        crashButton.isEnabled = false
        #endif

        let footer = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 120))
        footer.addSubview(crashButton)
        NSLayoutConstraint.activate([
            crashButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24),
            crashButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -24),
            crashButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            crashButton.heightAnchor.constraint(equalToConstant: 52),
        ])
        tableView.tableFooterView = footer

        // 一次性横幅：安全模式最小任务执行过的可见证据（spec: example-apps
        // MODIFIED）——修复重启回正常路径后展示一次，读后立即清零。
        let showSafeModeTaskBanner = UserDefaults.standard.bool(forKey: Self.safeModeTaskRanKey)
        if showSafeModeTaskBanner {
            UserDefaults.standard.set(false, forKey: Self.safeModeTaskRanKey)
        }

        #if DEBUG
        setupAutoCrashDemoHeader(showSafeModeTaskBanner: showSafeModeTaskBanner)
        #else
        if showSafeModeTaskBanner {
            tableView.tableHeaderView = makeHeaderContainer(withBannerOnly: true)
        }
        #endif
    }

    #if DEBUG
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 开关状态绑定剩余次数：进入安全模式时 AppDelegate 已将演示清零
        //（修复重启后 remaining == 0），回到首页时开关自动回弹为关闭
        //（spec: example-apps MODIFIED）
        autoCrashSwitch.setOn(BasicExampleCrashSimulator.shared.isArmed, animated: false)
    }
    #endif

    // MARK: - 连续闪退演示开关（DEBUG 限定，spec: example-apps MODIFIED）

    /// 首页顶部开关区：标题 + 说明文案 + UISwitch（状态绑定 remaining > 0；
    /// 开启调 arm() 置 3，关闭调 disarm() 清零）。当 showSafeModeTaskBanner
    /// 为 true 时，顶部叠加安全模式最小任务一次性横幅。
    #if DEBUG
    private func setupAutoCrashDemoHeader(showSafeModeTaskBanner: Bool) {
        let bannerHeight: CGFloat = showSafeModeTaskBanner ? 72 : 0
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 132 + bannerHeight))
        header.backgroundColor = .secondarySystemBackground

        var topAnchor = header.topAnchor
        if showSafeModeTaskBanner {
            let banner = makeSafeModeTaskBannerLabel()
            header.addSubview(banner)
            NSLayoutConstraint.activate([
                banner.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
                banner.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
                banner.trailingAnchor.constraint(
                    equalTo: header.trailingAnchor, constant: -24),
                banner.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            ])
            topAnchor = banner.bottomAnchor
        }

        let titleLabel = UILabel()
        titleLabel.text = "模拟连续启动闪退"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = UILabel()
        detailLabel.text = "开启后重启 App：接下来几次启动将在存活窗口内自动崩溃；达到闪退阈值（默认 3）后，下次启动进入安全模式并自动结束演示，可完整体验修复与一键重启。"
        detailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        autoCrashSwitch.addTarget(
            self, action: #selector(autoCrashSwitchChanged(_:)), for: .valueChanged)
        autoCrashSwitch.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(titleLabel)
        header.addSubview(detailLabel)
        header.addSubview(autoCrashSwitch)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(
                equalTo: autoCrashSwitch.leadingAnchor, constant: -12),

            autoCrashSwitch.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            autoCrashSwitch.trailingAnchor.constraint(
                equalTo: header.trailingAnchor, constant: -24),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            detailLabel.trailingAnchor.constraint(
                equalTo: header.trailingAnchor, constant: -24),
            detailLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: header.bottomAnchor, constant: -12),
        ])

        tableView.tableHeaderView = header
    }

    /// 开关切换：开启置剩余 3 次；关闭清零
    @objc private func autoCrashSwitchChanged(_ sender: UISwitch) {
        if sender.isOn {
            BasicExampleCrashSimulator.shared.arm()
        } else {
            BasicExampleCrashSimulator.shared.disarm()
        }
    }
    #endif

    // MARK: - 安全模式最小任务一次性横幅（spec: example-apps MODIFIED）

    /// 横幅样式：绿色底 + 白字居中，与首页列表勾号色调一致
    private func makeSafeModeTaskBannerLabel() -> UILabel {
        let label = UILabel()
        label.text = "上次安全模式启动：最小任务已执行（示例）"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.backgroundColor = .systemGreen
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    #if !DEBUG
    /// Release 下无连续闪退演示开关区：横幅独立占据 tableHeaderView
    private func makeHeaderContainer(withBannerOnly: Bool) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 64))
        container.backgroundColor = .secondarySystemBackground
        let banner = makeSafeModeTaskBannerLabel()
        container.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            banner.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
        return container
    }
    #endif

    // MARK: - 调试动作

    /// 模拟启动闪退：进程立即崩溃（DEBUG 限定）。
    ///
    /// 提示：需在启动后 5 秒内（survivalTimeout 默认值）点击，
    /// 否则存活确认已自动清零计数，本次死亡不会累计。
    #if DEBUG
    @objc private func simulateCrashTapped() {
        fatalError("💥 Simulated launch crash (BasicExample DEBUG button)")
    }
    #endif

    /// 直接进入安全模式（DEBUG 限定）：跳过 3 次闪退链路，立即激活安全模式。
    /// 激活后界面由安全模式窗口接管，需手动重启应用退出。
    #if DEBUG
    @objc private func enterSafeModeTapped() {
        ALLaunchGuard.shared.enterSafeModeForTesting()
        let alert = UIAlertController(
            title: "已进入安全模式",
            message: "安全模式已激活并持久化。\n请退出应用后重新打开，即可看到安全模式启动效果。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
    #endif

    // MARK: - UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        launchTasks.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath)
        let task = launchTasks[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.image = UIImage(systemName: task.icon)
        config.imageProperties.tintColor = .systemGreen
        config.text = task.title
        config.secondaryText = task.detail
        cell.contentConfiguration = config
        cell.accessoryType = .checkmark
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "本次启动已执行的启动任务（\(launchTasks.count) 项）"
    }
}
