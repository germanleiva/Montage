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
        
        //Let's create the videoDirectory
        do {
            //[.posixPermissions: 0777]
            try FileManager.default.createDirectory(at: videoDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            fatalError("Could not create videoDirectory at \(videoDirectory): \(error.localizedDescription)")
        }
        
        backgroundTrack = VideoTrack(context: context)
        prototypeTrack = VideoTrack(context: context)
        
        pausedTimeRanges = [TimeRange]()
    }
    
    var isNew:Bool {
        return backgroundTrack!.loadedFileURL == nil && prototypeTrack!.loadedFileURL == nil
    }
    
    public override func prepareForDeletion() {
        if hasVideoFile {
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
        do {
            try FileManager.default.copyItem(at: tempVideoFile, to: file)
            try self.managedObjectContext!.save()
            DispatchQueue.main.async {
                completionBlock()
            }
        } catch let error as NSError {
            print("Could not save video file: \(error.localizedDescription)")
        }
    }
        
    func generateImageFromVideoFile(compressionQuality:CGFloat) -> Data? {
        guard hasVideoFile else {
            return nil
        }
        
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
        
        if let image = generateImage(forUrl: file) {
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
        
        DispatchQueue.global(qos: .default).async {
            guard let aThumbnailData = self.generateImageFromVideoFile(compressionQuality: 0.3) else {
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
        
        DispatchQueue.global(qos: .default).async {
            guard let aSnapshoptData = self.generateImageFromVideoFile(compressionQuality: 0.3) else {
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
        if hasVideoFile {
            completionBlock(AVAsset(url: self.file))
        } else {
            completionBlock(nil)
        }
    }
    
    var name:String {
        let currentIdentifier:UUID
        
        if let anIdentifier = identifier {
            currentIdentifier = anIdentifier
        } else {
            currentIdentifier = UUID()
            identifier = currentIdentifier
            do {
                try managedObjectContext?.save()
            } catch let error as NSError {
                print("Couldn't force saving after initializing the identifier: \(error.localizedDescription)")
            }
        }
        return currentIdentifier.uuidString
    }
    
    var videoDirectory:URL {
        return Globals.documentsDirectory.appendingPathComponent(self.name, isDirectory: true)
    }
    
    var hasVideoFile:Bool {
        return FileManager.default.fileExists(atPath: file.path)
    }
    
    var file:URL {
        return videoDirectory.appendingPathComponent("final.mov")
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
