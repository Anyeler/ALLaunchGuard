Pod::Spec.new do |s|
  s.name             = 'ALLaunchGuard'
  s.version          = '2.0.0'
  s.summary          = 'iOS APP launch safety mode module.'
  s.description      = <<-DESC
    ALLaunchGuard monitors consecutive crash-on-launch events and automatically
    activates a safe mode to prevent crash loops. It takes over the screen with
    a dedicated window and a menu-style fix-action list to help users recover.
    Supports iOS 14.0+ and Swift 5.0+.
  DESC

  s.homepage         = 'https://github.com/Anyeler/ALLaunchGuard'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Anyeler' => 'anyeler@example.com' }
  s.source           = { :git => 'https://github.com/Anyeler/ALLaunchGuard.git', :tag => s.version.to_s }

  s.ios.deployment_target = '14.0'
  s.swift_versions        = ['5.0']

  s.source_files = 'Sources/ALLaunchGuard/**/*.swift'
end
