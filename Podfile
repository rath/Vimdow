platform :macos, '10.10'

target 'VimdowManager' do
  pod 'MASShortcut', '~> 2.4.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOS_DEPLOYMENT_TARGET'] = '10.10'
     end
  end
end
