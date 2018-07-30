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
    
    func startedLiveMode(mode:CanvasControllerLiveMode)

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
    weak var delegate:CanvasControllerModeDelegate?
    
    func startRecording(controller:CameraController) {
        preconditionFailure("This method must be overridden")
    }
    
    func cancelRecording(controller:CameraController) {
        //Empty implementation
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
    
    var currentTime:TimeInterval = 0.0  //This does NOT count the paused ranges, check property accumulatedTime
}

class CanvasControllerLiveMode:CanvasControllerMode {
    override var isLive:Bool {
        return true
    }

    override func startRecording(controller:CameraController) {
        controller.canvasControllerMode = CanvasControllerRecordingMode(controller: controller)
    }
    override func stopRecording(controller:CameraController) {
//        controller.alert(nil, title: "Cannot do", message: "I'm not recording")
    }
    
    override func pause(controller:CameraController) {
        controller.alert(nil, title: "Cannot do", message: "Cannot pause when streaming")
    }
    
    override func resume(controller:CameraController) {
        controller.alert(nil, title: "Cannot do", message: "Cannot resume when streaming")
    }
    
    override init(controller:CameraController) {
        super.init(controller: controller)
        
        delegate?.startedLiveMode(mode: self)
    }
}

class CanvasControllerRecordingMode:CanvasControllerMode {
    var timer:RepeatingTimer?
    
    override var shouldRecordInking:Bool {
        return !isPaused
    }
    override var isRecording:Bool {
        return true
    }
    override var isPaused:Bool {
        return currentlyPausedAt != nil
    }
    
    let timerInterval = 0.0001 //in seconds, this is 0.1 millisecond
    var currentlyPausedAt:TimeInterval?
    
    var accumulatedTime:TimeInterval = 0.0 //This count the paused ranges
    
    override init(controller:CameraController) {
        super.init(controller: controller)
        
        currentlyPausedAt = nil
        
        let weakSelf = self
        timer = RepeatingTimer(timeInterval: 0.0001)
        timer?.eventHandler = {
            if !weakSelf.isPaused {
                weakSelf.currentTime += weakSelf.timerInterval
            }
            
            weakSelf.accumulatedTime += weakSelf.timerInterval
        }
        timer?.resume()
        
        controller.startedRecording(mode: self)
    }
    
    override func startRecording(controller:CameraController) {
        controller.alert(nil, title: "Cannot do", message: "I'm already recording")
    }
    
    override func cancelRecording(controller: CameraController) {
        controller.cancelRecording(mode: self)
    }
    
    override func stopRecording(controller:CameraController) {
        if isPaused {
            //TODO:
        }
        controller.stoppedRecording(mode: self)
        
        timer = nil
    }
    
    override func pause(controller:CameraController) {
        currentlyPausedAt = Date().timeIntervalSince1970
        controller.pausedRecording(mode: self)
    }
    
    override func resume(controller:CameraController) {
        guard let recordingPauseStartedAt = currentlyPausedAt else {
            return
        }
        
        currentlyPausedAt = nil
        
        let durationInSeconds = Date().timeIntervalSince1970 - recordingPauseStartedAt
        let startTime = CMTime(seconds: accumulatedTime - durationInSeconds, preferredTimescale: DEFAULT_TIMESCALE)
        let pausedTimeRange = CMTimeRange(start: startTime, duration: CMTimeMakeWithSeconds(durationInSeconds, DEFAULT_TIMESCALE))
        
        controller.resumedRecording(mode: self,pausedTimeRange:pausedTimeRange)
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

    override init(controller:CameraController) {
        super.init(controller: controller)
        
        controller.startedPlaying(mode: self)
    }
    
    override func startRecording(controller:CameraController) {
        controller.alert(nil, title: "Cannot do", message: "Cannot start recording while in playback")
    }
    
    override func stopRecording(controller:CameraController) {
//        controller.alert(nil, title: "Cannot do", message: "Cannot stop recording while in playback")
    }
    
    override func pause(controller:CameraController) {
        currentlyPausedAt = controller.playerItemOffset()
        
        controller.pausedPlaying(mode: self)
    }
    
    override func resume(controller:CameraController) {
        currentlyPausedAt = nil
        
        controller.resumedPlaying(mode: self)
    }
    
    override var currentTime: TimeInterval {
        get {
            return delegate?.playerItemOffset() ?? 0
        }
        set {
            preconditionFailure("CanvasControllerPlayingMode >> This method should never be called")
        }
    }
}
