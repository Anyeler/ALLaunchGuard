# ALLaunchGuard

[![Swift 5.0+](https://img.shields.io/badge/Swift-5.0%2B-orange)](https://swift.org)
[![iOS 14.0+](https://img.shields.io/badge/iOS-14.0%2B-blue)](https://developer.apple.com/ios/)
[![SPM compatible](https://img.shields.io/badge/SPM-compatible-brightgreen)](https://swift.org/package-manager/)
[![CocoaPods compatible](https://img.shields.io/badge/CocoaPods-compatible-brightgreen)](https://cocoapods.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

ALLaunchGuard is an iOS app launch safety mode module. It detects consecutive crash-on-launch events and automatically activates **safe mode** to prevent crash loops, giving users a chance to recover.

---

## Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 14.0           |
| Swift    | 5.0            |

---

## Installation

### Swift Package Manager

Add the following dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Anyeler/ALLaunchGuard.git", from: "1.0.0")
]
```

Or add it via Xcode: **File → Add Package Dependencies…** and enter the repository URL.

### CocoaPods

Add the following line to your `Podfile`:

```ruby
pod 'ALLaunchGuard', '~> 1.0'
```

Then run:

```bash
pod install
```

---

## Quick Start

### 1. Start the guard as early as possible

```swift
import ALLaunchGuard

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        ALLaunchGuard.shared.start()

        if ALLaunchGuard.shared.isInSafeMode {
            // The app has crashed on launch multiple times.
            // Show a minimal / safe-mode UI instead of the normal flow.
            showSafeModeUI()
        } else {
            showNormalUI()
        }

        return true
    }
}
```

### 2. Mark a successful launch

Call `markLaunchSuccessful()` once the app has fully initialised and the main UI is visible. This resets the crash counter.

```swift
func applicationDidBecomeActive(_ application: UIApplication) {
    ALLaunchGuard.shared.markLaunchSuccessful()
}
```

### 3. Respond to safe-mode events (optional)

Adopt `ALLaunchGuardDelegate` to receive callbacks:

```swift
ALLaunchGuard.shared.delegate = self

extension AppDelegate: ALLaunchGuardDelegate {
    func launchGuardDidEnterSafeMode(_ guard: ALLaunchGuard) {
        // Log analytics, show alert, etc.
    }

    func launchGuardDidExitSafeMode(_ guard: ALLaunchGuard) {
        // Resume normal operation
    }
}
```

### 4. Reset safe mode

Allow users to clear app state and exit safe mode:

```swift
ALLaunchGuard.shared.reset()
```

---

## Configuration

| Property         | Type  | Default | Description                                              |
|------------------|-------|---------|----------------------------------------------------------|
| `crashThreshold` | `Int` | `3`     | Consecutive crash count required to activate safe mode.  |

```swift
ALLaunchGuard.shared.crashThreshold = 5
```

---

## How It Works

1. On each launch, `start()` increments a **persistent crash counter** (backed by `UserDefaults`).
2. If the counter reaches `crashThreshold`, `isInSafeMode` is set to `true`.
3. Calling `markLaunchSuccessful()` resets the counter to `0`.
4. If the app terminates without calling `markLaunchSuccessful()` (i.e. it crashed), the counter stays incremented and the next launch counts as another potential crash.

---

## License

ALLaunchGuard is released under the MIT License. See [LICENSE](LICENSE) for details.