#if canImport(UIKit)
import UIKit

/// A full-screen safe-mode page presented automatically (or manually) when
/// `ALLaunchGuard` detects consecutive crash-on-launch events.
///
/// The user must tap the **Fix** button to clear the crash counter and dismiss
/// the page.  The host app can supply a custom `fixHandler` closure to run
/// additional clean-up (e.g. clearing caches) before the guard is reset.
public final class ALLaunchGuardViewController: UIViewController {

    // MARK: - Public

    /// Called when the user taps the Fix button, **before** `ALLaunchGuard.shared.reset()`
    /// is invoked.  Use it to perform any app-specific clean-up.
    public var fixHandler: (() -> Void)?

    // MARK: - Private

    private let config: ALLaunchGuardConfig
    private weak var launchGuard: ALLaunchGuard?

    // MARK: - UI

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var contentStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .center
        sv.spacing = 20
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = config.tintColor
        let config_ = UIImage.SymbolConfiguration(pointSize: 72, weight: .regular)
        iv.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: config_)
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private lazy var titleLabel: UILabel = {
        let l = UILabel()
        l.text = config.title
        l.font = .systemFont(ofSize: 26, weight: .bold)
        l.textColor = .label
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    private lazy var messageLabel: UILabel = {
        let l = UILabel()
        l.text = config.message
        l.font = .systemFont(ofSize: 16, weight: .regular)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    private lazy var fixButton: UIButton = {
        var cfg = UIButton.Configuration.filled()
        cfg.title = config.fixButtonTitle
        cfg.baseBackgroundColor = config.tintColor
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .large
        cfg.buttonSize = .large
        cfg.image = UIImage(systemName: "wrench.and.screwdriver.fill")
        cfg.imagePadding = 8
        let b = UIButton(configuration: cfg, primaryAction: nil)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(didTapFix), for: .touchUpInside)
        return b
    }()

    // MARK: - Init

    /// Creates the safe-mode page.
    ///
    /// - Parameters:
    ///   - launchGuard: The `ALLaunchGuard` instance to reset when the user taps Fix.
    ///   - config:      Display configuration. Defaults to `ALLaunchGuardConfig.default`.
    public init(launchGuard: ALLaunchGuard = .shared, config: ALLaunchGuardConfig = .default) {
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
        setupLayout()
    }

    // MARK: - Layout

    private func setupLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(messageLabel)
        contentStack.setCustomSpacing(36, after: messageLabel)
        contentStack.addArrangedSubview(fixButton)

        let padding: CGFloat = 32

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(greaterThanOrEqualTo: scrollView.contentLayoutGuide.topAnchor,
                                              constant: padding),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.contentLayoutGuide.bottomAnchor,
                                                 constant: -padding),
            contentStack.centerYAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerYAnchor),
            contentStack.centerXAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerXAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor,
                                                constant: -padding * 2),

            scrollView.contentLayoutGuide.heightAnchor.constraint(
                greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),

            iconView.heightAnchor.constraint(equalToConstant: 88),
            iconView.widthAnchor.constraint(equalToConstant: 88),

            fixButton.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            fixButton.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    // MARK: - Actions

    @objc private func didTapFix() {
        fixHandler?()
        launchGuard?.reset()
        dismiss(animated: true)
    }
}

// MARK: - Convenience presentation

public extension ALLaunchGuard {

    /// Presents the built-in safe-mode page on the key window's root view controller
    /// if the guard is currently in safe mode.
    ///
    /// - Parameters:
    ///   - fixHandler:  Optional closure executed when the user taps Fix, before
    ///                  the crash counter is cleared.
    func presentSafeModeUIIfNeeded(fixHandler: (() -> Void)? = nil) {
        guard isInSafeMode else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let rootVC = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .compactMap({ scene -> UIViewController? in
                    if #available(iOS 15.0, *) {
                        return scene.keyWindow?.rootViewController
                    } else {
                        return scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                    }
                })
                .first else { return }

            let vc = ALLaunchGuardViewController(launchGuard: self, config: self.uiConfig)
            vc.fixHandler = fixHandler
            rootVC.present(vc, animated: true)
        }
    }
}
#endif
