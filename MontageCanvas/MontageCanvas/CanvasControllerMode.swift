//
//  CanvasControllerMode.swift
//  MontageCanvas
//
//  Created by Germán Leiva on 09/05/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import AVFoundation

protocol CanvasControllerModeDelegate:AnyObject {
    func startedRecording(mode:CanvasControllerRecordingMode)
    func stoppedRecording(mode:CanvasControllerRecordingMode)
    func pausedRecording(mode:CanvasControllerRecordingMode)
    func resumedRecording(mode:CanvasControllerRecordingMode,pausedTimeRange:TimeRange?)
    
    func startedPlaying(mode:CanvasControllerPlayingMode)
    func pausedPlaying(mode:CanvasControllerPlayingMode)
    func resumedPlaying(mode:CanvasControllerPlayingMode)
    
    func playerItemOffset() -> TimeInterval
}

class CanvasControllerMode {
    var shouldRecordInking:Bool {
        return false
    }
    var isPaused:Bool {
        return false
    }
    var isLive:Bool {
        return false
    }
    var isRecording:Bool {
        return false
    }
    var isPlayingMode:Bool {
        return false
    }
    var delegate:CanvasControllerModeDelegate
    
    func startRecording(controller:CameraController) {
        preconditionFailure("This method must be overridden")
    }
    
    func stopRecording(controller:CameraController) {
        preconditionFailure("This method must be overridden")
    }
    
    func pause(controller:CameraController) {
        preconditionFailure("This method must be overridden")
    }
    
    func resume(controller:CameraController) {
        preconditionFailure("This method must be overridden")
    }
    
    init(controller:CameraController) {
        delegate = controller
    }
    
    func normalizedTime(time:TimeInterval) -> TimeInterval? {
        return nil
    }
}

class CanvasControllerLiveMode:CanvasControllerMode {
    override var isLive:Bool {
        return true
    }

    override func startRecording(controller:CameraController) {
        controller.canvasControllerMode = CanvasControllerRecordingMode(controller: controller)
    }
    override func stopRecording(controller:CameraController) {
        controller.alert(nil, title: "Cannot do", message: "I'm not recording")
    }
    
    override func pause(controller:CameraController) {
        controller.alert(nil, title: "Cannot do", message: "Cannot pause when streaming")
    }
    
    override func resume(controller:CameraController) {
        controller.alert(nil, title: "Cannot do", message: "Cannot resume when streaming")
    }
}

class CanvasControllerRecordingMode:CanvasControllerMode {
    override var shouldRecordInking:Bool {
        return !isPaused
    }
    override var isRecording:Bool {
        return true
    }
    override var isPaused:Bool {
        return currentlyPausedAt != nil
    }
    
    var startedRecordingAt:TimeInterval
    var currentlyPausedAt:TimeInterval?
    var stoppedRecordingAt:TimeInterval?
    
    override init(controller:CameraController) {
        startedRecordingAt = Date().timeIntervalSince1970
        super.init(controller: controller)
        
        controller.startedRecording(mode: self)
    }
    
    override func startRecording(controller:CameraController) {
        controller.alert(nil, title: "Cannot do", message: "I'm already recording")
    }
    override func stopRecording(controller:CameraController) {
        stoppedRecordingAt = Date().timeIntervalSince1970
        controller.stoppedRecording(mode: self)
    }
    
    override func pause(controller:CameraController) {
        if currentlyPausedAt == nil {
            currentlyPausedAt = Date().timeIntervalSince1970
        }
        controller.pausedRecording(mode: self)
    }
    
    override func resume(controller:CameraController) {
        guard let recordingPauseStartedAt = currentlyPausedAt else {
            return
        }
        
        let startTime = CMTime(seconds: recordingPauseStartedAt - startedRecordingAt, preferredTimescale: DEFAULT_TIMESCALE)
        let durationInSeconds = Date().timeIntervalSince1970 - recordingPauseStartedAt
        let pausedTimeRange = CMTimeRange(start: startTime, duration: CMTimeMakeWithSeconds(durationInSeconds, DEFAULT_TIMESCALE))
        
        currentlyPausedAt = nil
        
        controller.resumedRecording(mode: self,pausedTimeRange:pausedTimeRange)
    }
    
    override func normalizedTime(time:TimeInterval) -> TimeInterval? {
        if let lastValidTime = currentlyPausedAt {
            return lastValidTime - startedRecordingAt
        }
        return time - startedRecordingAt
    }
}

class CanvasControllerPlayingMode:CanvasControllerMode {
    override var shouldRecordInking:Bool {
        return !isPaused
    }
    
    override var isPlayingMode:Bool {
        return true
    }
    override var isPaused:Bool {
        return currentlyPausedAt != nil
    }
    
    var currentlyPausedAt:TimeInterval?

    override func startRecording(controller:CameraController) {
        controller.alert(nil, title: "Cannot do", message: "Cannot start recording while in playback")
    }
    
    override func stopRecording(controller:CameraController) {
        controller.alert(nil, title: "Cannot do", message: "Cannot stop recording while in playback")
    }
    
    override func pause(controller:CameraController) {
        currentlyPausedAt = controller.playerItemOffset()
        
        controller.pausedPlaying(mode: self)
    }
    
    override func resume(controller:CameraController) {
        currentlyPausedAt = nil
        
        controller.resumedPlaying(mode: self)
    }
    
    override func normalizedTime(time:TimeInterval) -> TimeInterval? {
        return delegate.playerItemOffset()
    }
}
