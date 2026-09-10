#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint duo_animation.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'duo_animation'
  s.version          = '0.1.0'
  s.summary          = 'A tilt-driven frosted-glass fold effect for Flutter widgets.'
  s.description      = <<-DESC
A tilt-driven frosted-glass fold effect for Flutter widgets.
                       DESC
  s.homepage         = 'https://github.com/narayann7/duo_animation'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'narayann7' => 'narayan.reddy@eatwithnymble.com' }
  s.source           = { :path => '.' }
  # Narrowed to Swift so the glob does not also pick up PrivacyInfo.xcprivacy,
  # which ships through s.resource_bundles below. Matching it twice makes
  # CocoaPods treat a plist as a compilable source.
  s.source_files = 'duo_animation/Sources/duo_animation/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # Core Motion is not a required-reason API and the plugin collects nothing, so
  # the manifest is a set of empty arrays. It ships anyway: an absent manifest
  # and one that declares nothing read the same to a human and differently to
  # App Store review.
  s.resource_bundles = {'duo_animation_privacy' => ['duo_animation/Sources/duo_animation/PrivacyInfo.xcprivacy']}
end
