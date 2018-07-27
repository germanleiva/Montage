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

def common_pods
    pod 'NHNetworkTime'
end

target 'Streamer_Mac' do
    platform :osx, '10.13'
    project 'Streamer/Streamer.xcodeproj'
end

target 'Streamer' do
    project 'Streamer/Streamer.xcodeproj'
end

target 'MontageCanvas' do
    project 'MontageCanvas/MontageCanvas.xcodeproj'
    common_ui_pods
    common_pods
end

target 'MontageCam' do
    project 'MontageCam/MontageCam.xcodeproj'
    common_ui_pods
    common_pods
end

target 'MontageMirror' do
    project 'MontageMirror/MontageMirror.xcodeproj'
    common_ui_pods
end

target 'MontageMirrorMac' do
    platform :osx, '10.13'
    project 'MontageMirror/MontageMirror.xcodeproj'
end
