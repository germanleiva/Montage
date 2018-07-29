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
    
    var recordedBoxes:[BoxObservation] {
        if let savedBoxes = boxes {
            return savedBoxes.array as! [BoxObservation]
        }
        return []
    }
    
    func box(forItemTime lookUpTime:CMTime) -> VNRectangleObservation? {
        if recordedBoxes.isEmpty {
            return nil
        }
        for (index,boxObservation) in recordedBoxes.enumerated() {
            let time = boxObservation.time
            let box = boxObservation.observation
            
            switch CMTimeCompare(time, lookUpTime) {
            //-1 is returned if time is less than lookUpTime.
            case -1:
                continue
            //1 is returned if time is greater than lookUpTime.
            case 1:
                if index > 0 {
                    let previousBoxObservation = recordedBoxes[index - 1]
                    let differenceWithCurrent = CMTimeSubtract(time, lookUpTime)
                    let differenceWithPrevious = CMTimeSubtract(lookUpTime, previousBoxObservation.time)
                    
                    if CMTimeCompare(differenceWithPrevious, differenceWithCurrent) < 0 {
                        return previousBoxObservation.observation
                    }
                }
                return box
            //0 is returned if time and lookUpTime are equal.
            default:
                return box
            }
        }
        
        //I passed the whole array so the lookUpTime is the greatest, the closest it is the last one
        return recordedBoxes.last?.observation
    }
    
    /*
    func box(forItemTime lookUpTime:CMTime) -> VNRectangleObservation? {
        if recordedBoxes.isEmpty {
            return nil
        }

//        print("Looking for time \(time)")
        var bestBox = recordedBoxes.first!.1
        var shortestDifference = Double.greatestFiniteMagnitude
        for (timeBox,box) in recordedBoxes {
            let diff = abs(CMTimeSubtract(timeBox, lookUpTime).seconds)
//            print("Comparing with \(timeBox)")

//            if diff <= 0.015 { //15ms
//            if diff <= 0.001 { //1ms
//                return box
//            }
            
            if diff < shortestDifference {
                shortestDifference = diff
//                print("Shortest difference so far \(shortestDifference)")
                bestBox = box
            }
        }
//        print("--- Returned ---")
        return bestBox
    }*/
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
