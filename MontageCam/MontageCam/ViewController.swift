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
import Streamer
import VideoToolbox

let visionQueue = DispatchQueue.global(qos: .userInteractive) //concurrent
let mirrorQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_mirror_queue", qos: DispatchQoS.userInteractive)
let streamerQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_streamer_queue", qos: DispatchQoS.userInteractive)
let senderQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_sender_queue")
let captureOutputQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_capture-output_queue")

let fps = 30.0

class ViewController: UIViewController, MovieWriterDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, VideoEncoderDelegate, OutputStreamerDelegate {
    
    var initialChunkSPS_PPS:Data? {
        didSet {
            if let firstChunk = initialChunkSPS_PPS {
                let weakSelf = self
                streamerQueue.async {
                    for streamer in weakSelf.outputStreamers {
                        streamer.initialChunk = Data(firstChunk)
                    }
                }
            }
        }
    }
    
    var formatDescription:CMFormatDescription? = nil {
        didSet {
            guard let aFormatDescription = formatDescription else {
                return
            }
            
            guard !CMFormatDescriptionEqual(aFormatDescription, oldValue) else {
                return
            }
            
            didSetFormatDescriptionDo(video: aFormatDescription)
        }
    }
    
    lazy var encoder: H264Encoder = {
        let encoder = H264Encoder()
        encoder.expectedFPS = fps
        encoder.width = 480
        encoder.height = 272
        encoder.bitrate = 160 * 1024
        encoder.scalingMode = kVTScalingMode_Trim as String
        encoder.maxKeyFrameIntervalDuration = 1.0 //in seconds <--- change this for better performance, e.g., 0.2 (200ms) between each KeyFrame
        encoder.maxKeyFrameInterval = 15//in amount of frames, after X frames we should generate a KeyFrame
        encoder.profileLevel = kVTProfileLevel_H264_Baseline_3_1 as String
        encoder.delegate = self
        return encoder
    }()
    
    var myRole:MontageRole?
    
    var recordStartedAt:TimeInterval?
    var currentDetectedRectangle:VNRectangleObservation?
    var firstCaptureFrameTimeStamp:CMTime?
    
    var savedBoxes = [NSDictionary:VNRectangleObservation]()
    var mirrorPeer:MCPeerID? = nil
    var isStreaming:Bool = false {
        didSet {
            if isStreaming {
                if !captureSession.isRunning {
                    captureSession.startRunning()
                }
            } else {
                if captureSession.isRunning {
                    captureSession.stopRunning()
                    stopOutputStreamers()
                }
            }
        }
    }
    
    func stopOutputStreamers() {
        let weakSelf = self
        streamerQueue.async {
            for streamer in weakSelf.outputStreamers {
                streamer.close()
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
    
    let myContainer = CKContainer(identifier: "iCloud.fr.lri.ex-situ.MontageCanvas")
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
    var outputStreamers = [OutputStreamer]()
    var inputStreamers = [InputStreamer]()
    
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
        return self.createServiceAdvertiser()
    }()
    
    func createServiceAdvertiser() -> MCNearbyServiceAdvertiser {
        let role:MontageRole
        
        if let currentRole = myRole {
            role = currentRole
        } else {
            role = .cam
        }
        
        let info = ["role":String(describing:role.rawValue)]
        let _serviceAdvertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: info, serviceType: serviceType)
        _serviceAdvertiser.delegate = self
        
        return _serviceAdvertiser
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        //        cloudKitInitialize()
        
        if self.setupCamera() {
            isStreaming = true //This starts the captureSession
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(appWillWillEnterForeground), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillTerminate), name: NSNotification.Name.UIApplicationWillTerminate, object: nil)
        
        //        setupVisionDetection()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("viewWillAppear")
        if captureSession.isRunning {
            serviceAdvertiser.startAdvertisingPeer()
            print("initial startAdvertisingPeer")
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
                
                if let aRole = weakSelf.myRole, aRole == .userCam {
                    weakSelf.sendMessageToServer(dict: ["detectedRectangle":detectedRectangle])
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
        
        let dataOutput = AVCaptureVideoDataOutput()
        
        dataOutput.alwaysDiscardsLateVideoFrames = true
        dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
        dataOutput.setSampleBufferDelegate(self, queue: captureOutputQueue)
        
        if !captureSession.canAddOutput(dataOutput) {
            return false
        }
        captureSession.addOutput(dataOutput)
        
        //Configure movie writer
        let fileType = AVFileType.mov
        
        
        if let videoSettings = dataOutput.recommendedVideoSettings(forVideoCodecType: AVVideoCodecType.h264, assetWriterOutputFileType: fileType) as? [String:Any] {
            let extendedVideoSettings = videoSettings
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
        let maxFPS = 30.0
        
        for format in device.formats {
            for range in format.videoSupportedFrameRateRanges {
                if bestFrameRateRange == nil || (range.maxFrameRate > bestFrameRateRange!.maxFrameRate || range.maxFrameRate <= maxFPS) {
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
        
        /*Vision*/
        if !rectangleLocked {
            visionQueue.async {[unowned self] in
                let ciImage = CIImage(cvImageBuffer: imageBuffer)
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
        
        encoder.encodeImageBuffer(
            imageBuffer,
            presentationTimeStamp: sampleBuffer.presentationTimeStamp,
            duration: sampleBuffer.duration
        )
        
        //    CGContextRelease(newContext);
        //    CGColorSpaceRelease(colorSpace);
        //    UIImage *image = [[UIImage alloc] initWithCGImage:newImage scale:1 orientation:UIImageOrientationUpMirrored];
        //    CGImageRelease(newImage);
        //    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    }
    
    // MARK: Multipeer Streaming
    private var _serverPeer:MCPeerID?
    var serverPeer:MCPeerID? {
        get {
            return senderQueue.sync { _serverPeer }
        }
        set (newServerPeer) {
            return senderQueue.sync { _serverPeer = newServerPeer }
        }
    }
    
    // MARK: MCSessionDelegate
    
    // Remote peer changed state.
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case MCSessionState.connecting:
            print("connecting with peerID \(peerID)")
        case MCSessionState.connected:
            print("connected with peerID \(peerID)")
            
            let weakSelf = self
            streamerQueue.async {
                var shouldStartEncoder = false
                
                if weakSelf.outputStreamers.isEmpty {
                    shouldStartEncoder = true
                }
                
                if peerID.isEqual(weakSelf.serverPeer) || peerID.isEqual(weakSelf.mirrorPeer) {
                    if peerID.isEqual(weakSelf.mirrorPeer) {
                        print("IS MIRRORING")
                    }
                    let id = weakSelf.outputStreamers.count + 1
                    do {
                        let outputStream = try weakSelf.multipeerSession.startStream(withName: "videoStreamPruebita \(id) \(Date())", toPeer: peerID)
                        print("Created MultipeerSession Stream with peer: \(peerID.displayName)")
                        
                        let newOutputStreamer = OutputStreamer(peerID,outputStream:outputStream,initialChunk:weakSelf.initialChunkSPS_PPS)
                        newOutputStreamer.delegate = weakSelf
                        weakSelf.outputStreamers.append(newOutputStreamer)
                        
                        if shouldStartEncoder {
                            weakSelf.encoder.startRunning()
                        }
                    } catch let error as NSError {
                        print("Couldn't create output stream \(id): \(error.localizedDescription)")
                    }
                }
                
                if peerID.isEqual(weakSelf.serverPeer) {
                    print("stopAdvertisingPeer")
                    weakSelf.serviceAdvertiser.stopAdvertisingPeer()
                }
            }
            
        case MCSessionState.notConnected:
            print("notConnected with peerID \(peerID)")
            let weakSelf = self
            
            streamerQueue.async {
                if let unproperlyDisconnectedDestination = weakSelf.outputStreamers.first(where: { $0.peerID == peerID} ) {
                    unproperlyDisconnectedDestination.close()
                }
                
                if peerID.isEqual(weakSelf.serverPeer) {
                    weakSelf.serverPeer = nil
                    print("startAdvertisingPeer")
                    weakSelf.serviceAdvertiser.startAdvertisingPeer()
                }
                
                if peerID.isEqual(weakSelf.mirrorPeer) {
                    weakSelf.mirrorPeer = nil
                }
            }
            
            
            
        }
    }
    
    func sendMessageToServer(dict:[String:Any?]) {
        let weakSelf = self
        senderQueue.async {
            if let connectedServerPeer = weakSelf._serverPeer {
                weakSelf.sendMessage(peerID: connectedServerPeer, dict: dict)
            }
        }
    }
    
    func sendMessage(peerID:MCPeerID,dict:[String:Any?]) {
        let data = NSKeyedArchiver.archivedData(withRootObject: dict)
        
        do {
            try multipeerSession.send(data, toPeers: [peerID], with: .reliable)
        } catch let error as NSError {
            print("Could not send dict message: \(error.localizedDescription)")
        }
    }
    
    // Received data from remote peer.
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let receivedDict = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String:Any] {
            for (messageType, value) in receivedDict {
                switch messageType {
                case "role":
                    myRole = MontageRole(rawValue:value as! Int)
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
                case "stopRecording":
                    self.movieWriter.stopWriting()
                    if let aRole = self.myRole, aRole == .userCam {
                        sendMessageToServer(dict: ["savedBoxes":savedBoxes])
                    }
                case "mirrorMode":
                    mirrorPeer = value as? MCPeerID
                case "ARE_YOU_WIZARD_CAM":
                    if let aRole = self.myRole, aRole == .wizardCam {
                        sendMessage(peerID: peerID, dict: ["I_AM_WIZARD_CAM":true])
                    }
                case "streaming":
                    isStreaming = value as! Bool
                default:
                    print("Unrecognized message in receivedDict \(receivedDict)")
                }
            }
            
        }
        
    }
    
    
    // Received a byte stream from remote peer.
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("didReceive stream - nothing to be done")
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
        
        if let data = context, let stringData = String(data: data, encoding: .utf8), "MONTAGE_CANVAS" == stringData || (myRole == .wizardCam && "MONTAGE_MIRROR" == stringData) {
            serverPeer = peerID
            
            print("invitationHandler true \(peerID.displayName) with stringData = \(stringData)")
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
        
        let weakSelf = self
        senderQueue.async {
            guard let serverPeer = weakSelf._serverPeer else {
                print("Cannot send movie, there is no server connected")
                return
            }
            weakSelf.multipeerSession.sendResource(at: outputURL, withName: "MONTAGE_CAM_MOVIE", toPeer: serverPeer) { (error) in
                guard let error = error else {
                    print("Movie sent succesfully!")
                    return
                }
                print("Failed to send movie \(outputURL): \(error.localizedDescription)")
                
            }
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
    
    // MARK: Deinitialization of Streamers
    
    @objc func appWillWillEnterForeground(_ notification:Notification) {
        print("appWillWillEnterForeground")
        serviceAdvertiser.startAdvertisingPeer()
        print("startAdvertisingPeer")
    }
    
    @objc func appWillResignActive(_ notification:Notification) {
        print("appWillResignActive")
        
        stopOutputStreamers()
        
        for streamer in outputStreamers {
            streamer.close()
        }
        
        serviceAdvertiser.stopAdvertisingPeer()
        print("stopAdvertisingPeer")
    }
    
    @objc func appWillTerminate(_ notification:Notification) {
        print("appWillTerminate") //I think appWillResignActive is called before
        
        stopOutputStreamers()
        for streamer in inputStreamers {
            streamer.close()
        }
        
        serviceAdvertiser.stopAdvertisingPeer()
        print("stopAdvertisingPeer")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        print("viewWillDisappear")
        super.viewWillDisappear(animated)
        
        stopOutputStreamers()
        
        for streamer in inputStreamers {
            streamer.close()
        }
        serviceAdvertiser.stopAdvertisingPeer()
        print("stopAdvertisingPeer")
    }
    
    // VideoEncoderDelegate
    
    func didSetFormatDescription(video formatDescription: CMFormatDescription?) {
        //        print("**** didSetFormatDescription \(Date().timeIntervalSinceReferenceDate)")
        
        self.formatDescription = formatDescription
    }
    
    func sampleOutput(video sampleBuffer: CMSampleBuffer) {
        //        guard let videoData = sampleBuffer.dataBuffer?.data else {
        //            return
        //        }
        
        /*var outputBuffer: Data = Data([0x0,0x0,0x0,0x1])
         var headerInfo:Int = videoData.count
         print("headerInfo length \(headerInfo)")
         //        var lengthHeaderSize = MemoryLayout<Int>.size
         
         withUnsafeBytes(of: &headerInfo) { bytes in
         for byte in bytes {
         print("byte \(byte)")
         
         outputBuffer.append(byte)
         }
         }
         
         outputBuffer.append(videoData)
         
         accumulatedBuffers.append(outputBuffer)*/
        
        //        print("**** sampleOutput \(Date().timeIntervalSinceReferenceDate)")
        sampleOutputDo(video: sampleBuffer)
    }
    
    private func didSetFormatDescriptionDo(video formatDescription:CMFormatDescription) {
        
        var sampleData = Data()
        //         let formatDesrciption :CMFormatDescriptionRef = CMSampleBufferGetFormatDescription(sampleBuffer!)!
        //        let sps:UnsafeMutablePointer<UnsafePointer<UInt8>?>? = UnsafeMutablePointer<UnsafePointer<UInt8>?>.allocate(capacity: 1)
        var sps: UnsafePointer<UInt8>? = nil
        var pps: UnsafePointer<UInt8>? = nil
        
        var spsLength:Int = 0
        var ppsLength:Int = 0
        var spsCount:Int = 0
        var ppsCount:Int = 0
        
        var err : OSStatus
        err = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, 0, &sps, &spsLength, &spsCount, nil )
        if (err != noErr) {
            NSLog("An Error occured while getting h264 parameter 0")
        }
        err = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, 1, &pps, &ppsLength, &ppsCount, nil )
        if (err != noErr) {
            NSLog("An Error occured while getting h264 parameter 1")
        }
        
        let naluStart:[UInt8] = [0x00, 0x00, 0x00, 0x01]
        sampleData.append(naluStart, count: naluStart.count)
        if let sps = sps {
            //            print("SPS? appended buffer for nalu type \(sps.pointee & 0x1F)")
            
            sampleData.append(sps, count: spsLength)
        }
        sampleData.append(naluStart, count: naluStart.count)
        if let pps = pps {
            //            print("PPS? appended buffer for nalu type \(pps.pointee & 0x1F)")
            
            sampleData.append(pps, count: ppsLength)
        }
        
        //        lockQueue.async { [unowned self] in
        self.initialChunkSPS_PPS = sampleData
        //        }
    }
    
    //
    private func sampleOutputDo(video sampleBuffer: CMSampleBuffer) {
        //        print("get slice data! \(Date())") // \(sampleBuffer)")
        // todo : write to h264 file
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("Could not create blockBuffer from sampleBuffer")
            return
        }
        
        var totalLength:Int = 0
        var lengthAtOffset:Int = 0
        var unwrappedDataPointer: UnsafeMutablePointer<Int8>? = nil
        
        let status = CMBlockBufferGetDataPointer(blockBuffer, 0, &lengthAtOffset, &totalLength, &unwrappedDataPointer)
        
        guard status == noErr else {
            let errorMessage = SecCopyErrorMessageString(status, nil) as String?
            print("Error in CMBlockBufferGetDataPointer: \(errorMessage ?? "no description")")
            return
        }
        
        guard let dataPointer = unwrappedDataPointer else {
            print("Error in CMBlockBufferGetDataPointer, unwrappedDataPointer is nil")
            return
        }
        
        var bufferOffset = 0
        let AVCCHeaderLength = 4
        
        var chunk = Data()
        
        while bufferOffset < totalLength - AVCCHeaderLength {
            var NALUnitLength:UInt32 = 0
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength)
            
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength)
            
            var naluStart:[UInt8] = [0x00,0x00,0x00,0x01]
            let buffer = NSMutableData()
            buffer.append(&naluStart, length: naluStart.count)
            buffer.append(dataPointer + bufferOffset + AVCCHeaderLength, length: Int(NALUnitLength))
            //            let naluType = dataPointer.advanced(by: bufferOffset + AVCCHeaderLength).pointee & 0x1F
            //            print("offset \(bufferOffset) for nalu type \(naluType)")
            chunk.append(buffer as Data)
            
            bufferOffset += AVCCHeaderLength + Int(NALUnitLength)
        }
        
        let weakSelf = self
        streamerQueue.async {
            for outputStreamer in weakSelf.outputStreamers {
//                print("Sending chunk to \(outputStreamer.peerID.displayName)")
                outputStreamer.sendData(chunk)
            }
        }
        
    }
    
    //WriteDestinationDelegate
    func didClose(streamer: OutputStreamer) {
        let weakSelf = self
        streamerQueue.async {
            if let disconnectedStreamerIndex = weakSelf.outputStreamers.index(of:streamer) {
                weakSelf.outputStreamers.remove(at: disconnectedStreamerIndex)
                
                if weakSelf.outputStreamers.isEmpty {
                    captureOutputQueue.async {
                        weakSelf.encoder.stopRunning()
                    }
                }
            }
        }
    }
    
}

