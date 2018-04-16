//
//  MovieWriter.swift
//  MontageCam
//
//  Created by Germán Leiva on 20/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import AVFoundation

protocol MovieWriterDelegate:class {
    func didWriteMovie(atURL outputURL:URL)
}

class MovieWriter: NSObject {
    var isWriting = false
    
    weak var delegate:MovieWriterDelegate?
    private let videoSettings:[String : Any]
    private var writingDispatchQueue:DispatchQueue
    //    private var ciContex:CIContext
    private var colorSpace:CGColorSpace
    //    private var activeFilter:CIFilter
    private var firstSample = true

    init(_ videoSettings:[String : Any]) {
        self.videoSettings = videoSettings
        self.writingDispatchQueue = DispatchQueue(label: "fr.ex-situ.Montage.writingDispatchQueue")
        self.colorSpace = CGColorSpaceCreateDeviceRGB()
        
        super.init()
    }
    
    var outputURL:URL {
        let fileName = "movie-example.mov"
        let filePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        do {
            try FileManager.default.removeItem(at: filePath)
            print("Cleaned \(fileName)")
        } catch let error as NSError {
            print("(not a problem) First usage of \(fileName): \(error.localizedDescription)")
        }
        return filePath
    }
    
    private var assetWriter:AVAssetWriter!
    private var assetWriterVideoInput:AVAssetWriterInput!
    private var assetWriterAudioInput:AVAssetWriterInput?
    private var assetWriterInputPixelBufferAdaptor:AVAssetWriterInputPixelBufferAdaptor!
    
    func transformForDeviceOrientation(_ orientation:UIDeviceOrientation) -> CGAffineTransform {
        let result:CGAffineTransform
        
        switch (orientation) {
            
        case .landscapeRight:
            result = CGAffineTransform(rotationAngle: CGFloat.pi)
            break
        case .portraitUpsideDown:
            result = CGAffineTransform(rotationAngle: (CGFloat.pi / 2) * 3)
            break
            
        case .portrait/*,.faceUp,.faceDown*/:
            result = CGAffineTransform(rotationAngle: CGFloat.pi / 2)
            break
            
        default: // Default orientation of landscape left
            result = CGAffineTransform.identity
            break
        }
        
        return result
    }
    
    
    func startWriting() {
        writingDispatchQueue.async {[unowned self] in
            let fileType = AVFileType.mov
            
            do {
                self.assetWriter = try AVAssetWriter(url: self.outputURL, fileType: fileType)
            } catch let error as NSError {
                print("Could not create AVAssetWriter: \(error.localizedDescription)")
                return
            }
            
            self.assetWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: self.videoSettings)
            
            //This it is recommended to be true when recording a movie file but false when processing the frames
            self.assetWriterVideoInput.expectsMediaDataInRealTime = true
            
            self.assetWriterVideoInput.transform = self.transformForDeviceOrientation(UIDevice.current.orientation)
            
            //To ensure maximum efficiency, the values in this dictionary should correspond to the source pixel format used when configuring the AVCaptureVideoDataOutput
            let attributes = [
                kCVPixelBufferPixelFormatTypeKey : kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey : self.videoSettings[AVVideoWidthKey] ?? 1920, //check recommendedVideoSettingsForAssetWriter
                kCVPixelBufferHeightKey : self.videoSettings[AVVideoHeightKey] ?? 1080,
//                kCVPixelFormatOpenGLESCompatibility : kCFBooleanTrue
            ] as [String : Any]
            
            self.assetWriterInputPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.assetWriterVideoInput, sourcePixelBufferAttributes: attributes)
            
            if self.assetWriter.canAdd(self.assetWriterVideoInput) {
                self.assetWriter.add(self.assetWriterVideoInput)
            } else {
                print("Unable to add video input to assetWriter")
                return
            }
            
            //We did not configure an audioInput
//            self.assetWriterAudioInput =  AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: self.audioSettings)
//
//            self.assetWriterAudioInput.expectsMediaDataInRealTime = true
//
//            if self.assetWriter.canAdd(self.assetWriterAudioInput) {
//                self.assetWriter.add(self.assetWriterAudioInput)
//            } else {
//                print("Unable to add audio input to assetWriter")
//                return
//            }
            
            self.isWriting = true
            self.firstSample = true
        }
    }
    
    func process(sampleBuffer:CMSampleBuffer) {
        if !self.isWriting {
            return
        }
        
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            print("Could not extract the FormatDescription fom the sample buffer")
            return
        }
        
        let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
        
        if mediaType == kCMMediaType_Video {
            
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            if (self.firstSample) {
                if self.assetWriter.startWriting() {
                    self.assetWriter.startSession(atSourceTime: timestamp)
                } else {
                    print("Failed to start writing.")
                }
                self.firstSample = false
            }
            /*
            var outputRenderBuffer:CVPixelBuffer? = nil
            
            let pixelBufferPool = self.assetWriterInputPixelBufferAdaptor.pixelBufferPool
            
            let err = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool!, &outputRenderBuffer)

            switch err {
            case kCVReturnSuccess:
//                print("Function executed successfully without errors.")
                break
            default:
                print("ERROR: Unable to obtain a pixel buffer from the pool.")
//                @constant   kCVReturnFirst Placeholder to mark the beginning of the range of CVReturn codes.
//                @constant   kCVReturnLast Placeholder to mark the end of the range of CVReturn codes.
//
//                @constant   kCVReturnInvalidArgument At least one of the arguments passed in is not valid. Either out of range or the wrong type.
//                @constant   kCVReturnAllocationFailed The allocation for a buffer or buffer pool failed. Most likely because of lack of resources.
//
//                @constant   kCVReturnInvalidDisplay A CVDisplayLink cannot be created for the given DisplayRef.
//                @constant   kCVReturnDisplayLinkAlreadyRunning The CVDisplayLink is already started and running.
//                @constant   kCVReturnDisplayLinkNotRunning The CVDisplayLink has not been started.
//                @constant   kCVReturnDisplayLinkCallbacksNotSet The output callback is not set.
//
//                @constant   kCVReturnInvalidPixelFormat The requested pixelformat is not supported for the CVBuffer type.
//                @constant   kCVReturnInvalidSize The requested size (most likely too big) is not supported for the CVBuffer type.
//                @constant   kCVReturnInvalidPixelBufferAttributes A CVBuffer cannot be created with the given attributes.
//                @constant   kCVReturnPixelBufferNotOpenGLCompatible The Buffer cannot be used with OpenGL as either its size, pixelformat or attributes are not supported by OpenGL.
//                @constant   kCVReturnPixelBufferNotMetalCompatible The Buffer cannot be used with Metal as either its size, pixelformat or attributes are not supported by Metal.
//
//                @constant   kCVReturnWouldExceedAllocationThreshold The allocation request failed because it would have exceeded a specified allocation threshold (see kCVPixelBufferPoolAllocationThresholdKey).
//                @constant   kCVReturnPoolAllocationFailed The allocation for the buffer pool failed. Most likely because of lack of resources. Check if your parameters are in range.
//                @constant   kCVReturnInvalidPoolAttributes A CVBufferPool cannot be created with the given attributes.
//                @constant   kCVReturnRetry a scan hasn't completely traversed the CVBufferPool due to a concurrent operation. The client can retry the scan.
                return
            }*/
            
//            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
//            let sourceImage = CIImage(cvPixelBuffer: imageBuffer)
//            self.activeFilter.setValue(sourceImage, forKey: kCIInputImageKey)
//                let filteredImage = self.activeFilter.outputImage
//            if !filteredImage {
//                filteredImage = sourceImage
//            }
//            self.ciContext.render(filteredImage, to: outputRenderBuffer, bounds: filteredImage.extent, colorSpace: self.colorSpace)
            
            if self.assetWriterVideoInput.isReadyForMoreMediaData {
                if !self.assetWriterInputPixelBufferAdaptor.append(CMSampleBufferGetImageBuffer(sampleBuffer)!, withPresentationTime: timestamp) {
                    print("Error appending pixel buffer.")
                }
            }
            
//            outputRenderBuffer = nil
            
        } //No audio yet
        /*else if !self.firstSample && mediaType == kCMMediaType_Audio {
            if self.assetWriterAudioInput.isReadyForMoreMediaData {
                if !self.assetWriterAudioInput?.append(sampleBuffer) {
                    print("Error appending audio sample buffer.")
                }
            }
        }*/
    }
    
    func stopWriting() {
        guard self.isWriting else {
            return
        }
        print("MovieWriter >> stopWriting()")
        self.isWriting = false
        guard let assetWriter = self.assetWriter else {
            return
        }
        let delegate = self.delegate
        writingDispatchQueue.async {
            if [.unknown, .failed,.cancelled].contains(assetWriter.status) {
                print("Asset writer in weird state after stopWriting(): \(assetWriter.error!.localizedDescription)")
            }
            assetWriter.finishWriting {
                if assetWriter.status == AVAssetWriterStatus.completed {
                    DispatchQueue.main.async {
                        delegate?.didWriteMovie(atURL: assetWriter.outputURL)
                    }
                } else {
                    print("Failed to write movie: \(assetWriter.error!.localizedDescription)")
                }
            }
        }
    }
}
