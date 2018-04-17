# Uncomment this line to define a global platform for your project
platform :ios, '11.3'
# Uncomment this line if you're using Swift
use_frameworks!

workspace 'Montage'

project 'MontageCanvas/MontageCanvas.xcodeproj'
project 'MontageCam/MontageCam.xcodeproj'
project 'MontageMirror/MontageMirror.xcodeproj'

def common_ui_pods
    pod 'MBProgressHUD'
end

def other_pods
end

target 'Streamer' do
    project 'Streamer/Streamer.xcodeproj'
    other_pods
end

target 'MontageCanvas' do
    project 'MontageCanvas/MontageCanvas.xcodeproj'
    common_ui_pods
end

target 'MontageCam' do
    project 'MontageCam/MontageCam.xcodeproj'
    common_ui_pods
end

target 'MontageMirror' do
    project 'MontageMirror/MontageMirror.xcodeproj'
    common_ui_pods
end
