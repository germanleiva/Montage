//
//  Video+CoreDataClass.swift
//  Montage
//
//  Created by Germán Leiva on 12/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//
//

import Foundation
import CoreData
import AVFoundation

@objc(Video)
public class Video: NSManagedObject {
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        guard let context = managedObjectContext else {
            print("Could not create VideoTracks in Video >> awakeFromInsert")
            return
        }
        
        identifier = UUID()
        
        prototypeTrack = VideoTrack(context: context)
        prototypeTrack?.fileURL = Globals.documentsDirectory.appendingPathComponent("\(self.name!)-prototype.mov")
        
        backgroundTrack = VideoTrack(context: context)
        backgroundTrack?.fileURL = Globals.documentsDirectory.appendingPathComponent("\(self.name!)-background.mov")
        
        pausedTimeRanges = [TimeRange]()
    }
    
    public override func prepareForDeletion() {
        if let file = self.file {
            do {
                print("Deleting video file: \(file.absoluteString)")
                try FileManager().removeItem(at: file)
            } catch let error as NSError {
                print("Could not delete video file: \(error.localizedDescription)")
            }
        }
        super.prepareForDeletion()
    }
    
    func saveVideoFile(_ tempVideoFile:URL, completionBlock: @escaping () -> Void) {
        self.isRecorded = true //isRecorded is used inside file, so it needs to be set to true before asking for the file
        
        do {
            try FileManager.default.copyItem(at: tempVideoFile, to: self.file!)
            try self.managedObjectContext!.save()
            DispatchQueue.main.async {
                completionBlock()
            }
        } catch let error as NSError {
            print("Could not save video file: \(error.localizedDescription)")
        }
    }
        
    func generateImageFromVideo(_ aFile:URL, compressionQuality:CGFloat) -> Data? {
        func generateImage(forUrl url: URL) -> UIImage? {
            let asset: AVAsset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            
            do {
                let generatedThumbnailImage = try imageGenerator.copyCGImage(at: CMTimeMake(1, 60) , actualTime: nil)
                return UIImage(cgImage: generatedThumbnailImage)
            } catch let error as NSError {
                print("Could not generateImage: \(error.localizedDescription)")
            }
            
            return nil
        }
        
        if let image = generateImage(forUrl: aFile) {
            guard let imageDataRepresentation = UIImageJPEGRepresentation(image, 1) else {
                // handle failed conversion
                print("jpg error")
                return nil
            }
            return imageDataRepresentation
        }
        return nil
    }
    
    func loadThumbnailImage(completionBlock: @escaping ((UIImage?) -> Void)) {
        if let cachedThumbnailImage = thumbnailImage {
            completionBlock(cachedThumbnailImage)
            return
        }
        guard let file = self.file else {
            print("I do not have a video file")
            return
        }
        
        DispatchQueue.global(qos: .default).async {
            guard let aThumbnailData = self.generateImageFromVideo(file, compressionQuality: 0.3) else {
                print("Could not generate image data for the thumbnail")
                return
            }
            
            self.thumbnailData = aThumbnailData
            self.thumbnailImage = UIImage(data: aThumbnailData)
            
            // Bounce back to the main thread to update the UI
            DispatchQueue.main.async {
                completionBlock(self.thumbnailImage)
            }
        }
    }
    
    func loadSnapshotImage(completionBlock: @escaping ((UIImage?) -> Void)) {
        if let cachedSnapshotImage = snapshotImage {
            completionBlock(cachedSnapshotImage)
            return
        }
        guard let file = self.file else {
            print("I do not have a video file")
            return
        }
        
        DispatchQueue.global(qos: .default).async {
            guard let aSnapshoptData = self.generateImageFromVideo(file, compressionQuality: 0.3) else {
                print("Could not generate image data for the snapshot")
                return
            }
            
            self.snapshotData = aSnapshoptData
            self.snapshotImage = UIImage(data: aSnapshoptData)
            
            // Bounce back to the main thread to update the UI
            DispatchQueue.main.async {
                completionBlock(self.snapshotImage)
            }
        }
    }
    
    func loadAsset(completionBlock: @escaping ((AVAsset?) -> Void)) {
        if let aFile = self.file {
            completionBlock(AVAsset(url: aFile))
        } else {
            completionBlock(nil)
        }
    }
    
    var name:String? {
        return self.identifier?.uuidString
    }
    
    var fileName:String? {
        guard let aName = self.name else {
            return nil
        }
        return aName + "-background.mov"
    }
    
    var file:URL? {
        guard let aFileName = self.fileName else {
            return nil
        }
        let documentsDirectory = Globals.documentsDirectory
        return documentsDirectory.appendingPathComponent("\(aFileName)")
    }
    
    var snapshotImage:UIImage?
    internal var thumbnailImage:UIImage?
    
    var isVideo: Bool {
        return false
    }
    
    var isTitleCard: Bool {
        return false
    }
    
    var snapshotData:Data? {
        get {
            return self.snapshot
        }
        set {
            self.snapshot = newValue
            self.snapshotImage = nil
        }
    }
    var thumbnailData:Data? {
        get {
            return self.thumbnail
        }
        set {
            self.thumbnail = newValue
            self.thumbnailImage = nil
        }
    }
}
