//
//  ViewController.swift
//  MontageCam
//
//  Created by Germán Leiva on 29/11/2017.
//  Copyright © 2017 ExSitu. All rights reserved.
//

import UIKit
import AVFoundation
import MultipeerConnectivity
import Vision
import CloudKit
import WatchConnectivity

enum MontageRole:Int {
    case undefined = 0
    case iphoneCam
    case iPadCam
    case mirror
    case watchMirror
    case canvas
}

//    dispatch_queue_create("cachequeue", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL)
let visionQueue = DispatchQueue.global(qos: .userInteractive)
let streamingQueue1 = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_streaming_queue_1", qos: DispatchQoS.userInteractive)
let streamingQueue2 = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_streaming_queue_1", qos: DispatchQoS.userInteractive)
let mirrorQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_mirror_queue", qos: DispatchQoS.userInteractive)
let watchQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_watch_queue", qos: DispatchQoS.userInteractive)

let fps = 24.0

class ViewController: UIViewController, MovieWriterDelegate, OutputStreamOwner, InputStreamOwnerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, StreamDelegate, WCSessionDelegate {
    
    var myRole:String?
    
    var recordStartedAt:TimeInterval?
    var currentDetectedRectangle:VNRectangleObservation?
    var firstCaptureFrameTimeStamp:CMTime?
    
    var savedBoxes = [NSDictionary:VNRectangleObservation]()
    var isMirrorMode = false
    var isStreaming:Bool = false {
        didSet {
            if isStreaming {
                if !captureSession.isRunning {
                    captureSession.startRunning()
                }
            } else {
                if captureSession.isRunning {
                    captureSession.stopRunning()
                    for outputStreamHandler in outputStreamHandlers {
                        outputStreamHandler.close()
                    }
                }
            }
        }
    }
    
    @IBOutlet weak var slider0:UISlider!
    @IBOutlet weak var slider1:UISlider!
    @IBOutlet weak var slider2:UISlider!
    @IBOutlet weak var slider3:UISlider!
    @IBOutlet weak var slider4:UISlider!
    
    let context = CIContext()
    var overlayImage:CIImage?
    
    @IBAction func recordToggle(_ sender:UIButton) {
        guard let writer = movieWriter else {
            return
        }
        
        if writer.isWriting {
            writer.stopWriting()
            sender.setTitle("Record", for: UIControlState.normal)
        } else {
            writer.startWriting()
            sender.setTitle("Stop", for: UIControlState.normal)
        }
    }
    
    var rectangleLocked = false
    
    var videoLayer:AVCaptureVideoPreviewLayer?
    var rectangleLayer:CAShapeLayer!
    
    // MARK: CloutKit
    
    let myContainer = CKContainer(identifier: "iCloud.fr.lri.ex-situ.Montage")
    lazy var publicDatabase = {
        return myContainer.publicCloudDatabase
    }()
    
    // MARK: Vision.framework variables
    lazy var requests:[VNRequest] = {
        let rectangleRequest = VNDetectRectanglesRequest(completionHandler: self.detectRectanglesHandler)
        rectangleRequest.minimumAspectRatio = 0.5 //16/9
        rectangleRequest.maximumAspectRatio = 1 //16/9
        rectangleRequest.minimumSize = 0.15
        rectangleRequest.minimumConfidence = 1 //0 //default
        rectangleRequest.quadratureTolerance = 45
        
        return [rectangleRequest]
    }()
    
    // MARK: AV
    var outputStreamHandlers = Set<OutputStreamHandler>()
    
    func addOutputStreamHandler(_ outputStreamHandler:OutputStreamHandler) {
        outputStreamHandlers.insert(outputStreamHandler)
    }
    
    func removeOutputStreamHandler(_ outputStreamHandler:OutputStreamHandler) {
        outputStreamHandlers.remove(outputStreamHandler)
    }
    var inputStreamHandlers = Set<InputStreamHandler>()
    
    func addInputStreamHandler(_ inputStreamHandler:InputStreamHandler) {
        inputStreamHandlers.insert(inputStreamHandler)
    }
    
    func removeInputStreamHandler(_ inputStreamHandler:InputStreamHandler) {
        inputStreamHandlers.remove(inputStreamHandler)
    }
    
    lazy var captureSession = {
        return AVCaptureSession()
    }()
    
    var movieWriter:MovieWriter!
    
    // MARK: MC
    
    let serviceType = "multipeer-video"
    
    lazy var localPeerID = {
        return MCPeerID(displayName: UIDevice.current.name)
    }()
    
    lazy var multipeerSession:MCSession = {
        let session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: MCEncryptionPreference.optional)
        session.delegate = self
        return session
    }()
    
    lazy var serviceAdvertiser:MCNearbyServiceAdvertiser = {
        let role:MontageRole
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            role = .iphoneCam
            break
        case .pad:
            role = .iPadCam
            break
        default:
            role = .undefined
        }
        
        let info = ["role":String(describing:role.rawValue)]
        let _serviceAdvertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: info, serviceType: serviceType)
        _serviceAdvertiser.delegate = self
        return _serviceAdvertiser
    }()
    
    deinit {
        for anInputStreamHandler in inputStreamHandlers {
            anInputStreamHandler.close()
        }
        for anOutputStreamHandler in outputStreamHandlers {
            anOutputStreamHandler.close()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        //        cloudKitInitialize()
        
        if self.setupCamera() {
            isStreaming = true //This starts the captureSession
            if captureSession.isRunning {
                print("initial startAdvertisingPeer")
                serviceAdvertiser.startAdvertisingPeer()
            }
        }
        
        //        setupWatchSession()
        
        //        setupVisionDetection()
    }
    
    //Watch related code
    
    var lastTimeSent = Date()
    var watchConnectivitySession:WCSession?
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("activationDidCompleteWith \(activationState)")
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("sessionDidBecomeInactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("activationDidCompleteWith")
    }
    
    func setupWatchSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            
            watchConnectivitySession = session
        }
    }
    
    
    func cloudKitInitialize() {
        //        publicDatabase.fetch(withRecordID: CKRecordID(recordName:"115")) { (videoRecord, error) in
        //            if let error = error {
        //                // Error handling for failed fetch from public database
        //                print("CloudKit could not fetch video: \(error.localizedDescription)")
        //                return
        //            }
        //
        //            // Display the fetched record
        //            if let isRecording = videoRecord!["isRecording"] as? NSNumber {
        //                print("Succesfully fetched video \(isRecording.boolValue)")
        //            }
        //        }
        let predicate = NSPredicate(format: "isRecording = %@", NSNumber(value:true))
        let query = CKQuery(recordType: "Video", predicate: predicate)
        publicDatabase.perform(query, inZoneWith: nil) { (results, error) in
            if let error = error {
                // Error handling for failed fetch from public database
                print("CloudKit perform query: \(error.localizedDescription)")
                return
            }
            
            // Display the fetched record
            if let videoRecords = results {
                print("Succesfully queried \(videoRecords.count) videos")
            }
        }
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
    }
    
    // MARK: Vision.framework
    
    func visionDetection(_ sampleBuffer:CMSampleBuffer, outputImage:CIImage) {
        var requestOptions:[VNImageOption : Any] = [:]
        
        if let camData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            //            requestOptions = [.cameraIntrinsics:camData,.ciContext:ciContext]
            requestOptions = [.cameraIntrinsics:camData]
            
        }
        
        //        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: outputImage.pixelBuffer!, orientation: CGImagePropertyOrientation.downMirrored, options: requestOptions)
        
        let imageRequestHandler = VNImageRequestHandler(ciImage: outputImage, orientation: CGImagePropertyOrientation.downMirrored, options: requestOptions)
        
        //        DispatchQueue.main.async {
        //            let rectangleRequest = self.requests.first as! VNDetectRectanglesRequest
        //            rectangleRequest.minimumAspectRatio = self.slider0.value //16/9
        //            rectangleRequest.maximumAspectRatio = self.slider1.value //16/9
        //            rectangleRequest.minimumSize = self.slider2.value //0.5
        //            rectangleRequest.minimumConfidence = self.slider3.value ////0 //default
        //            rectangleRequest.quadratureTolerance = self.slider4.value //45
        //        }
        do {
            try imageRequestHandler.perform(self.requests)
        } catch let error as NSError {
            print(error.localizedDescription)
        }
    }
    
    //    func setupVisionDetection() {
    //        //        let textRequest = VNDetectTextRectanglesRequest(completionHandler: self.detect)
    //        //        textRequest.reportCharacterBoxes = true
    //
    //        let rectangleRequest = VNDetectRectanglesRequest(completionHandler: self.detectRectanglesHandler)
    //        rectangleRequest.quadratureTolerance = 45
    //        rectangleRequest.minimumAspectRatio = 16/9
    //        rectangleRequest.maximumAspectRatio = 16/9
    //        rectangleRequest.minimumSize = 0.5
    //        rectangleRequest.minimumConfidence = 0.8 //0 //default
    //
    //        self.requests = [rectangleRequest]
    //    }
    
    func detectRectanglesHandler(request: VNRequest, error: Error?) {
        let weakSelf = self
        visionQueue.async {
            guard let observations = request.results else {
                //                print("no result")
                return
            }
            
            let result = observations.map({$0 as? VNRectangleObservation})
            
            for region in result {
                guard let detectedRectangle = region else {
                    continue
                }
                weakSelf.currentDetectedRectangle = detectedRectangle
                
                if weakSelf.myRole?.isEqual("background") ?? false {
                    if let connectedServerPeer = weakSelf.connectedServer {
                        let dict = ["detectedRectangle":detectedRectangle]
                        let data = NSKeyedArchiver.archivedData(withRootObject: dict)
                        
                        do {
                            try weakSelf.multipeerSession.send(data, toPeers: [connectedServerPeer], with: MCSessionSendDataMode.reliable)
                        } catch let error as NSError {
                            print("Error in sending detectedRectangle: \(error.localizedDescription)")
                        }
                    }
                    
                    weakSelf.highlightRectangle(box:detectedRectangle)
                }
                
            }
        }
    }
    
    func highlightRectangle(box: VNRectangleObservation) {
        if let videoLayer = videoLayer {
            let path = CGMutablePath()
            
            let topLeft = videoLayer.layerPointConverted(fromCaptureDevicePoint: box.topLeft)
            let topRight = videoLayer.layerPointConverted(fromCaptureDevicePoint: box.topRight)
            let bottomLeft = videoLayer.layerPointConverted(fromCaptureDevicePoint: box.bottomLeft)
            let bottomRight = videoLayer.layerPointConverted(fromCaptureDevicePoint: box.bottomRight)
            
            path.move(to: topLeft)
            path.addLine(to: topLeft)
            path.addLine(to: topRight)
            path.addLine(to: bottomRight)
            path.addLine(to: bottomLeft)
            path.closeSubpath()
            
            let weakSelf = self
            DispatchQueue.main.async {
                weakSelf.rectangleLayer.path = path
            }
        }
        //        print("TopR \(topRight) \(box.topRight)")
        //        print("TopL \(topLeft) \(box.topLeft)")
        //        print("BotR \(bottomRight) \(box.bottomRight)")
        //        print("BotL \(bottomLeft) \(box.bottomLeft)")
        
        //Core image points are in cartesian (y is going upwards insetead of downwards)
        //        var t = CGAffineTransform(scaleX: 1, y: -1)
        //        t = t.translatedBy(CGAffineTransform(translationX: 0, y: -box.boundingBox.size.height)
        //        let pointUIKit = CGPointApplyAffineTransform(pointCI, t)
        //        let rectUIKIT = CGRectApplyAffineTransform(rectCI, t)
        
        /* APPLY GREEN NOT NEEDED NOW */
        /*
         let perspectiveTransform = CIFilter(name: "CIPerspectiveTransform")!
         
         let w = self.catCIImage!.extent.size.width
         let h = self.catCIImage!.extent.size.height
         
         perspectiveTransform.setValue(CIVector(cgPoint:CGPoint(x: box.topLeft.x * w, y: h * (1 - box.topLeft.y))), forKey: "inputTopLeft")
         perspectiveTransform.setValue(CIVector(cgPoint:CGPoint(x: box.topRight.x * w, y: h * (1 - box.topRight.y))), forKey: "inputTopRight")
         perspectiveTransform.setValue(CIVector(cgPoint:CGPoint(x: box.bottomRight.x * w, y: h * (1 - box.bottomRight.y))), forKey: "inputBottomRight")
         perspectiveTransform.setValue(CIVector(cgPoint:CGPoint(x: box.bottomLeft.x * w, y: h * (1 - box.bottomLeft.y))), forKey: "inputBottomLeft")
         //        perspectiveTransform.setValue(CIVector(cgPoint:box.topLeft.scaled(to: ciSize)), forKey: "inputTopLeft")
         //        perspectiveTransform.setValue(CIVector(cgPoint:box.topRight.scaled(to: ciSize)), forKey: "inputTopRight")
         //        perspectiveTransform.setValue(CIVector(cgPoint:box.bottomRight.scaled(to: ciSize)), forKey: "inputBottomRight")
         //        perspectiveTransform.setValue(CIVector(cgPoint:box.bottomLeft.scaled(to: ciSize)), forKey: "inputBottomLeft")
         perspectiveTransform.setValue(self.catCIImage!.oriented(CGImagePropertyOrientation.downMirrored),
         forKey: kCIInputImageKey)
         
         if let currentFrame = self.currentFrame {
         
         let composite = ChromaKeyFilter()
         composite.inputImage = currentFrame
         composite.backgroundImage = perspectiveTransform.outputImage
         composite.activeColor = CIColor(red: 0, green: 1, blue: 0)
         
         //Apple Chroma (not working)
         //            let composite = CIFilter(name:"ChromaKey") as! ChromaKey
         //
         //            composite.setDefaults()
         //            composite.setValue(perspectiveTransform.outputImage!, forKey: "inputBackgroundImage")
         //            composite.setValue(currentFrame, forKey: "inputImage")
         //
         //            composite.inputCenterAngle = NSNumber(value:120 * Float.pi / 180)
         //            composite.inputAngleWidth = NSNumber(value:45 * Float.pi / 180)
         
         if let compositeImage = composite.outputImage {
         self.imageView.image = UIImage(ciImage:compositeImage)
         }
         }
         */
        /* APPLY GREEN NOT NEEDED NOW */
    }
    
    // MARK: Capture Session
    
    func setupCamera() -> Bool {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = AVCaptureSession.Preset.hd1280x720
        
        // get list of devices; connect to front-facing camera
        guard let videoDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
            let alert = UIAlertController(title: "Fatal error", message: "This device cannot capture video", preferredStyle: UIAlertControllerStyle.alert)
            self.present(alert, animated: true, completion: nil)
            return false
        }
        
        self.configureCameraForHighestFrameRate(device: videoDevice)
        
        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            if !captureSession.canAddInput(input) {
                return false
            }
            
            captureSession.addInput(input)
        } catch let error as NSError {
            let alert = UIAlertController(title: "Fatal error", message: "The video capture input is not working. \(error.localizedDescription)", preferredStyle: UIAlertControllerStyle.alert)
            self.present(alert, animated: true, completion: nil)
            return false
        }
        
        let sampleBufferSerialQueue = DispatchQueue(label: "My_Wizard_Sample_Buffer_Serial_Queue")
        
        let dataOutput = AVCaptureVideoDataOutput()
        
        dataOutput.alwaysDiscardsLateVideoFrames = true
        dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
        dataOutput.setSampleBufferDelegate(self, queue: sampleBufferSerialQueue)
        
        if !captureSession.canAddOutput(dataOutput) {
            return false
        }
        captureSession.addOutput(dataOutput)
        
        //Configure movie writer
        let fileType = AVFileType.mov
        
        
        if let videoSettings = dataOutput.recommendedVideoSettings(forVideoCodecType: AVVideoCodecType.h264, assetWriterOutputFileType: fileType) as? [String:Any] {
            var extendedVideoSettings = videoSettings
            //            extendedVideoSettings[AVVideoCompressionPropertiesKey] = [
            //                AVVideoAverageBitRateKey : ,
            //                AVVideoProfileLevelKey : AVVideoProfileLevelH264Main31, /* Or whatever profile & level you wish to use */
            //                AVVideoMaxKeyFrameIntervalKey :
            //            ]
            
            movieWriter = MovieWriter(extendedVideoSettings)
            movieWriter.delegate = self
        }
        
        captureSession.commitConfiguration()
        
        let weakSelf = self
        //I'm dispatching this in a synchronous way to configure everything before doing any rectangle detection
        DispatchQueue.main.async {
            let previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
            
            previewLayer.connection!.videoOrientation = .landscapeRight
            
            previewLayer.frame = self.view.bounds.insetBy(dx: 0, dy: 100)
            previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
            weakSelf.view.layer.addSublayer(previewLayer)
            
            weakSelf.videoLayer = previewLayer
            
            let outline = CAShapeLayer()
            
            //        outline.frame = CGRect(x: xCord, y: yCord, width: width, height: height)
            outline.lineWidth = 2
            outline.strokeColor = UIColor.red.cgColor
            //            outline.fillColor = UIColor.orange.cgColor
            outline.fillColor = UIColor.clear.cgColor
            
            weakSelf.videoLayer?.addSublayer(outline)
            weakSelf.rectangleLayer = outline
        }
        
        return true
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func configureCameraForHighestFrameRate(device:AVCaptureDevice) {
        var bestFormat:AVCaptureDevice.Format?
        var bestFrameRateRange:AVFrameRateRange?
        
        for format in device.formats {
            for range in format.videoSupportedFrameRateRanges {
                if bestFrameRateRange == nil || (range.maxFrameRate > bestFrameRateRange!.maxFrameRate || range.maxFrameRate <= 60) {
                    bestFormat = format
                    bestFrameRateRange = range
                }
            }
        }
        
        if let bestFormat = bestFormat, let bestFrameRateRange = bestFrameRateRange {
            do {
                try device.lockForConfiguration()
                device.activeFormat = bestFormat
                device.focusMode = .autoFocus //.locked
                device.activeVideoMinFrameDuration = bestFrameRateRange.minFrameDuration
                device.activeVideoMaxFrameDuration = bestFrameRateRange.maxFrameDuration
                device.unlockForConfiguration()
            } catch {
                print("We couldn't lock the device for configuration, keeping the default configuration")
            }
        }
    }
    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if movieWriter.isWriting, let detectedRectangle = self.currentDetectedRectangle {
            if firstCaptureFrameTimeStamp == nil {
                firstCaptureFrameTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            }
            //            presentationTimeStamp = fileFramePresentationTime + firstFrameCaptureTime
            let fileFramePresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let presentationTimeStamp = CMTimeSubtract(fileFramePresentationTime, firstCaptureFrameTimeStamp!)
            
            if let detectedTime = CMTimeCopyAsDictionary(presentationTimeStamp,kCFAllocatorDefault) {
                savedBoxes.updateValue(detectedRectangle, forKey: detectedTime)
            }
        }
        
        movieWriter.process(sampleBuffer: sampleBuffer)
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        //There are two options to obtain the data of the image from the CMSampleBuffer
        
        // (Disabled) Option One, we create our own CGContext and create a CGImage -> UIImage
        //        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags.readOnly)
        //
        //        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
        //        let bitsPerComponent = 8
        //        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        //        let width = CVPixelBufferGetWidth(imageBuffer)
        //        let height = CVPixelBufferGetHeight(imageBuffer)
        //        let colorSpace = CGColorSpaceCreateDeviceRGB()
        //
        //        guard let newContext = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: UInt32(UInt8(CGBitmapInfo.byteOrder32Little.rawValue) |  UInt8(CGImageAlphaInfo.premultipliedFirst.rawValue))) else {
        //            return
        //        }
        //
        //        guard let newImage = newContext.makeImage() else {
        //            return
        //        }
        //
        //        let image = UIImage(cgImage: newImage, scale: 1, orientation: UIImageOrientation.upMirrored)
        //
        //        CVPixelBufferUnlockBaseAddress(imageBuffer,CVPixelBufferLockFlags.readOnly)
        // Option One (End)
        
        // (Enabled) Option Two, we create a CIImage from the CMSampleBuffer and from there the UIImage
        
        //        let cropRect = AVMakeRect(aspectRatio: CGSize(width:320, height:320), insideRect: CGRect(x:0, y:0, width:CVPixelBufferGetWidth(imageBuffer), height:CVPixelBufferGetHeight(imageBuffer)))
        //
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        
        //        let croppedImage = ciImage.cropped(to: cropRect)
        let croppedImage = ciImage
        
        guard let scaleFilter = CIFilter(name: "CILanczosScaleTransform") else {
            return
        }
        scaleFilter.setValue(croppedImage, forKey: "inputImage")
        let reduceFactor = 0.25
        scaleFilter.setValue(reduceFactor, forKey: "inputScale")
        scaleFilter.setValue(1.0, forKey: "inputAspectRatio")
        
        guard let finalImage = scaleFilter.outputImage else {
            return
        }
        
        //Can I just use finalImage.cgImage?
        guard let image = self.cgImageBackedImage(withCIImage:finalImage) else {
            print("cgImageBackedImage failed")
            return
        }
        // Option Two (End)
        
        /*Vision*/
        if !rectangleLocked {
            visionQueue.async {[unowned self] in
                let colorMatrixEffect = CIFilter(name:"CIColorMatrix")!
                
                colorMatrixEffect.setDefaults()
                colorMatrixEffect.setValue(ciImage, forKey: kCIInputImageKey)
                
                colorMatrixEffect.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
                colorMatrixEffect.setValue(CIVector(x: -5, y: 5, z: -5, w: 0), forKey: "inputGVector")
                colorMatrixEffect.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
                colorMatrixEffect.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
                colorMatrixEffect.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
                
                let outputImage = colorMatrixEffect.outputImage!
                
                self.visionDetection(sampleBuffer, outputImage: outputImage)
            }
        }
        /*Vision*/
        
        guard let data = UIImageJPEGRepresentation(image, 0.25) else {
            print("UIImageJPEGRepresentation failed")
            return
        }
        
        self.writeData(data as NSData)
        
        if self.watchConnectivitySession?.isReachable ?? false {
            watchQueue.async {[unowned self] in
                guard let scaleFilter = CIFilter(name: "CILanczosScaleTransform") else {
                    return
                }
                scaleFilter.setValue(finalImage, forKey: "inputImage")
                let scaleFactor = 0.5
                scaleFilter.setValue(scaleFactor, forKey: "inputScale")
                scaleFilter.setValue(1.0, forKey: "inputAspectRatio")
                
                guard let scaledFinalImage = scaleFilter.outputImage else {
                    return
                }
                
                let currentMirroredImage:CIImage
                
                if let currentOverlayImage = self.overlayImage {
                    let scaledOverlay = currentOverlayImage.transformed(by: CGAffineTransform.identity.scaledBy(x: scaledFinalImage.extent.width / currentOverlayImage.extent.width, y: scaledFinalImage.extent.height / currentOverlayImage.extent.height))
                    let overlayFilter = CIFilter(name: "CISourceOverCompositing")!
                    overlayFilter.setValue(scaledFinalImage, forKey: kCIInputBackgroundImageKey)
                    overlayFilter.setValue(scaledOverlay, forKey: kCIInputImageKey)
                    if let obtainedImage = overlayFilter.outputImage {
                        currentMirroredImage = obtainedImage
                    } else {
                        currentMirroredImage = scaledFinalImage
                    }
                } else {
                    currentMirroredImage = scaledFinalImage
                }
                
                guard let image = self.cgImageBackedImage(withCIImage: currentMirroredImage) else {
                    return
                }
                
                if Date().timeIntervalSince(self.lastTimeSent) >= (1 / fps) {
                    if let smallData = UIImageJPEGRepresentation(image, 0.1) {
                        self.watchConnectivitySession?.sendMessageData(smallData, replyHandler: nil, errorHandler: { (error) in
                            print("*** watchConnectivitySession sendMessage error: \(error)")
                        })
                        //                        self.watchConnectivitySession?.sendMessageData(smallData, replyHandler: nil, errorHandler: nil)
                        self.lastTimeSent = Date()
                    }
                }
            }
        }
        //    CGContextRelease(newContext);
        //    CGColorSpaceRelease(colorSpace);
        //    UIImage *image = [[UIImage alloc] initWithCGImage:newImage scale:1 orientation:UIImageOrientationUpMirrored];
        //    CGImageRelease(newImage);
        //    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    }
    
    func cgImageBackedImage(withCIImage ciImage:CIImage) -> UIImage? {
        guard let ref = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let image = UIImage(cgImage: ref, scale: UIScreen.main.scale, orientation: UIImageOrientation.up)
        
        return image
    }
    
    // MARK: Multipeer Streaming
    var serverName:String?
    var peersNamesToStream = Set<String>()
    var peersToStream:[MCPeerID] {
        return self.multipeerSession.connectedPeers.filter { (peer) -> Bool in
            return peersNamesToStream.contains(peer.displayName)
        }
    }
    var connectedServer:MCPeerID? {
        return self.multipeerSession.connectedPeers.first { (peer) -> Bool in
            return serverName?.isEqual(peer.displayName) ?? false
        }
    }
    
    func writeData(_ data:NSData) {
        if isMirrorMode && peersToStream.count < 2 {
            return
        }
        
        for (peer,queue) in zip(self.peersToStream,[streamingQueue1,streamingQueue2]) {
            queue.async {[unowned self] in
                let currentDate = Date()
                //                let streamName = "\(currentDate.description(with: Locale.current)) \(currentDate.timeIntervalSince1970)"
                let streamName = "\(currentDate.timeIntervalSince1970)"
                
                let outputStream:OutputStream
                
                do {
                    outputStream = try self.multipeerSession.startStream(withName: streamName, toPeer: peer)
                } catch let error as NSError {
                    print("Couldn't crete output stream: \(error.localizedDescription)")
                    return
                }
                let outputStreamHandler = OutputStreamHandler(outputStream,owner:self,data: data, queue:queue)
                
                DispatchQueue.main.async {
                    outputStream.delegate = outputStreamHandler
                    outputStream.schedule(in: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
                    outputStream.open()
                }
            }
        }
    }
    
    // MARK: MCSessionDelegate
    
    // Remote peer changed state.
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case MCSessionState.connecting:
            print("connecting with peerID \(peerID)")
            break
        case MCSessionState.connected:
            print("connected with peerID \(peerID)")
            let currentPeersToStreamCount = peersToStream.count
            if (!isMirrorMode && currentPeersToStreamCount > 0) || (isMirrorMode && currentPeersToStreamCount >= 2) {
                print("stopAdvertisingPeer")
                serviceAdvertiser.stopAdvertisingPeer()
            }
            break
        case MCSessionState.notConnected:
            print("notConnected with peerID \(peerID)")
            if let peerNameIndex = peersNamesToStream.index(of: peerID.displayName) {
                peersNamesToStream.remove(at: peerNameIndex)
            }
            if serverName?.isEqual(peerID.displayName) ?? false {
                serverName = nil
                myRole = nil
                if peersToStream.isEmpty {
                    //If there is no server and peers, let's clean
                    movieWriter.stopWriting()
                    isStreaming = true
                    
                    for outputStreamHandler in outputStreamHandlers {
                        outputStreamHandler.close()
                    }
                }
            }
            if peersToStream.isEmpty || serverName == nil {
                print("startAdvertisingPeer")
                serviceAdvertiser.startAdvertisingPeer()
            }
            break
        }
    }
    
    // Received data from remote peer.
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let receivedDict = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String:Any] {
            for (messageType, value) in receivedDict {
                switch messageType {
                case "role":
                    myRole = value as? String
                    break
                case "startRecordingDate":
                    if let startRecordingDate = value as? Date {
                        recordStartedAt = startRecordingDate.timeIntervalSince1970
                        let timer = Timer(fire: startRecordingDate, interval: 0, repeats: false, block: { (timer) in
                            self.savedBoxes.removeAll()
                            self.firstCaptureFrameTimeStamp = nil
                            self.movieWriter.startWriting()
                            print("START RECORDING!!!! NOW! \(Date().timeIntervalSince1970)")
                            timer.invalidate()
                        })
                        RunLoop.main.add(timer, forMode: RunLoopMode.commonModes)
                    }
                    break
                case "stopRecording":
                    self.movieWriter.stopWriting()
                    if self.myRole?.isEqual("background") ?? false {
                        if let connectedServerPeer = connectedServer {
                            let dict = ["savedBoxes":savedBoxes]
                            let data = NSKeyedArchiver.archivedData(withRootObject: dict)
                            
                            do {
                                try self.multipeerSession.send(data, toPeers: [connectedServerPeer], with: MCSessionSendDataMode.reliable)
                            } catch let error as NSError {
                                print("Error in sending savedBoxes: \(error.localizedDescription)")
                            }
                        }
                    }
                    
                    break
                case "mirrorMode":
                    isMirrorMode = value as! Bool
                    
                    if isMirrorMode {
                        print("startAdvertisingPeer because isMirrorMode")
                        serviceAdvertiser.startAdvertisingPeer()
                    }
                    break
                case "streaming":
                    isStreaming = value as! Bool
                    break
                default:
                    print("Unrecognized message in receivedDict \(receivedDict)")
                }
            }
            
        }
        
    }
    
    
    // Received a byte stream from remote peer.
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        let weakSelf = self
        
        mirrorQueue.async {
            weakSelf.readDataToInputStream(stream, owner:self, queue: mirrorQueue) { ciImage in
                weakSelf.overlayImage = ciImage
            }
        }
    }
    
    func readDataToInputStream(_ iStream:InputStream,owner:InputStreamOwnerDelegate,queue:DispatchQueue,completion:((CIImage?)->())?) {
        let inputStreamHandler = InputStreamHandler(iStream,owner:owner,queue: queue)
        
        inputStreamHandler.completionBlock = completion
        
        iStream.open()
    }
    
    // Start receiving a resource from remote peer.
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        
        print("didStartReceivingResourceWithName")
    }
    
    
    // Finished receiving a resource from remote peer and saved the content
    // in a temporary location - the app is responsible for moving the file
    // to a permanent location within its sandbox.
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        print("didFinishReceivingResourceWithName")
    }
    
    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        print("multipeer session didReceiveCertificate")
        certificateHandler(true)
    }
    
    // MARK: MCNearbyServiceAdvertiserDelegate
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        
        if let data = context, let stringData = String(data: data, encoding: .utf8), ["MONTAGE_CANVAS","MONTAGE_MIRROR"].contains(stringData) {
            if stringData == "MONTAGE_CANVAS" {
                //                if serverName?.isEqual(peerID.displayName) ?? false {
                //                    return
                //                }
                serverName = peerID.displayName
            } else {
                //                if peersNamesToStream.contains(peerID.displayName) {
                //                    return
                //                }
                print("MONTAGE_MIRROR \(peerID.displayName)")
            }
            peersNamesToStream.insert(peerID.displayName)
            print("invitationHandler true \(peerID.displayName)")
            invitationHandler(true,multipeerSession)
        } else {
            print("invitationHandler false \(peerID.displayName)")
            invitationHandler(false,multipeerSession)
        }
    }
    
    // MARK: Actions
    
    @IBAction func lockPressed(_ sender:UISwitch) {
        rectangleLocked = sender.isOn
    }
    
    // MARK: MovieWriterDelegate
    
    func didWriteMovie(atURL outputURL: URL) {
        print("didWriteMovie \(outputURL)")
        isStreaming = false
        
        guard let serverPeer = connectedServer else {
            print("Cannot send movie, there is no server connected")
            return
        }
        multipeerSession.sendResource(at: outputURL, withName: "MONTAGE_CAM_MOVIE", toPeer: serverPeer) { (error) in
            guard let error = error else {
                print("Movie sent succesfully!")
                return
            }
            print("Failed to send movie \(outputURL): \(error.localizedDescription)")
            
        }
        //        let cloudKitAsset = CKAsset(fileURL: outputURL)
        //
        //        publicDatabase.fetch(withRecordID: CKRecordID(recordName:"115")) { (result, error) in
        //            if let error = error {
        //                // Error handling for failed fetch from public database
        //                print("CloudKit could not fetch video: \(error.localizedDescription)")
        //                return
        //            }
        //
        //            guard let videoRecord = result else {
        //                print("CloudKit does not have a video with that recordName")
        //                return
        //            }
        //
        //            //We load the asset
        //            videoRecord["backgroundMovie"] = cloudKitAsset
        //
        //            self.publicDatabase.save(videoRecord) {
        //                (record, error) in
        //                if let error = error {
        //                    // Insert error handling
        //                    return
        //                }
        //                // Insert successfully saved record code
        //            }
        //        }
    }
    
}

