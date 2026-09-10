#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint duo_animation.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'duo_animation'
  s.version          = '0.0.1'
  s.summary          = 'A tilt-driven frosted-glass fold effect for Flutter widgets.'
  s.description      = <<-DESC
A tilt-driven frosted-glass fold effect for Flutter widgets.
                       DESC
  s.homepage         = 'https://github.com/narayann7/duo_animation'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'narayann7' => 'narayan.reddy@eatwithnymble.com' }
  s.source           = { :path => '.' }
  s.source_files = 'duo_animation/Sources/duo_animation/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'duo_animation_privacy' => ['duo_animation/Sources/duo_animation/PrivacyInfo.xcprivacy']}
end
