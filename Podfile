platform :osx, '10.10'

target 'sidetalk' do
  use_frameworks!

  pod 'KissXML', '~>5.2.0'
  pod 'XMPPFramework', '~>3.7.0'
  pod 'ReactiveCocoa', '~>7.0.1'
  pod 'MASShortcut', '~>2.3'
  pod 'FuzzySearch', :git => 'https://github.com/yavier/FuzzySearch'
  pod 'ReachabilitySwift', '~>4.1.0'
  pod 'p2.OAuth2', '~>4.0.1'
  pod 'SQLite.swift', '~>0.11.4'

  post_install do |installer|
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['SWIFT_VERSION'] = '4.0'
      end
    end
  end
end

