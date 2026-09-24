platform :macos, '12.4'

target 'VimdowManager' do
  pod 'MASShortcut', '~> 2.4.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '12.4'
    end
  end
end
