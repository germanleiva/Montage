# Uncomment this line to define a global platform for your project
platform :ios, '11.3'
# Uncomment this line if you're using Swift
use_frameworks!

workspace 'Montage'

xcodeproj 'MontageCanvas/MontageCanvas.xcodeproj'
xcodeproj 'MontageCam/MontageCam.xcodeproj'
xcodeproj 'MontageMirror/MontageMirror.xcodeproj'

def common_ui_pods
pod 'MBProgressHUD'
end

def other_pods
pod 'Reachability'
end

target 'MontageCanvas' do
xcodeproj 'MontageCanvas/MontageCanvas.xcodeproj'
common_ui_pods
end

target 'MontageCam' do
xcodeproj 'MontageCam/MontageCam.xcodeproj'
common_ui_pods
end

target 'MontageMirror' do
xcodeproj 'MontageMirror/MontageMirror.xcodeproj'
common_ui_pods
end
