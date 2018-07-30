//
//  Line+CoreDataClass.swift
//  Montage
//
//  Created by Germán Leiva on 05/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//
//

import Foundation
import CoreData
import AVFoundation

@objc(Line)
public class Line: NSManagedObject {
    var isAlternative:Bool {
        return self.parent != nil
    }
    var isParent:Bool {
        return self.parent == nil
    }
    var videos:[Video] {
        return elements!.array as! [Video]
    }
    
    class func createComposition(_ elements:[Video],completionHandler:((NSError?,AVMutableComposition?,AVMutableVideoComposition?) -> Void)?) {
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("Couldn't addMutableTrack withMediaType video in AVMutableComposition")
            return
        }
        var compositionAudioTrack:AVMutableCompositionTrack? = nil
        //        var compositionMetadataTrack:AVMutableCompositionTrack? = nil
        var cursorTime = kCMTimeZero
        var lastNaturalSize = CGSize.zero
        
        //        let compositionMetadataTrack = composition.addMutableTrackWithMediaType(AVMediaTypeMetadata, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        var instructions = [AVMutableVideoCompositionInstruction]()
        /*var timedMetadataGroups = [AVTimedMetadataGroup]()*/
        
        //        let locationMetadata = AVMutableMetadataItem()
        //        locationMetadata.identifier = AVMetadataIdentifierQuickTimeUserDataLocationISO6709
        //        locationMetadata.dataType = kCMMetadataDataType_QuickTimeMetadataLocation_ISO6709 as String
        //        locationMetadata.value = "+48.701697+002.188952"
        //        metadataItems.append(locationMetadata)
        
        let assetLoadingGroup = DispatchGroup();
        
        var assetDictionary:[Video:AVAsset] = [:]
        
        for eachElement in elements {
            
            assetLoadingGroup.enter();
            
            if eachElement.isVideo && compositionAudioTrack == nil {
                //I need to create a mutable track for the sound
                compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            }
            
            //I only added the location timed metadata to the TitleCard
            //            if eachElement.isTitleCard() && compositionMetadataTrack == nil {
            //                compositionMetadataTrack = composition.addMutableTrackWithMediaType(AVMediaTypeMetadata, preferredTrackID: kCMPersistentTrackID_Invalid)
            //            }
            guard eachElement.hasVideoFile else {
                let videoIdentifier = eachElement.identifier?.uuidString ?? "Unkown"
                let error = NSError(domain: "File Manager", code: 666, userInfo: [NSLocalizedDescriptionKey : "Video \(videoIdentifier) does not have a video file"])
                completionHandler?(error,nil,nil)
                return
            }
            
            let asset = AVURLAsset(url: eachElement.file, options: [AVURLAssetPreferPreciseDurationAndTimingKey:true])

            asset.loadValuesAsynchronously(forKeys: ["duration"]) {
                assetDictionary[eachElement] = asset
                assetLoadingGroup.leave()
            }
        }
        
        assetLoadingGroup.notify(queue: DispatchQueue.main, execute: {
            for eachElement in elements {
                let asset:AVAsset? = assetDictionary[eachElement]
                let startTime = kCMTimeZero
                var assetDuration = kCMTimeZero
                if eachElement.isVideo {
                    assetDuration = asset!.duration
                } else if eachElement.isTitleCard {
                    //                    let eachTitleCard = eachElement as! TitleCard
                    //                    assetDuration = CMTimeMake(Int64(eachTitleCard.duration!.intValue), 1)
                    
                    var error:NSError?
                    let status = asset!.statusOfValue(forKey: "duration", error: &error)
                    
                    if status != AVKeyValueStatus.loaded {
                        print("Duration was not ready: \(error!.localizedDescription)")
                    }
                    
                    assetDuration = asset!.duration
                    
                    /*let chapterMetadataItem = AVMutableMetadataItem()
                     chapterMetadataItem.identifier = AVMetadataIdentifierQuickTimeUserDataChapter
                     chapterMetadataItem.dataType = kCMMetadataBaseDataType_UTF8 as String
                     //                chapterMetadataItem.time = cursorTime
                     //                chapterMetadataItem.duration = assetDuration
                     //                chapterMetadataItem.locale = NSLocale.currentLocale()
                     //                chapterMetadataItem.extendedLanguageTag = "en-FR"
                     //                chapterMetadataItem.extraAttributes = nil
                     
                     chapterMetadataItem.value = "Capitulo \(elements.indexOfObject(eachElement))"
                     
                     let group = AVMutableTimedMetadataGroup(items: [chapterMetadataItem], timeRange: CMTimeRange(start: cursorTime,duration: kCMTimeInvalid))
                     timedMetadataGroups.append(group)*/
                }
                
                let sourceVideoTrack = asset!.tracks(withMediaType: .video).first
                let sourceAudioTrack = asset!.tracks(withMediaType: .audio).first
                //                let sourceMetadataTrack = asset!.tracksWithMediaType(AVMediaTypeMetadata).first
                
                let range = CMTimeRangeMake(startTime, assetDuration)
                //                let range = CMTimeRangeMake(startTime,sourceVideoTrack!.timeRange.duration)
                do {
                    try compositionVideoTrack.insertTimeRange(range, of: sourceVideoTrack!, at: cursorTime)
                    compositionVideoTrack.preferredTransform = sourceVideoTrack!.preferredTransform
                    //                if sourceMetadataTrack != nil {
                    //                    try compositionMetadataTrack.insertTimeRange(range, ofTrack: sourceMetadataTrack!,atTime:cursorTime)
                    //                }
                    
                    //In the case of having only one TitleCard there is no sound track
                    if let _ = sourceAudioTrack {
                        try compositionAudioTrack!.insertTimeRange(range, of: sourceAudioTrack!, at: cursorTime)
                    }
                    
                    //If there is at least one TitleCard we should have metadata
                    //                    if let _ = sourceMetadataTrack {
                    //                        try compositionMetadataTrack!.insertTimeRange(range, ofTrack: sourceMetadataTrack!, atTime: cursorTime)
                    //                    }
                    
                } catch let error as NSError {
                    completionHandler?(error,nil,nil)
                    return
                }
                
                
                // create a layer instruction at the start of this clip to apply the preferred transform to correct orientation issues
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack:compositionVideoTrack)
                
                //            lastNaturalTimeScale = sourceVideoTrack!.naturalTimeScale
                lastNaturalSize = sourceVideoTrack!.naturalSize
                
                var transformation = sourceVideoTrack!.preferredTransform
                
                if lastNaturalSize != Globals.defaultRenderSize {
                    if lastNaturalSize.width < Globals.defaultRenderSize.width || lastNaturalSize.height < Globals.defaultRenderSize.height {
                        abort()
                    } else {
                        //The lastNaturalSize is bigger than the defaultRenderSize
                        transformation = transformation.scaledBy(x: Globals.defaultRenderSize.width / lastNaturalSize.width, y: Globals.defaultRenderSize.height / lastNaturalSize.height)
                    }
                }
                
                layerInstruction.setTransform(transformation, at: kCMTimeZero)
                
//                if (eachElement is VideoClip) && (eachElement as! VideoClip).isRotated!.boolValue {
//                    let translate = CGAffineTransform(translationX: 1280, y: 720)
//                    let rotate = translate.rotated(by: CGFloat(Double.pi))
//
//                    layerInstruction.setTransform(rotate, at: kCMTimeZero)
//                }
                
                // create the composition instructions for the range of this clip
                let videoTrackInstruction = AVMutableVideoCompositionInstruction()
                videoTrackInstruction.timeRange = CMTimeRange(start:cursorTime, duration:assetDuration)
                videoTrackInstruction.layerInstructions = [layerInstruction]
                
                instructions.append(videoTrackInstruction)
                
                cursorTime = CMTimeAdd(cursorTime, assetDuration)
            }
            
            // create our video composition which will be assigned to the player item
            let videoComposition = AVMutableVideoComposition()
            videoComposition.instructions = instructions
            //        videoComposition.frameDuration = CMTimeMake(1, lastNaturalTimeScale)
            videoComposition.frameDuration = CMTimeMake(1, 30)
            
            //            videoComposition.renderSize = CGSize(width: 1920,height: 1080)
            videoComposition.renderSize = Globals.defaultRenderSize
            
            completionHandler?(nil,composition,videoComposition)
        })
    }
}
