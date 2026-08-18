Pod::Spec.new do |s|
  s.name             = 'ALLaunchGuard'
  s.version          = '2.2.0-beta.1'
  s.summary          = 'iOS APP launch safety mode module.'
  s.description      = <<-DESC
    ALLaunchGuard monitors consecutive crash-on-launch events and automatically
    activates a safe mode to prevent crash loops. It takes over the screen with
    a dedicated window and a menu-style fix-action list to help users recover.
    Supports iOS 14.0+. This beta builds the library in Swift 6 language mode
    (requires Xcode 16+ toolchain); the main line keeps serving Swift 5.
  DESC

  s.homepage         = 'https://github.com/Anyeler/ALLaunchGuard'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Anyeler' => 'anyeler@example.com' }
  s.source           = { :git => 'https://github.com/Anyeler/ALLaunchGuard.git', :tag => s.version.to_s }

  s.ios.deployment_target = '14.0'
  s.swift_versions        = ['6.0']

  s.source_files = 'Sources/ALLaunchGuard/**/*.swift'
end
