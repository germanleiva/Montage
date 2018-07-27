//
//  VideoTrack+CoreDataClass.swift
//  Montage
//
//  Created by Germán Leiva on 29/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import Foundation
import CoreData
import Vision
import AVFoundation

@objc(VideoTrack)
public class VideoTrack: NSManagedObject {
    var startedRecordingAt:TimeInterval = -1
    var endedRecordingAt:TimeInterval = -1
    
    var video:Video {
        if inverseBackgroundTrack != nil {
            return inverseBackgroundTrack!
        }
        if inversePrototypeTrack != nil {
            return inversePrototypeTrack!
        }
        fatalError("We should not have a VideoTrack without Video")
    }
    
    var fileURL:URL {
        let fileName:String
        if isPrototype {
            fileName = "prototype.mov"
        } else {
            fileName = "background.mov"
        }
        return video.videoDirectory.appendingPathComponent(fileName)
    }
    
    func startRecording(time:TimeInterval) {
        startedRecordingAt = time
        isRecordingInputs = true
    }
    
    func stopRecording(time:TimeInterval) {
        endedRecordingAt = time
        isRecordingInputs = false
    }
    
    func pauseRecording() {
        isRecordingInputs = false
    }
    
    func resumeRecording() {
        isRecordingInputs = true
    }
    
    var isRecordingInputs = false
    
    var recordedBoxes = [(CMTime,VNRectangleObservation)]()
    
    func box(forItemTime time:CMTime,adjustment:Double) -> VNRectangleObservation? {
        if recordedBoxes.isEmpty {
            return nil
        }

//        print("Looking for time \(time)")
        let lookUpTime = CMTimeAdd(time, CMTime(seconds: adjustment, preferredTimescale: time.timescale))
        var bestBox = recordedBoxes.first!.1
        var shortestDifference = Double.greatestFiniteMagnitude
        for (timeBox,box) in recordedBoxes {
            let diff = abs(CMTimeSubtract(timeBox, lookUpTime).seconds)
//            print("Comparing with \(timeBox)")

            if diff <= 0.015 { //15ms
                return box
            }
            
            if diff < shortestDifference {
                shortestDifference = diff
//                print("Shortest difference so far \(shortestDifference)")
                bestBox = box
            }
        }
//        print("--- Returned ---")
        return bestBox
    }
    func deselectAllTiers() {
        guard let allTiers = tiers?.array as? [Tier] else {
            return
        }
        for eachTier in allTiers {
            if eachTier.isSelected {
                eachTier.isSelected = false
            }
        }
    }
    
    var loadedFileURL:URL? {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }
}
