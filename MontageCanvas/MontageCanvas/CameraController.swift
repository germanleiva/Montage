//
//  CameraController.swift
//  Montage
//
//  Created by Germán Leiva on 08/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import AVFoundation
import Vision
import MultipeerConnectivity
import CloudKit
//import TCCore
//import TCMask
import Streamer
import GLKit
import MBProgressHUD

let STATUS_KEYPATH  = "status"
let RATE_KEYPATH  = "rate"

let REFRESH_INTERVAL = Float64(0.5)
let fps = 30.0

let streamerQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.streamer_queue", qos: DispatchQoS.userInteractive)
let mirrorQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_mirror_queue", qos: DispatchQoS.userInteractive)
let drawingQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.drawing_queue", qos: DispatchQoS.userInteractive)

let deviceScale = UIScreen.main.scale

class CameraController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate, InputStreamerDelegate, OutputStreamerDelegate {
//    let dataSource = TierCollectionDataSource()
//    @IBOutlet weak var tiersCollectionView:UICollectionView! {
//        didSet {
//            tiersCollectionView.delegate = self
//            tiersCollectionView.dataSource = dataSource
//        }
//    }
    var palettePopoverPresentationController:UIPopoverPresentationController?
    
    lazy var removeGreenFilter = {
        return colorCubeFilterForChromaKey(hueAngle: 120)
    }()
    
    func RGBtoHSV(r : Float, g : Float, b : Float) -> (h : Float, s : Float, v : Float) {
        var h : CGFloat = 0
        var s : CGFloat = 0
        var v : CGFloat = 0
        let col = UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
        col.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
        return (Float(h), Float(s), Float(v))
    }
    
    func colorCubeFilterForChromaKey(hueAngle: Float) -> CIFilter {
        
        let hueRange: Float = 60 // degrees size pie shape that we want to replace
        let minHueAngle: Float = (hueAngle - hueRange/2.0) / 360
        let maxHueAngle: Float = (hueAngle + hueRange/2.0) / 360
        
        let size = 64
        var cubeData = [Float](repeating: 0, count: size * size * size * 4)
        var rgb: [Float] = [0, 0, 0]
        var hsv: (h : Float, s : Float, v : Float)
        var offset = 0
        
        for z in 0 ..< size {
            rgb[2] = Float(z) / Float(size) // blue value
            for y in 0 ..< size {
                rgb[1] = Float(y) / Float(size) // green value
                for x in 0 ..< size {
                    
                    rgb[0] = Float(x) / Float(size) // red value
                    hsv = RGBtoHSV(r: rgb[0], g: rgb[1], b: rgb[2])
                    // the condition checking hsv.s may need to be removed for your use-case
                    let alpha: Float = (hsv.h > minHueAngle && hsv.h < maxHueAngle && hsv.s > 0.5) ? 0 : 1.0
                    
                    cubeData[offset] = rgb[0] * alpha
                    cubeData[offset + 1] = rgb[1] * alpha
                    cubeData[offset + 2] = rgb[2] * alpha
                    cubeData[offset + 3] = alpha
                    offset += 4
                }
            }
        }
        let data = cubeData.withUnsafeBufferPointer { Data(buffer: $0) }
        
        let colorCube = CIFilter(name: "CIColorCube", withInputParameters: [
            "inputCubeDimension": size,
            "inputCubeData": data as NSData
            ])
        return colorCube!
    }

    var prototypeTimeline:TimelineViewController?
    var backgroundTimeline:TimelineViewController?
    
    var isMirrorMode = false

    var lastTimeSent = Date()
    // MARK: Streaming Multipeer
    
    // MARK: OutputStreamerDelegate
    func didClose(streamer: OutputStreamer) {
        if outputStreamerForMirror == streamer {
            print("didClose outputStreamerForMirror")
            outputStreamerForMirror = nil
        }
    }
    
//    var outputStreamers = [OutputStreamer]()
    var outputStreamerForMirror:SimpleOutputStreamer?
    
    // MARK: InputStreamerDelegate
    var userCamStreamer:InputStreamer?
    var wizardCamStreamer:InputStreamer?
    
    func inputStreamer(_ streamer: InputStreamer, decodedImage ciImage: CIImage) {
        let weakSelf = self
        
        if streamer == userCamStreamer {
            streamerQueue.async {
                weakSelf.backgroundCameraFrame = ciImage
            }
            return
        }
        if streamer == wizardCamStreamer {
            DispatchQueue.main.async {
                weakSelf.snapshotSketchOverlay(layers: [weakSelf.prototypeCanvasView.canvasLayer],size: weakSelf.prototypeCanvasView.frame.size)
            }
    
            streamerQueue.async {
                weakSelf.prototypeCameraFrame = ciImage
                
                //MIRROR
                if let _ = weakSelf.mirrorPeer {
                    
                    if Date().timeIntervalSince(weakSelf.lastTimeSent) >= (1 / fps) {
                        mirrorQueue.async {
                            if weakSelf.sketchOverlay == nil {
                                return
                            }
                            
                            var overlay = weakSelf.sketchOverlay!
                            
                            //Reduce the overlay drastically
                            guard let scaleFilter = CIFilter(name: "CILanczosScaleTransform") else {
                                return
                            }
                            scaleFilter.setValue(overlay, forKey: "inputImage")
                            let scaleFactor = 0.25
                            scaleFilter.setValue(scaleFactor, forKey: "inputScale")
                            scaleFilter.setValue(1.0, forKey: "inputAspectRatio")
                            
                            guard let scaledFinalImage = scaleFilter.outputImage else {
                                return
                            }
                            overlay = scaledFinalImage
                            
                            guard let image = weakSelf.cgImageBackedImage(withCIImage: overlay) else {
                                print("Could not build overly image to mirror")
                                return
                            }
                            
                            DispatchQueue.main.async {
                                guard let data = UIImagePNGRepresentation(image) else {
//                                guard let data = UIImageJPEGRepresentation(image, 0.25) else {
                                    print("Could not build data to mirror")
                                    return
                                }
                                
                                var dataToSend = data
                                dataToSend.append(simpleSepdata)
                                
                                weakSelf.outputStreamerForMirror?.sendData(dataToSend)
                                print("Sent sketches, count \(dataToSend.count)")
                                
                                weakSelf.lastTimeSent = Date()
                            }
                        }
                    }
                }
            }
            
        }

    }
    func didClose(_ streamer: InputStreamer) {
        if streamer == userCamStreamer {
            userCamStreamer = nil
            print("*** didClose userCamStreamer")
        }
        
        if streamer == wizardCamStreamer {
            wizardCamStreamer = nil
            print("*** didClose wizardCamStreamer")
        }
    }
    
//    let persistentContainer = (UIApplication.shared.delegate as! AppDelegate).persistentContainer
    let coreDataContext = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext

    var videoModel:Video!
    
    //AVPlaying
    var prototypeComposition:AVMutableComposition?
    var backgroundComposition:AVMutableComposition?
    
    @IBOutlet weak var recordingLabel:UILabel!
    @IBOutlet weak var modalNavigationItem:UINavigationItem!
    @IBOutlet weak var recordingIndicator:UILabel!
    @IBOutlet weak var recordingControls:UISegmentedControl! {
        didSet {
            recordingControls.isHidden = true
        }
    }

    @IBOutlet weak var saveButton:UIBarButtonItem!
    @IBOutlet weak var playButton:UIButton!
    @IBOutlet weak var playButtonContainer:UIBarButtonItem!
    @IBOutlet weak var scrubberButtonItem:UIBarButtonItem!
    @IBOutlet weak var scrubberSlider:UISlider!
    @IBOutlet weak var prototypeProgressBar:UIProgressView!
    @IBOutlet weak var backgroundProgressBar:UIProgressView!
    
    var periodicTimeObserver:AnyObject? = nil
    var itemEndObserver:NSObjectProtocol? = nil

    private static var observerContext = 0
    
    var displayLink:CADisplayLink?
    
    var prototypePlayerItem:AVPlayerItem?
    var prototypePlayer:AVPlayer!
    
    @IBOutlet weak var prototypePlayerView:VideoPlayerView!

    var backgroundPlayerItem:AVPlayerItem?
    var backgroundPlayer:AVPlayer!
    
    var lastPrototypePixelBuffer:CVPixelBuffer?
    let prototypeVideoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value: kCVPixelFormatType_32BGRA)])
    let backgroundVideoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value: kCVPixelFormatType_32BGRA)])
    
    // CloudKit
    let videoRecordID = CKRecordID(recordName: "115")
    lazy var videoRecord:CKRecord = {
        let videoRecord = CKRecord(recordType: "Video", recordID: videoRecordID)
        videoRecord["isRecording"] = NSNumber(value: true)
        return videoRecord
    }()
    let publicDatabase = CKContainer.default().publicCloudDatabase
    
    var sketchOverlay:CIImage? = nil
    
//    lazy var recordingCanvasViewManager = {
//        return RecordingCanvasViewManager(controller: self)
//    }()
//    lazy var playbackCanvasViewManager = {
//        return PlaybackCanvasViewManager(controller: self)
//    }()
    
    //POP
    lazy var canvasControllerMode:CanvasControllerMode = {
        CanvasControllerLiveMode(controller: self)
    }()
    
    @IBOutlet weak var prototypeCanvasView:CanvasView! {
        didSet {
            prototypeCanvasView.videoTrack = videoModel.prototypeTrack!
            prototypeCanvasView.delegate = self
        }
    }
    @IBOutlet weak var prototypePlayerCanvasView:CanvasView! {
        didSet {
            prototypePlayerCanvasView.videoTrack = videoModel.prototypeTrack!
            prototypePlayerCanvasView.delegate = self
        }
    }
    
    @IBOutlet weak var backgroundCanvasView:CanvasView! {
        didSet {
            backgroundCanvasView.videoTrack = videoModel.backgroundTrack!
            backgroundCanvasView.delegate = self
        }
    }
    @IBOutlet weak var backgroundPlayerCanvasView:CanvasView! {
        didSet {
            backgroundPlayerCanvasView.videoTrack = videoModel.backgroundTrack!
            backgroundPlayerCanvasView.delegate = self
        }
    }
    var backgroundPlayerSyncLayer:AVSynchronizedLayer?
    
    var box = VNRectangleObservation(boundingBox: CGRect.zero)
    
//    @IBOutlet weak var playerView:UIView!
    @IBOutlet weak var backgroundFrameImageView: GLKView! {
        didSet {
            backgroundFrameImageView.context = eaglContext
        }
    }
    @IBOutlet weak var prototypeFrameImageView: GLKView! {
        didSet {
            prototypeFrameImageView.context = eaglContext
        }
    }
    
    // MARK: Multipeer
//    let localPeerID = MCPeerID.reusableInstance(withDisplayName: UIDevice.current.name)
    let localPeerID = MCPeerID(displayName: UIDevice.current.name)
    lazy var multipeerSession:MCSession = {
        let _session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .none)
        _session.delegate = self
        return _session
    }()
    
    lazy var browser:MCNearbyServiceBrowser = {
        let _browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: "multipeer-video")
        _browser.delegate = self
        return _browser
    }()
    
    var _peersRoles = [MCPeerID:MontageRole]()
    
    func update(role:MontageRole,forPeer peerID:MCPeerID) {
        _peersRoles.updateValue(role,forKey:peerID)
    }
    
    func role(forPeer peerID:MCPeerID) -> MontageRole? {
        return _peersRoles[peerID]
    }
    
    func removeRole(forPeer peerID:MCPeerID) {
        _peersRoles.removeValue(forKey: peerID)
    }
    
    let countDownTimeInterval:TimeInterval = 3.0
    var syncTime:Date?
    
    var userCamPeer:MCPeerID?
    var wizardCamPeer:MCPeerID?
    var mirrorPeer:MCPeerID?
    
    var cams:[MCPeerID] {
        var cams = [MCPeerID]()
        if let userCam = userCamPeer {
            cams.append(userCam)
        }
        if let wizardCam = wizardCamPeer {
            cams.append(wizardCam)
        }
        return cams
    }
    
    // MARK: Properties

    lazy var eaglContext:EAGLContext = {
        guard let context = EAGLContext(api: EAGLRenderingAPI.openGLES2) else {
            print("Fatal Error: could not create openGLContext")
            abort()
        }
        return context
    }()
    
    var ciContext:CIContext?
    var backgroundCameraFrame:CIImage?
    var prototypeCameraFrame:CIImage?
    
    // MARK: AVFoundation variables
    
    var isUserOverlayActive = false

    //POP
//    lazy var videoDataOutput:AVCaptureVideoDataOutput = {
//        let deviceOutput = AVCaptureVideoDataOutput()
//        deviceOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
//        deviceOutput.setSampleBufferDelegate(self, queue: streamerQueue)
//        return deviceOutput
//    }()
    
    var activeVideoInput:AVCaptureDeviceInput?
        
    let videoDimensions = CMVideoDimensions(width: 1920, height: 1080)
    
    // MARK: Initializers
    
    required init?(coder aDecoder: NSCoder) {
        //initialize something
        super.init(coder: aDecoder)
    }
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        //initialize something
        super.init(nibName:nibNameOrNil, bundle:nibBundleOrNil)
    }
    
    deinit {
        print("^^^^^^ I actually did deinit")
    }
    
    func close() {
        stopCamsStreaming()

        browser.stopBrowsingForPeers()
//        browser.delegate = nil
        
        userCamStreamer?.close()
//        userCamStreamer = nil
        wizardCamStreamer?.close()
//        wizardCamStreamer = nil
        outputStreamerForMirror?.close()
//        outputStreamerForMirror = nil
        
        multipeerSession.disconnect()
//        multipeerSession.delegate = nil
        
        NotificationCenter.default.removeObserver(self)
        
        //TODO: revise
        deinitPlaybackObjects()
        
        ciContext = nil
        
        displayLink?.isPaused = true
        displayLink?.remove(from: RunLoop.main, forMode: RunLoopMode.commonModes)
        displayLink?.invalidate()
        displayLink = nil
        
//        prototypePlayerCanvasView.removeFromSuperview()
//        prototypePlayerCanvasView.delegate = nil
//        prototypeCanvasView.removeFromSuperview()
//        prototypeCanvasView.delegate = nil
//        backgroundPlayerCanvasView.removeFromSuperview()
//        backgroundPlayerCanvasView.delegate = nil
//        backgroundCanvasView.removeFromSuperview()
//        backgroundCanvasView.delegate = nil
        
//        videoModel = nil
//        prototypeTimeline?.delegate = nil
//        prototypeTimeline = nil
//        backgroundTimeline?.delegate = nil
//        backgroundTimeline = nil
        cleanExportSession()
    }

    func deinitPlaybackObjects() {
        prototypePlayerItem?.removeObserver(self, forKeyPath: STATUS_KEYPATH, context: &CameraController.observerContext)
        prototypePlayerItem?.removeObserver(self, forKeyPath: RATE_KEYPATH, context: &CameraController.observerContext)
        
        prototypePlayerItem?.remove(self.prototypeVideoOutput)
        backgroundPlayerItem?.remove(self.backgroundVideoOutput)
        
        if let observer = self.periodicTimeObserver {
            prototypePlayer.removeTimeObserver(observer)
            self.periodicTimeObserver = nil
        }
        if let observer = self.itemEndObserver {
            NotificationCenter.default.removeObserver(observer)
            self.itemEndObserver = nil
        }
        
        self.prototypePlayerView.syncLayer?.removeFromSuperlayer()
        self.backgroundPlayerSyncLayer?.removeFromSuperlayer()
    }
    
    // MARK: View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        ciContext = CIContext.init(eaglContext: eaglContext)//, options: [kCIContextWorkingColorSpace:NSNull.init()])
        
        //Let's initialize the mode
         //POP
         if !videoModel.isNew {
//            canvasControllerMode = CanvasControllerLiveMode(controller: self)
//        } else {
            canvasControllerMode = CanvasControllerPlayingMode(controller: self)
        }
        
        //Let's stretch the scrubber
        scrubberSlider.frame = CGRect(origin: scrubberSlider.frame.origin, size: CGSize(width:view!.frame.width - 165,height:scrubberSlider.frame.height))

        // Do any additional setup after loading the view.
//        cloudKitInitialize()
        
        displayLink = CADisplayLink(target: self, selector: #selector(self.displayLinkDidRefresh(displayLink:)))
        displayLink?.preferredFramesPerSecond = Int(fps)
        displayLink?.add(to: RunLoop.main, forMode: RunLoopMode.commonModes)
        displayLink?.isPaused = false
        
        NotificationCenter.default.addObserver(self, selector: #selector(appWillWillEnterForeground), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillTerminate), name: NSNotification.Name.UIApplicationWillTerminate, object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
//        print("viewWillAppear")
//        browser.startBrowsingForPeers()
//        print("initial start browsing for peers")
    }
    
    func cloudKitInitialize() {
        publicDatabase.save(videoRecord) {
            (record, error) in
            if let error = error {
                // Insert error handling
                print("CloudKit save error: \(error.localizedDescription)")
                return
            }
            // Insert successfully saved record code
        }
        let predicate = NSPredicate(format: "isRecording = %@", NSNumber(value:true))

        let subscription = CKQuerySubscription(recordType: "Video", predicate: predicate, options: CKQuerySubscriptionOptions.firesOnRecordUpdate)

        let notificationInfo = CKNotificationInfo()
        notificationInfo.alertLocalizationKey = "The recorded video was modified."
        notificationInfo.shouldBadge = true

        subscription.notificationInfo = notificationInfo

        publicDatabase.save(subscription) { (subscription, error) in
            if let error = error {
                // insert error handling
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(recordUpdate), name: NSNotification.Name(rawValue:"CLOUDKIT_RECORD_UPDATE"), object: nil)
    }
    
    @objc func recordUpdate(notification:Notification) {
        guard let updatedRecordID = notification.object as? CKRecordID else {
            return
        }
        publicDatabase.fetch(withRecordID: updatedRecordID) { (result, error) in
            if let error = error {
                print("Couldn't fetch updated record id \(updatedRecordID)")
                return
            }
            if let video = result {
                if let movieDataFileAsset = video["backgroundMovie"] as? CKAsset {
                    var movieFileURL = movieDataFileAsset.fileURL
                    movieFileURL.appendPathExtension("mov")
                    do {
//                        try movieFileURL.checkResourceIsReachable() //This will fail so I'm not asking anymore
                        try FileManager.default.linkItem(at: movieDataFileAsset.fileURL, to: movieFileURL)
//                        try FileManager.default.removeItem(at: movieFileURL) //This removes the hard link
                    } catch let error as NSError {
                        print("Could not create hard link, we should copy the data to a controlled folder")
                        return
                    }
                    
                    let weakSelf = self
                    DispatchQueue.main.async {
//                        weakSelf.startPlayback(backgroundVideoFileURL: movieFileURL)
                    }
                }
            } else {
                print("--> result was empty")
            }
        }
    }
    
    //Deprecated
    @objc func snapshotSketchOverlay(layers:[CALayer],size:CGSize) {
        UIGraphicsBeginImageContextWithOptions(size, layers.first!.isOpaque, UIScreen.main.scale)
        let graphicContext = UIGraphicsGetCurrentContext()!
        
        for layer in layers {
            layer.render(in: graphicContext)
        }
        
        if let imageFromCurrentImageContext = UIGraphicsGetImageFromCurrentImageContext() {
            sketchOverlay = CIImage(image:imageFromCurrentImageContext)
        } else {
            print("something happened")
        }
        
        UIGraphicsEndImageContext()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: Rotation
    
    override var shouldAutorotate : Bool {
        return false
    }
    
    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return [.landscapeRight]
    }
    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        if "BACKGROUND_TIMELINE_SEGUE" == segue.identifier {
            let navigationController = segue.destination as? UINavigationController
            backgroundTimeline = navigationController?.topViewController as? TimelineViewController
            backgroundTimeline?.videoTrack = videoModel.backgroundTrack
            backgroundTimeline?.canvasView = backgroundCanvasView
            backgroundTimeline?.delegate = self
        }
        if "PROTOTYPE_TIMELINE_SEGUE" == segue.identifier {
            let navigationController = segue.destination as? UINavigationController
            prototypeTimeline = navigationController?.topViewController as? TimelineViewController
            prototypeTimeline?.videoTrack = videoModel.prototypeTrack
            prototypeTimeline?.canvasView = prototypeCanvasView
            prototypeTimeline?.delegate = self
        }
    }
    
    // MARK: - Actions
    
    @IBAction func playPressed(_ sender:AnyObject?) {
        if canvasControllerMode.isPaused {
            playPlayers()
        } else {
            pausePlayers()
        }
    }
    
    var progressBar:MBProgressHUD?
    var exportSession:AVAssetExportSession?
    
    @IBAction func savePressed(_ sender: Any) {
        displayLink?.isPaused = true
        
        guard let backgroundMutableComposition = backgroundComposition?.copy() as? AVComposition else {
            alert(nil, title: "Fatal Error", message: "Couldn't create a copy of the background composition to export")
            return
        }
        
        exportSession = AVAssetExportSession(asset: backgroundMutableComposition, presetName: AVAssetExportPreset1280x720)
        
        let weakSelf = self
        
        let tolerance = kCMTimeZero
        
        guard let coreImageContext = ciContext else {
            alert(nil, title: "Fatal Error", message: "Couldn't get core image context")
            return
        }
        
        let videoComposition = AVVideoComposition(asset: backgroundMutableComposition, applyingCIFiltersWithHandler: { request in
            let compositionTime = request.compositionTime
            let backgroundFrameImage = request.sourceImage
            
            weakSelf.backgroundPlayerItem?.cancelPendingSeeks()
            weakSelf.backgroundPlayerItem?.seek(to: compositionTime, toleranceBefore: tolerance, toleranceAfter: tolerance, completionHandler: { (finishedBackgroundPlayerItem) in
                //                        guard finishedBackgroundPlayerItem else {
                //                            request.finish(with: NSError(domain: "savePressed", code: 666, userInfo: [NSLocalizedDescriptionKey : "App error - Couldn't seek backgroundPlayerItem"]))
                //                            return
                //                        }
                weakSelf.prototypePlayerItem?.cancelPendingSeeks()
                weakSelf.prototypePlayerItem?.seek(to: compositionTime, toleranceBefore: tolerance, toleranceAfter: tolerance, completionHandler: { (finishedPrototypePlayerItem) in
                    
                    //                            guard finishedPrototypePlayerItem else {
                    //                                request.finish(with: NSError(domain: "savePressed", code: 666, userInfo: [NSLocalizedDescriptionKey : "App error - Couldn't seek prototypePlayerItem"]))
                    //                                return
                    //                            }
                    
                    let currentMediaTime = CACurrentMediaTime() //weakSelf.displayLink.timestamp + weakSelf.displayLink.duration
                    
                    let prototypeItemTime = weakSelf.prototypeVideoOutput.itemTime(forHostTime: currentMediaTime)
                    
                    let prototypePixelBuffer:CVPixelBuffer
                    
                    if let currentPrototypePixelBuffer = weakSelf.prototypeVideoOutput.copyPixelBuffer(forItemTime: prototypeItemTime, itemTimeForDisplay: nil) {
                        prototypePixelBuffer = currentPrototypePixelBuffer
                        weakSelf.lastPrototypePixelBuffer = currentPrototypePixelBuffer
                    } else {
                        prototypePixelBuffer = weakSelf.lastPrototypePixelBuffer!
                    }
                    
                    let source = CIImage(cvPixelBuffer: prototypePixelBuffer)
                    
                    DispatchQueue.main.async {
                        
                        guard let copiedBackgroundSyncLayer = weakSelf.backgroundPlayerSyncLayer?.presentation(), let copiedBackgroundCanvasLayer = weakSelf.backgroundCanvasView?.canvasLayer.presentation() else {
                            request.finish(with: NSError(domain: "savePressed", code: 666, userInfo: [NSLocalizedDescriptionKey : "App error - Could not get background presentation()"]))
                            return
                        }
                        
                        weakSelf.snapshotSketchOverlay(layers: [copiedBackgroundSyncLayer,copiedBackgroundCanvasLayer], size:weakSelf.backgroundCanvasView.frame.size)
                        
                        let finalBackgroundFrameImage:CIImage
                        
                        if let backgroundOverlay = weakSelf.sketchOverlay {
                            
                            let overlayFilter = CIFilter(name: "CISourceOverCompositing")!
                            overlayFilter.setValue(backgroundFrameImage, forKey: kCIInputBackgroundImageKey)
                            overlayFilter.setValue(backgroundOverlay, forKey: kCIInputImageKey)
                            guard let result = overlayFilter.outputImage else {
                                request.finish(with: NSError(domain: "savePressed", code: 666, userInfo: [NSLocalizedDescriptionKey : "App error - couldn't get outputImage from CISourceOverCompositing"]))
                                return
                            }
                            finalBackgroundFrameImage = result
                        } else {
                            finalBackgroundFrameImage = backgroundFrameImage
                        }
                        
                        guard let currentBox = weakSelf.videoModel.backgroundTrack?.box(forItemTime: prototypeItemTime) else {
                            request.finish(with: finalBackgroundFrameImage, context: nil)
                            return
                        }
                        
                        guard let copiedSyncLayer = weakSelf.prototypePlayerView.syncLayer?.presentation(), let copiedCanvasLayer = weakSelf.prototypePlayerCanvasView?.canvasLayer.presentation() else {
                            request.finish(with: NSError(domain: "savePressed", code: 666, userInfo: [NSLocalizedDescriptionKey : "App error - Could not get prototype presentation()"]))
                            return
                        }
                        
                        weakSelf.snapshotSketchOverlay(layers:[copiedSyncLayer,copiedCanvasLayer],size:weakSelf.prototypePlayerView.frame.size)

                        var currentPrototypeAndOverlayFrame:CIImage
                        
                        if let overlay = weakSelf.sketchOverlay {
                            let scaledSource = source.transformed(by: CGAffineTransform.identity.scaledBy(x: overlay.extent.width / source.extent.width, y: overlay.extent.height / source.extent.height ))
                            
                            let overlayFilter = CIFilter(name: "CISourceOverCompositing")!
                            overlayFilter.setValue(scaledSource, forKey: kCIInputBackgroundImageKey)
                            overlayFilter.setValue(overlay, forKey: kCIInputImageKey)
                            
                            currentPrototypeAndOverlayFrame = overlayFilter.outputImage!
                        } else {
                            currentPrototypeAndOverlayFrame = source
                        }
                        
                        if let normalizedViewportRect = weakSelf.videoModel.prototypeTrack?.viewportRect {
                            let totalWidth = currentPrototypeAndOverlayFrame.extent.width
                            let totalHeight = currentPrototypeAndOverlayFrame.extent.height
                            
                            let croppingRect = CGRect(x: normalizedViewportRect.origin.x * totalWidth,
                                                      y: normalizedViewportRect.origin.y * totalHeight,
                                                      width: normalizedViewportRect.width * totalWidth,
                                                      height: normalizedViewportRect.height * totalHeight)
                            
                            currentPrototypeAndOverlayFrame = currentPrototypeAndOverlayFrame.cropped(to: croppingRect)
                        }
                        
                        let perspectiveTransformFilter = CIFilter(name: "CIPerspectiveTransform")!
                        
                        let ciSize = backgroundFrameImage.extent.size
                        
                        perspectiveTransformFilter.setValue(CIVector(cgPoint:currentBox.topLeft.scaled(to: ciSize)),
                                                            forKey: "inputTopLeft")
                        perspectiveTransformFilter.setValue(CIVector(cgPoint:currentBox.topRight.scaled(to: ciSize)),
                                                            forKey: "inputTopRight")
                        perspectiveTransformFilter.setValue(CIVector(cgPoint:currentBox.bottomRight.scaled(to: ciSize)),
                                                            forKey: "inputBottomRight")
                        perspectiveTransformFilter.setValue(CIVector(cgPoint:currentBox.bottomLeft.scaled(to: ciSize)),
                                                            forKey: "inputBottomLeft")
                        perspectiveTransformFilter.setValue(currentPrototypeAndOverlayFrame.oriented(CGImagePropertyOrientation.up),
                                                            forKey: kCIInputImageKey)
                        
                        let composite = ChromaKeyFilter()
                        composite.inputImage = finalBackgroundFrameImage
                        composite.backgroundImage = perspectiveTransformFilter.outputImage
                        composite.activeColor = CIColor(red: 0, green: 1, blue: 0)
                        
                        // Provide the filter output to the composition
                        request.finish(with: composite.outputImage, context: coreImageContext)
                    }
                })
            })
        })
        
        exportSession?.outputFileType = AVFileType.mov
        let temporalOutputURL = Globals.temporaryDirectory.appendingPathComponent("currently_exported_movie.mov")
        
        if FileManager.default.fileExists(atPath: temporalOutputURL.path) {
            do {
                try FileManager.default.removeItem(at: temporalOutputURL)
            } catch let error as NSError {
                alert(error, title:"FileSystem Error", message:"Could not clean temporal video file location \(temporalOutputURL)")
                return
            }
        }
        
        exportSession?.outputURL = temporalOutputURL
        exportSession?.videoComposition = videoComposition
        
        guard let window = UIApplication.shared.keyWindow else {
            alert(nil, title: "Fatal Error", message: "Couldn't get the keyWindow of the app")
            return
        }
        
        progressBar = MBProgressHUD.showAdded(to: window, animated: true)
        progressBar?.mode = MBProgressHUDMode.determinateHorizontalBar
        progressBar?.label.text = "Exporting ..."
        
        progressBar?.detailsLabel.text = "Tap to cancel"
        progressBar?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cancelExport(_:))))
        
        exportSession?.exportAsynchronously {
            switch weakSelf.exportSession!.status {
            case .unknown:
                print("exportSession status unknown")
            case .waiting:
                print("exportSession status waiting")
            case .exporting:
                print("exportSession status exporting")
            case .cancelled, .failed:
                weakSelf.alert(weakSelf.exportSession?.error, title: "Export Session", message: "Failed or cancelled")
            case .completed:
                DispatchQueue.main.async {
                    let finalOutputURL = weakSelf.videoModel.file
                    
                    //If the finalOutput exist, then I do a backup
                    if FileManager.default.fileExists(atPath: finalOutputURL.path) {
                        let backupFilePath = finalOutputURL.deletingPathExtension().lastPathComponent + "-backup." + finalOutputURL.pathExtension
                        let backupOutputURL = finalOutputURL.deletingLastPathComponent().appendingPathComponent(backupFilePath)
                        
                        //I delete the last backup if there is one
                        if FileManager.default.fileExists(atPath: backupOutputURL.path) {
                            do {
                                try FileManager.default.removeItem(at: backupOutputURL)
                            } catch let error as NSError {
                                weakSelf.alert(error, title:"FileSystem Error", message:"Could not delete previous backup file \(backupOutputURL)")
                                return
                            }
                        }
                        
                        //Finally I move the finalOutput to the backupOutput
                        do {
                            try FileManager.default.moveItem(at: finalOutputURL, to: backupOutputURL)
                        } catch {
                            weakSelf.alert(error, title:"FileSystem Error", message:"Could not move existing final commposition video file to backup location \(backupOutputURL)")
                            return
                        }
                    }
                    
                    //Always at the end, I move the temporalOutput to the finalOutput (aka video.file)
                    do {
                        try FileManager.default.moveItem(at: temporalOutputURL, to: finalOutputURL)
                    } catch let error as NSError {
                        weakSelf.alert(error, title:"FileSystem Error", message:"Could not move recently exported final commposition video file to final location \(finalOutputURL)")
                        return
                    }
                    
                    do {
                        try weakSelf.coreDataContext.save()
                        weakSelf.close()
                        weakSelf.dismiss(animated: true, completion: nil)
                    } catch {
                        weakSelf.alert(error, title: "DB Error", message: "Could not save exported final video")
                    }
                    
                }
            }
        }
        monitorExportProgress(exportSession!)
    }
    
    func monitorExportProgress(_ exportSession:AVAssetExportSession) {
        let delta = Int64(NSEC_PER_SEC / 10)
        
        let popTime = DispatchTime.now() + Double(delta) / Double(NSEC_PER_SEC)
        
        let weakSelf = self
        DispatchQueue.main.asyncAfter(deadline: popTime, execute: {
            let status = exportSession.status
            if status == AVAssetExportSessionStatus.exporting {
                weakSelf.progressBar?.progress = exportSession.progress
                if exportSession.progress == 1 {
                    weakSelf.progressBar?.label.text = "Saving ..."
                }
                //                print("Exporting progress \(exportSession.progress)")
                weakSelf.monitorExportProgress(exportSession)
            } else {
                //Not exporting anymore
                if let progress = weakSelf.progressBar {
                    progress.label.text = "Done"
                    progress.hide(animated: true)
                    weakSelf.progressBar = nil
                }
            }
        })
    }
    
    @objc func cancelExport(_ recognizer:UITapGestureRecognizer) {
        guard let aProgressBar = progressBar else {
            return
        }
        let location = recognizer.location(in: progressBar)
        
        let xDist = location.x - aProgressBar.center.x
        let yDist = location.y - aProgressBar.center.y
        let distanceToCenter = sqrt((xDist * xDist) + (yDist * yDist))
        
        if distanceToCenter < 90 {
            cleanExportSession()
        }
    }
    
    func cleanExportSession() {
        exportSession?.cancelExport()
        exportSession = nil
        progressBar?.hide(animated:true)
        progressBar = nil
    }
    
    @IBAction func cancelPressed(_ sender: Any) {
        canvasControllerMode.cancel(controller:self)
        
        close()
        dismiss(animated: true)
    }
    
    @IBAction func menuPressed(_ sender: UIBarButtonItem) {
        let weakSelf = self
        
        let alertController = UIAlertController(title: nil, message: "Actions", preferredStyle: .actionSheet)
        
        let goLiveAction = UIAlertAction(title: "Go Live", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            weakSelf.livePressed()
        })
        
        goLiveAction.isEnabled = !canvasControllerMode.isLive
        
        let startRecordingAction = UIAlertAction(title: "Start Recording", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            weakSelf.startRecordingPressed()
        })
        
        startRecordingAction.isEnabled = !canvasControllerMode.isRecording
        
        let searchCamAction = UIAlertAction(title: "Connect Camera", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            weakSelf.searchForCam()
        })
        
        searchCamAction.isEnabled = !canvasControllerMode.isRecording

        
        let searchMirrorAction = UIAlertAction(title: "Connect Mirror", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            weakSelf.searchForMirror()
        })
        
        searchMirrorAction.isEnabled = !canvasControllerMode.isRecording
        
        let maskAction = UIAlertAction(title: "Extract Sketch", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            weakSelf.maskPressed()
        })
        
        let calibrateAction = UIAlertAction(title: "Calibrate Chroma", style: .default, handler: { (alert: UIAlertAction!) -> Void in

        })
        
        let userOverlayAction = UIAlertAction(title: "Toggle User Overlay", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            weakSelf.isUserOverlayActive = !weakSelf.isUserOverlayActive
        })
        
        let swapCamsAction = UIAlertAction(title: "Swap Cams", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            if let newUserCam = weakSelf.wizardCamPeer, let newWizardCam = weakSelf.userCamPeer {
                swap(&weakSelf.userCamPeer, &weakSelf.wizardCamPeer)
                weakSelf.setRole(peerID: newUserCam, role: .userCam)
                weakSelf.setRole(peerID: newWizardCam, role: .wizardCam)
                swap(&weakSelf.userCamStreamer, &weakSelf.wizardCamStreamer)
            }
        })
        
        swapCamsAction.isEnabled = userCamStreamer != nil && wizardCamStreamer != nil
        maskAction.isEnabled = !canvasControllerMode.isRecording
        
        alertController.addAction(goLiveAction)
        alertController.addAction(startRecordingAction)
        alertController.addAction(searchCamAction)
        alertController.addAction(searchMirrorAction)
        alertController.addAction(maskAction)
        alertController.addAction(calibrateAction)
        alertController.addAction(userOverlayAction)
        alertController.addAction(swapCamsAction)
        
        if let popoverController = alertController.popoverPresentationController {
            popoverController.barButtonItem = sender
        }
        
        weakSelf.present(alertController, animated: true, completion: nil)
    }
    
    func livePressed() {
        if !canvasControllerMode.isRecording {
            prototypePlayerView.isHidden = true
            
            prototypeCanvasView.isHidden = false
            prototypeCanvasView.isUserInteractionEnabled = true
            
            backgroundPlayerSyncLayer?.removeFromSuperlayer()
            backgroundPlayerSyncLayer = nil
            
            backgroundCanvasView.isHidden = false
            backgroundCanvasView.isUserInteractionEnabled = true
            
            playButtonContainer.isEnabled = false
            playButton.isEnabled = false
            scrubberSlider.isEnabled = false
            scrubberButtonItem.isEnabled = false
            
            let dict = ["shouldStream":true]
            let data = NSKeyedArchiver.archivedData(withRootObject: dict)
            
            do {
                try multipeerSession.send(data, toPeers: cams, with: .reliable)
            } catch let error as NSError {
                print("Could not send trigger to start streaming remote cams: \(error.localizedDescription)")
            }
            
            canvasControllerMode = CanvasControllerLiveMode(controller:self)
        }
    }
    
    @IBAction func recordingControlChanged(_ sender:UISegmentedControl) {
        let selectedSegment = sender.selectedSegmentIndex
        
        if (selectedSegment == 0) {
            if canvasControllerMode.isPaused {
                sender.setTitle("Pause", forSegmentAt: selectedSegment)
                resumeRecordingPressed()
            } else {
                sender.setTitle("Resume", forSegmentAt: selectedSegment)
                pauseRecordingPressed()
            }
        } else{
            stopRecordingPressed()
        }

        sender.selectedSegmentIndex = UISegmentedControlNoSegment

    }
    
    func resumeRecordingPressed() {
        canvasControllerMode.resume(controller: self)
    }
    
    func pauseRecordingPressed() {
        canvasControllerMode.pause(controller: self)
    }
    
    func stopRecordingPressed() {
        canvasControllerMode.stopRecording(controller: self)
    }
    
    func startRecordingPressed() {
        syncTime = NSDate.network()
            
        let startRecordingDate = syncTime!.addingTimeInterval(countDownTimeInterval)
        
        recordingControls.isHidden = false
        
        let weakSelf = self
        let timer = Timer(fire: startRecordingDate, interval: 0, repeats: false, block: { (timer) in
            weakSelf.canvasControllerMode.startRecording(controller: self)
            timer.invalidate()
        })
        RunLoop.main.add(timer, forMode: RunLoopMode.commonModes)
        
        let syncDict:[String : Any?] = ["syncTime":nil]
        if let wizardCam = wizardCamPeer {
            sendMessage(peerID: wizardCam, dict: syncDict)
        }
        if let userCam = userCamPeer {
            sendMessage(peerID: userCam, dict: syncDict)
        }
    }
    
    func maskPressed() {
//        multipeerSession.disconnect()
//        let maskView = TCMaskView(image: UIImage(named:"cat")!/*UIImage(ciImage:prototypeCameraFrame!)*/)
//        maskView.testDevices = ["10b996fbcdc43ec8a2eb203397273dce"]
//        maskView.delegate = self
//        maskView.presentFrom(rootViewController: self, animated: true)
    }
    
    func searchForMirror() {
        isMirrorMode = true
        browser.startBrowsingForPeers()
    }
    
    func searchForCam() {
        browser.startBrowsingForPeers()
    }
    
    func sendMessage(peerID:MCPeerID,dict:[String:Any?]) {
        let data = NSKeyedArchiver.archivedData(withRootObject: dict)

        do {
            try multipeerSession.send(data, toPeers: [peerID], with: .reliable)
        } catch let error as NSError {
            print("Could not send dict message: \(error.localizedDescription)")
        }
    }
    
    @objc func countDownMethod() {
        if recordingLabel.isHidden {
            view.bringSubview(toFront: recordingLabel)
            recordingLabel.isHidden = false
            recordingLabel.text = "3"
            self.perform(#selector(countDownMethod), with: nil, afterDelay: 1.0)
        } else if recordingLabel.text! == "3" {
            recordingLabel.text = "2"
            self.perform(#selector(countDownMethod), with: nil, afterDelay: 1.0)
        } else if recordingLabel.text! == "2" {
            recordingLabel.text = "1"
            self.perform(#selector(countDownMethod), with: nil, afterDelay: 1.0)
        } else if recordingLabel.text! == "1" {
            recordingLabel.text = "GO"
            
            let weakSelf = self
            UIView.animate(withDuration: 0.5, animations: {
                weakSelf.recordingLabel.alpha = 0
            }, completion: { (completed) in
                weakSelf.recordingLabel.isHidden = true
            })
        }
    }
    
    @IBAction func sliderChanged(_ sender:UISlider) {
//        let trackRect = scrubberSlider.trackRect(forBounds: scrubberSlider.bounds)
//        let thumbRect = scrubberSlider.thumbRect(forBounds: scrubberSlider.bounds, trackRect: trackRect, value: scrubberSlider.value)
        
        seekToTime(Double(scrubberSlider.value))
    }
    
    func startPlayback(shouldUseSmallestDuration:Bool = false) {
        //We should start showing the prototype AVPlayer and enabling the player controls\
        
        guard let prototypeVideoFileURL = self.videoModel.prototypeTrack?.loadedFileURL, let backgroundVideoFileURL = self.videoModel.backgroundTrack?.loadedFileURL else {
            print("Cannot start playback, missing movie/s")
            return
        }
        
        let assetLoadingGroup = DispatchGroup()
        
        let prototypeAsset = AVURLAsset(url: prototypeVideoFileURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey:true])
        assetLoadingGroup.enter()
        prototypeAsset.loadValuesAsynchronously(forKeys: ["duration"]) {
            assetLoadingGroup.leave()
        }
        
        let backgroundAsset = AVURLAsset(url: backgroundVideoFileURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey:true])
        assetLoadingGroup.enter()
        backgroundAsset.loadValuesAsynchronously(forKeys: ["duration"]) {
            assetLoadingGroup.leave()
        }
        
        let weakSelf = self
        assetLoadingGroup.notify(queue: DispatchQueue.main) {
            print("Prototype duration \(prototypeAsset.duration.seconds)")
            print("Background duration \(backgroundAsset.duration.seconds)")
            let compositionTotalDuration:CMTime
            
            if shouldUseSmallestDuration {
                compositionTotalDuration = CMTimeCompare(backgroundAsset.duration, prototypeAsset.duration) < 0 ? backgroundAsset.duration : prototypeAsset.duration
            } else {
                compositionTotalDuration = backgroundAsset.duration
            }

            weakSelf.prototypeComposition = AVMutableComposition()
            guard let prototypeCompositionVideoTrack = weakSelf.prototypeComposition?.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                weakSelf.alert(nil, title: "Playback error", message: "Could not create compositionVideoTrack for prototype")
                return
            }
            
            guard let prototypeAssetVideoTrack = prototypeAsset.tracks(withMediaType: .video).first else {
                weakSelf.alert(nil, title: "Playback error", message: "The prototype video file does not have any video track")
                return
            }
            
            let prototypeCompositionVideoTimeRange = CMTimeRange(start: kCMTimeZero, duration: compositionTotalDuration)
            
            do {
                try prototypeCompositionVideoTrack.insertTimeRange(prototypeCompositionVideoTimeRange, of: prototypeAssetVideoTrack, at: kCMTimeZero)
            } catch {
                weakSelf.alert(nil, title: "Playback error", message: "Could not insert video track in prototype  compositionVideoTrack")
                return
            }
            
            let aPrototypePlayerItem = AVPlayerItem(asset: weakSelf.prototypeComposition!,automaticallyLoadedAssetKeys:["tracks","duration"])
            self.prototypePlayerItem = aPrototypePlayerItem
            
            weakSelf.prototypePlayer = AVPlayer(playerItem: aPrototypePlayerItem)
            weakSelf.prototypePlayerView.player = weakSelf.prototypePlayer
            weakSelf.prototypePlayerView.isHidden = false
            weakSelf.prototypeCanvasView.isHidden = true
            weakSelf.prototypeCanvasView.isUserInteractionEnabled = false
            
            weakSelf.prototypePlayerItem?.add(weakSelf.prototypeVideoOutput)
            
            weakSelf.backgroundComposition = AVMutableComposition()
            guard let backgroundCompositionVideoTrack = weakSelf.backgroundComposition?.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                weakSelf.alert(nil, title: "Playback error", message: "Could not create compositionVideoTrack for background")
                return
            }
            
            guard let backgroundCompositionAudioTrack = weakSelf.backgroundComposition?.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                weakSelf.alert(nil, title: "Playback error", message: "Could not create compositionAudioTrack for background")
                return
            }
            
            guard let backgroundAssetVideoTrack = backgroundAsset.tracks(withMediaType: .video).first else {
                weakSelf.alert(nil, title: "Playback error", message: "The background video file does not have any video track")
                return
            }
            
            guard let backgroundAssetAudioTrack = backgroundAsset.tracks(withMediaType: .audio).first else {
                weakSelf.alert(nil, title: "Playback error", message: "The background video file does not have any audio track")
                return
            }
            
            let backgroundCompositionTotalTimeRange = CMTimeRange(start: kCMTimeZero, duration: compositionTotalDuration)
            
            do {
                try backgroundCompositionVideoTrack.insertTimeRange(backgroundCompositionTotalTimeRange, of: backgroundAssetVideoTrack, at: kCMTimeZero)
            } catch {
                weakSelf.alert(nil, title: "Playback error", message: "Could not insert video track in background compositionVideoTrack")
                return
            }
            
            do {
                try backgroundCompositionAudioTrack.insertTimeRange(backgroundCompositionTotalTimeRange, of: backgroundAssetAudioTrack, at: kCMTimeZero)
            } catch {
                weakSelf.alert(nil, title: "Playback error", message: "Could not insert audio track in background compositionAudioTrack")
                return
            }
            
            let aBackgroundPlayerItem = AVPlayerItem(asset: weakSelf.backgroundComposition!,automaticallyLoadedAssetKeys:["tracks","duration"])
            self.backgroundPlayerItem = aBackgroundPlayerItem
            weakSelf.backgroundPlayer = AVPlayer(playerItem: aBackgroundPlayerItem)

            weakSelf.backgroundCanvasView.isHidden = true
            weakSelf.backgroundCanvasView.isUserInteractionEnabled = false
            
            //        let backgroundPlayerView = VideoPlayerView()
            //        backgroundPlayerView.translatesAutoresizingMaskIntoConstraints = false
            //        backgroundPlayerView.player = backgroundPlayer
            //        backgroundPlayerView.frame = CGRect(x: 0, y: 500, width: 480, height: 360)
            //        view.addSubview(backgroundPlayerView)
            
            weakSelf.backgroundPlayerItem?.add(weakSelf.backgroundVideoOutput)
            weakSelf.backgroundVideoOutput.suppressesPlayerRendering = true
            
            //Prototype Player Canvas View
            weakSelf.prototypePlayerCanvasView.isHidden = false
            weakSelf.prototypePlayerView.syncLayer = AVSynchronizedLayer(playerItem: aPrototypePlayerItem)

            weakSelf.prototypePlayerCanvasView?.associatedSyncLayer = weakSelf.prototypePlayerView.syncLayer
            
            for tier in weakSelf.prototypePlayerCanvasView?.videoTrack.tiers!.array as! [Tier] {
                let shapeLayer = tier.shapeLayer
                
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                weakSelf.prototypePlayerView.syncLayer?.addSublayer(shapeLayer)
                CATransaction.commit()
                
                tier.rebuildAnimations(forLayer:shapeLayer, totalRecordingTime:weakSelf.prototypeComposition!.duration.seconds)
            }
            
            //Background Player Canvas View
            weakSelf.backgroundPlayerCanvasView.isHidden = false
            
            weakSelf.backgroundPlayerSyncLayer = AVSynchronizedLayer(playerItem: aBackgroundPlayerItem)
            weakSelf.backgroundFrameImageView.layer.addSublayer(weakSelf.backgroundPlayerSyncLayer!)
            
            weakSelf.backgroundPlayerCanvasView?.associatedSyncLayer = weakSelf.backgroundPlayerSyncLayer
            
            for tier in weakSelf.backgroundPlayerCanvasView!.videoTrack.tiers!.array as! [Tier] {
                let shapeLayer = tier.shapeLayer
                
                weakSelf.backgroundPlayerSyncLayer!.addSublayer(shapeLayer)
                
                tier.rebuildAnimations(forLayer:shapeLayer, totalRecordingTime:weakSelf.backgroundComposition!.duration.seconds)
            }
            
            weakSelf.playButtonContainer.isEnabled = true
            weakSelf.playButton.isEnabled = true
            weakSelf.scrubberSlider.isEnabled = true
            weakSelf.scrubberButtonItem.isEnabled = true
            
            weakSelf.prototypePlayerItem?.addObserver(weakSelf, forKeyPath: STATUS_KEYPATH, options: NSKeyValueObservingOptions(rawValue: 0), context: &CameraController.observerContext)
            weakSelf.prototypePlayerItem?.addObserver(weakSelf, forKeyPath: RATE_KEYPATH, options: NSKeyValueObservingOptions.initial, context: &CameraController.observerContext)
            
            weakSelf.playPlayers()
            
            if weakSelf.displayLink?.isPaused != true {
                print("Weird, displayLink?.isPaused should be true at this point")
            }
            weakSelf.displayLink?.isPaused = false
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change:
        [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

        if let object = object as? AVPlayerItem, context! == &CameraController.observerContext {
            if prototypePlayerItem == object {
                guard let keyPath = keyPath else {
                    return
                }
                switch keyPath {
                case STATUS_KEYPATH:
                    guard prototypePlayerItem?.status == AVPlayerItemStatus.readyToPlay else {
                        print("Error, failed to load video") //TODO check why this is happening sometimes
                        return
                    }
                    guard let duration = prototypePlayerItem?.duration else {
                        print("Couldn't get prototypePlayerItem?.duration")
                        return
                    }
                    
                    let weakSelf = self
                    DispatchQueue.main.async(execute: { () -> Void in
                        weakSelf.setCurrentTime(CMTimeGetSeconds(kCMTimeZero),duration:CMTimeGetSeconds(duration))
                        //                    weakSelf.displayLink.isPaused = false
                        weakSelf.addPlayerItemPeriodicTimeObserver()
                        weakSelf.addDidPlayToEndItemEndObserverForPlayerItem()
                    })
                case RATE_KEYPATH:
                    print("Not doing anyhting for RATE_KEYPATH, prototypePlayer.rate = \(prototypePlayer.rate)")
                default:
                    print("Unkown observeValue forKeyPath \(keyPath)")
                }
            }
        }
    }
    
    @objc func displayLinkDidRefresh(displayLink: CADisplayLink) {
        /*
         The callback gets called once every Vsync.
         Using the display link's timestamp and duration we can compute the next time the screen will be refreshed, and copy the pixel buffer for that time
         This pixel buffer can then be processed and later rendered on screen.
         */
/*        var prototypeItemTime = kCMTimeInvalid
        var backgroundItemTime = kCMTimeInvalid
        
        // Calculate the nextVsync time which is when the screen will be refreshed next.
        let nextVSync = (displayLink.timestamp + displayLink.duration)
        
        prototypeItemTime = prototypeVideoOutput.itemTime(forHostTime: nextVSync)
        backgroundItemTime = backgroundVideoOutput.itemTime(forHostTime: nextVSync)
*/
        
        if type(of: canvasControllerMode) != CanvasControllerPlayingMode.self {

            let weakSelf = self
            
            streamerQueue.async {
//                if let ciImage = weakSelf.backgroundCameraFrame {
//                    weakSelf.setImageOpenGL(view: weakSelf.backgroundFrameImageView, image: ciImage)
//                }
                if let receivedCIImage = weakSelf.prototypeCameraFrame {
                    weakSelf.applyFilterFromPrototypeToBackground(source: receivedCIImage)
                }
            }
            
        } else {
            getFramesForPlayback()
        }
    }
    
    func getFramesForPlayback() {
//        let currentMediaTime = CACurrentMediaTime()
//
//        let prototypeItemTime = prototypeVideoOutput.itemTime(forHostTime: currentMediaTime)
//        let backgroundItemTime = backgroundVideoOutput.itemTime(forHostTime: currentMediaTime)
//        var prototypeItemTime = kCMTimeInvalid
//        var backgroundItemTime = kCMTimeInvalid
        
        // Calculate the nextVsync time which is when the screen will be refreshed next.
        
//        let nextVSync = CACurrentMediaTime() + displayLink.duration

//        guard let timestamp = displayLink?.timestamp, let duration = displayLink?.duration else {
//            print("Error in getFramesForPlayback, couldn't get displayLink")
//            return
//        }
        
//        let nextVSync = displayLink!.timestamp + displayLink!.duration
        
        let nextVSync = canvasControllerMode.isPaused ? CACurrentMediaTime() : displayLink!.timestamp + displayLink!.duration
        let prototypeItemTime = prototypeVideoOutput.itemTime(forHostTime: nextVSync)
        let backgroundItemTime = backgroundVideoOutput.itemTime(forHostTime: nextVSync)
        
        let weakSelf = self
        DispatchQueue.main.async {
            if let copiedSyncLayer = weakSelf.prototypePlayerView.syncLayer?.presentation(), let copiedCanvasLayer = weakSelf.prototypePlayerCanvasView?.canvasLayer.presentation() {
                weakSelf.snapshotSketchOverlay(layers:[copiedSyncLayer,copiedCanvasLayer],size:weakSelf.prototypePlayerView.frame.size)
            } else {
                print("getFramesForPlayback >> Could not get presentation()")
            }
        }
        
        if backgroundVideoOutput.hasNewPixelBuffer(forItemTime: backgroundItemTime) {
            //            print("backgroundVideoOutput hasNewPixelBuffer")
            if let backgroundPixelBuffer = backgroundVideoOutput.copyPixelBuffer(forItemTime: backgroundItemTime, itemTimeForDisplay: nil) {
                //                print("backgroundPixelBuffer SUCCESS")
                backgroundCameraFrame = CIImage(cvPixelBuffer: backgroundPixelBuffer)
            } else {
                print("backgroundPixelBuffer FAIL")
                
            }
        }// else {
        //            print("backgroundVideoOutput NOT hasNewPixelBuffer")
        //        }
        
        if prototypeVideoOutput.hasNewPixelBuffer(forItemTime: prototypeItemTime) {
            //            print("prototypeVideoOutput hasNewPixelBuffer")
            if let prototypePixelBuffer = prototypeVideoOutput.copyPixelBuffer(forItemTime: prototypeItemTime, itemTimeForDisplay: nil) {
                //                print("prototypePixelBuffer SUCCESS")
                lastPrototypePixelBuffer = prototypePixelBuffer
            } else {
                print("prototypePixelBuffer FAIL")
            }
        } else {
//            print("prototypeVideoOutput NOT hasNewPixelBuffer")
        }
        
        if let prototypePixelBuffer = lastPrototypePixelBuffer {
            let weakSelf = self
            
            streamerQueue.async {
                if let obtainedBox = weakSelf.videoModel.backgroundTrack?.box(forItemTime: backgroundItemTime) {
                    weakSelf.box = obtainedBox
                } else {
                    print("box(forItemTime: ...) returned nil") //TODO:
                }
                weakSelf.applyFilterFromPrototypeToBackground(prototypePixelBuffer)
            }
        }
        
        //        print("---")
        //        if let backgroundPixelBuffer = backgroundPixelBuffer {
        //            externalCameraFrame = UIImage(ciImage: CIImage(cvPixelBuffer: backgroundPixelBuffer))
        //        }
        //
        //        if let prototypePixelBuffer = prototypePixelBuffer {
        //            applyFilterFromPrototypeToBackground(prototypePixelBuffer,ignoreSketchOverlay: true)
        //        }
    }

    func cgImageBackedImage(withCIImage ciImage:CIImage) -> UIImage? {
        guard let ref = ciContext?.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let image = UIImage(cgImage: ref, scale: UIScreen.main.scale, orientation: UIImageOrientation.up)
        
        return image
    }
    
    func applyFilterFromPrototypeToBackground(_ pixelBuffer:CVImageBuffer) {
        applyFilterFromPrototypeToBackground(source:CIImage(cvPixelBuffer: pixelBuffer))
    }
    
    func setImageOpenGL(view glkView:GLKView, image:CIImage) {
//        guard let ciContext = ciContext else {
//            print("Couldn't get ciContext")
//            return
//        }
        let weakSelf = self
        DispatchQueue.main.async {
            let glkViewBounds = glkView.bounds
            drawingQueue.async {
                glkView.bindDrawable()
                let containerBoundsInPixels = glkViewBounds.applying(CGAffineTransform(scaleX: deviceScale, y: deviceScale))
                weakSelf.ciContext?.draw(image, in: containerBoundsInPixels, from: image.extent)
                glkView.display()
            }
        }
    }
    
    func applyFilterFromPrototypeToBackground(source:CIImage) {

        var currentPrototypeAndOverlayFrame:CIImage
        
        if let overlay = sketchOverlay {
            let scaledSource = source.transformed(by: CGAffineTransform.identity.scaledBy(x: overlay.extent.width / source.extent.width, y: overlay.extent.height / source.extent.height ))
            
            let overlayFilter = CIFilter(name: "CISourceOverCompositing")!
            overlayFilter.setValue(scaledSource, forKey: kCIInputBackgroundImageKey)
            overlayFilter.setValue(overlay, forKey: kCIInputImageKey)
            
            currentPrototypeAndOverlayFrame = overlayFilter.outputImage!
        } else {
            currentPrototypeAndOverlayFrame = source
        }
        
        if let normalizedViewportRect = videoModel.prototypeTrack?.viewportRect {
            let totalWidth = currentPrototypeAndOverlayFrame.extent.width
            let totalHeight = currentPrototypeAndOverlayFrame.extent.height
    
            let croppingRect = CGRect(x: normalizedViewportRect.origin.x * totalWidth,
                                      y: normalizedViewportRect.origin.y * totalHeight,
                                      width: normalizedViewportRect.width * totalWidth,
                                      height: normalizedViewportRect.height * totalHeight)
            
            currentPrototypeAndOverlayFrame = currentPrototypeAndOverlayFrame.cropped(to: croppingRect)
        }
        
        guard let finalBackgroundFrameImage = backgroundCameraFrame else {
            setImageOpenGL(view: prototypeFrameImageView,image: source)
            return
        }
        
        let perspectiveTransformFilter = CIFilter(name: "CIPerspectiveTransform")!
        let ciSize = finalBackgroundFrameImage.extent.size
        
        let currentBox = box
        perspectiveTransformFilter.setValue(CIVector(cgPoint:currentBox.topLeft.scaled(to: ciSize)),
                                            forKey: "inputTopLeft")
        perspectiveTransformFilter.setValue(CIVector(cgPoint:currentBox.topRight.scaled(to: ciSize)),
                                            forKey: "inputTopRight")
        perspectiveTransformFilter.setValue(CIVector(cgPoint:currentBox.bottomRight.scaled(to: ciSize)),
                                            forKey: "inputBottomRight")
        perspectiveTransformFilter.setValue(CIVector(cgPoint:currentBox.bottomLeft.scaled(to: ciSize)),
                                            forKey: "inputBottomLeft")
        
        perspectiveTransformFilter.setValue(currentPrototypeAndOverlayFrame.oriented(CGImagePropertyOrientation.up), forKey: kCIInputImageKey)
        
        let composite = ChromaKeyFilter()
        composite.inputImage = finalBackgroundFrameImage
        composite.backgroundImage = perspectiveTransformFilter.outputImage
        composite.activeColor = CIColor(red: 0, green: 1, blue: 0)
        
        if let compositeImage = composite.outputImage {
            setImageOpenGL(view: self.backgroundFrameImageView,image: compositeImage)
        }
        //Apple Chroma (not working)
        //            let composite = CIFilter(name:"ChromaKey") as! ChromaKey
        //
        //            composite.setDefaults()
        //            composite.setValue(perspectiveTransform.outputImage!, forKey: "inputBackgroundImage")
        //            composite.setValue(currentFrame, forKey: "inputImage")
        //
        //            composite.inputCenterAngle = NSNumber(value:120 * Float.pi / 180)
        //            composite.inputAngleWidth = NSNumber(value:45 * Float.pi / 180)
        
        //GHOST
        guard isUserOverlayActive else {
            setImageOpenGL(view: self.prototypeFrameImageView,image: source)
            return
        }

        //We do a CIPerspectiveCorrection of the green area finalBackgroundFrameImage
        
        let perspectiveCorrection = CIFilter(name: "CIPerspectiveCorrection")!
        
        perspectiveCorrection.setValue(perspectiveTransformFilter.value(forKey: "inputTopLeft"),
                                       forKey: "inputTopLeft")
        perspectiveCorrection.setValue(perspectiveTransformFilter.value(forKey: "inputTopRight"),
                                       forKey: "inputTopRight")
        perspectiveCorrection.setValue(perspectiveTransformFilter.value(forKey: "inputBottomRight"),
                                       forKey: "inputBottomRight")
        perspectiveCorrection.setValue(perspectiveTransformFilter.value(forKey: "inputBottomLeft"),
                                       forKey: "inputBottomLeft")
        
        perspectiveCorrection.setValue(finalBackgroundFrameImage,forKey: kCIInputImageKey)
        
        guard let ghost = perspectiveCorrection.outputImage?.oriented(CGImagePropertyOrientation.up) else {
            print("perspectiveCorrection failed - falling back to simple source")
            setImageOpenGL(view: self.prototypeFrameImageView,image: source)
            return
        }
        
        let scaledGhost = ghost.transformed(by: CGAffineTransform.identity.scaledBy(x: source.extent.width / ghost.extent.width, y: source.extent.height / ghost.extent.height ))
        
        removeGreenFilter.setValue(scaledGhost, forKey: kCIInputImageKey)
        
        let transparencyMatrixEffect = CIFilter(name:"CIColorMatrix")!
        
        transparencyMatrixEffect.setDefaults()
        transparencyMatrixEffect.setValue(removeGreenFilter.outputImage, forKey: kCIInputImageKey)
        
        transparencyMatrixEffect.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        transparencyMatrixEffect.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        transparencyMatrixEffect.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        transparencyMatrixEffect.setValue(CIVector(x: 0, y: 0, z: 0, w: 0.8), forKey: "inputAVector")
        
        let composite2 = CIFilter(name: "CISourceOverCompositing")!
        composite2.setValue(transparencyMatrixEffect.outputImage, forKey: kCIInputImageKey)
        composite2.setValue(source, forKey: kCIInputBackgroundImageKey)
        
        //composite2.inputImage = transparencyMatrixEffect.outputImage
        //composite2.backgroundImage = source
        //composite2.activeColor = CIColor(red: 0, green: 1, blue: 0)
        
        if let compositeImage2 = composite2.outputImage {
            setImageOpenGL(view: self.prototypeFrameImageView,image: compositeImage2)
        }
    }
    
    func exifOrientation(orientation: UIDeviceOrientation) -> UInt32 {
        switch orientation {
        case .portraitUpsideDown:
            return 8
        case .landscapeLeft:
            return 3
        case .landscapeRight:
            return 1
        default:
            return 6
        }
    }
    
    //MARK: MCSessionDelegate Methods
    func setRole(peerID:MCPeerID,role:MontageRole) {
        let dict = ["role":role.rawValue]
        let data = NSKeyedArchiver.archivedData(withRootObject: dict)
        
        do {
            try multipeerSession.send(data, toPeers: [peerID], with: .reliable)
        } catch let error as NSError {
            print("Could not send set remote cam \(peerID) to have role \(role): \(error.localizedDescription)")
        }
    }
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            print("PEER CONNECTED: \(peerID.displayName)")
            
            guard let peerRole = role(forPeer: peerID) else {
                return
            }
            
            switch peerRole {
            case .cam:
                if userCamPeer == nil {
                    userCamPeer = peerID
                    setRole(peerID: peerID, role: .userCam)
                    browser.stopBrowsingForPeers()
                } else {
                    if wizardCamPeer == nil {
                        wizardCamPeer = peerID
                        setRole(peerID: peerID, role: .wizardCam)
                    }
                }
            case .mirror:
                if mirrorPeer == nil {
                    mirrorPeer = peerID

                    do {
                        let outputStream = try multipeerSession.startStream(withName: "canvas_sketches_stream_for_mirror", toPeer: peerID)
                        print("Created MultipeerSession Stream for mirror peer: \(peerID.displayName)")
                        
                        outputStreamerForMirror = SimpleOutputStreamer(peerID,outputStream:outputStream)
                        outputStreamerForMirror?.delegate = self
                        
                        if let connectedWizardCam = wizardCamPeer {
                            //Let's notify the wizardCam to connect to the mirror
                            sendMessage(peerID:connectedWizardCam,dict:["mirrorMode":peerID])
                        }
                        
                    } catch {
                        print("Could not create multipeer stream for mirror peer \(peerID.displayName)")
                    }
                    
                }
            default:
                print("ignoring other roles \(peerRole.rawValue)")
            }
            
            break
        case .connecting:
            print("PEER CONNECTING: \(peerID.displayName)")
            break
        case .notConnected:
            print("PEER NOT CONNECTED: \(peerID.displayName)")
        
            if peerID == userCamPeer {
                userCamPeer = nil
                browser.startBrowsingForPeers()
            }
            
            if peerID == wizardCamPeer {
                wizardCamPeer = nil
            }
            
            if peerID == mirrorPeer {
                mirrorPeer = nil
                
                outputStreamerForMirror?.close()
                outputStreamerForMirror = nil

                if let connectedWizardCam = wizardCamPeer {
                    sendMessage(peerID:connectedWizardCam,dict:["mirrorMode":nil])
                }
            }
            
            break
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
//        print("Received data from \(peerID.displayName) Read \(data.count) bytes")
        if let receivedDict = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String:Any] {
            for (messageType, value) in receivedDict {
                switch messageType {
                case "detectedRectangle":
                    //These rectangles are in a coordinate space with lower left origin.
                    if let currentRectangle = value as? VNRectangleObservation {
                        box = currentRectangle
                    }
                    break
                case "savedBoxes":
                    print("Received savedBoxes")
                    
                    guard peerID == userCamPeer else {
                        print("I shouldn't receive a message with savedBoxes from someone that it is not the userCamPeer")
                        return
                    }
                    guard let dictionaryOfSavedBoxes = value as? [NSDictionary:VNRectangleObservation] else {
                        print("Couldn't get value from message")
                        return
                    }
                    
                    var orderedTemporalBoxes = [(CMTime,RectangleObservation)]()
                    for (timeBoxDictionary,box) in dictionaryOfSavedBoxes {
                        let timeBox = CMTimeMakeFromDictionary(timeBoxDictionary)
                        
                        orderedTemporalBoxes.append((timeBox,box))
                    }
                    
                    orderedTemporalBoxes.sort(by: { (tuple1, tuple2) -> Bool in
                        return CMTimeCompare(tuple1.0, tuple2.0) == -1
                    })
                    
                    let weakSelf = self
                    DispatchQueue.main.async {
                        for (time,box) in orderedTemporalBoxes {
                            let newBoxObservation = BoxObservation(context: weakSelf.coreDataContext)
                            newBoxObservation.value = time.value
                            newBoxObservation.timescale = time.timescale
                            newBoxObservation.observation = box
                            
                            weakSelf.videoModel.backgroundTrack?.addToBoxes(newBoxObservation)
                        }
                    }
                case "ACK":
                    guard let syncTime = syncTime else {
                        return
                    }
                    let delay = NSDate.network().timeIntervalSince(syncTime) / 2
                    switch peerID {
                    case wizardCamPeer:
                        videoModel.prototypeTrack?.camDelay = delay
                    case userCamPeer:
                        videoModel.backgroundTrack?.camDelay = delay
                    default:
                        print("Ignored ACK from unkown peerID \(peerID.displayName)")
                    }
                    
                    if let wizardCamDelay = videoModel.prototypeTrack?.camDelay, let userCamDelay = videoModel.backgroundTrack?.camDelay {
                        print("wizardCamDelay \(wizardCamDelay)")
                        print("userCamDelay \(userCamDelay)")
                        for (camPeer, camDelay) in [(wizardCamPeer,wizardCamDelay),(userCamPeer,userCamDelay)] {
                            sendMessage(peerID: camPeer!, dict:["startRecordingDate":syncTime.addingTimeInterval(countDownTimeInterval - camDelay)])
                        }
                        
                        let weakSelf = self
                        DispatchQueue.main.async {
                            weakSelf.countDownMethod()
                        }
                    }
                default:
                    print("Unrecognized message in receivedDict \(receivedDict)")
                }
            }

        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        if peerID == userCamPeer {
            userCamStreamer = InputStreamer(peerID,stream:stream)
            userCamStreamer?.delegate = self
        }
        if peerID == wizardCamPeer {
            wizardCamStreamer = InputStreamer(peerID,stream:stream)
            wizardCamStreamer?.delegate = self
        }

    }
    
    var prototypeReceptionProgress:Progress?
    var prototypeReceptionTimer:Timer?
    var backgroundReceptionProgress:Progress?
    var backgroundReceptionTimer:Timer?

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        guard "MONTAGE_CAM_MOVIE" == resourceName else {
            print("Ignoring didStartReceivingResourceWithName \(resourceName)")
            return
        }
        
        displayLink?.isPaused = true
        
        let weakSelf = self
        DispatchQueue.main.async {
            weakSelf.setImageOpenGL(view: weakSelf.prototypeFrameImageView, image: CIImage(image: #imageLiteral(resourceName: "white"))!)
            weakSelf.setImageOpenGL(view: weakSelf.backgroundFrameImageView, image: CIImage(image: #imageLiteral(resourceName: "white"))!)
            
            if peerID == weakSelf.wizardCamPeer {
                weakSelf.prototypeCanvasView.isHidden = true
                weakSelf.prototypeCanvasView.isUserInteractionEnabled = false
                
                weakSelf.prototypeReceptionProgress = progress
                
                DispatchQueue.main.async {
                    weakSelf.prototypeReceptionTimer = Timer.scheduledTimer(timeInterval: 0.1, target: weakSelf, selector: #selector(weakSelf.updatePrototypeReceptionProgress), userInfo: nil, repeats: true)
                    weakSelf.prototypeReceptionTimer?.fire()
                }
            }
            if peerID == weakSelf.userCamPeer {
                weakSelf.backgroundCanvasView.isHidden = true
                weakSelf.backgroundCanvasView.isUserInteractionEnabled = false
                
                weakSelf.backgroundReceptionProgress = progress
                
                DispatchQueue.main.async {
                    weakSelf.backgroundReceptionTimer = Timer.scheduledTimer(timeInterval: 0.1, target: weakSelf, selector: #selector(weakSelf.updateBackgroundReceptionProgress), userInfo: nil, repeats: true)
                    weakSelf.backgroundReceptionTimer?.fire()
                }
            }
        }
    }
    
    @objc func updatePrototypeReceptionProgress(){
        self.prototypeProgressBar.isHidden = false
        
        guard let receptionProgress = self.prototypeReceptionProgress else {
            self.prototypeReceptionTimer?.invalidate()
            return
        }
        
        self.prototypeProgressBar.progress = Float(receptionProgress.fractionCompleted)
        if receptionProgress.completedUnitCount >= receptionProgress.totalUnitCount {
            self.cleanPrototypeReception()
        }
    }
    
    func cleanPrototypeReception() {
        self.prototypeProgressBar.isHidden = true
        self.prototypeReceptionTimer?.invalidate()
    }
    
    @objc func updateBackgroundReceptionProgress(){
        self.backgroundProgressBar.isHidden = false
        
        guard let receptionProgress = self.backgroundReceptionProgress else {
            self.backgroundReceptionTimer?.invalidate()
            return
        }
        
        self.backgroundProgressBar.progress = Float(receptionProgress.fractionCompleted)
        if receptionProgress.completedUnitCount >= receptionProgress.totalUnitCount {
            cleanBackgroundReception()
        }
    }
    
    func cleanBackgroundReception() {
        self.backgroundProgressBar.isHidden = true
        self.backgroundReceptionTimer?.invalidate()
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard "MONTAGE_CAM_MOVIE" == resourceName else {
            print("Ignoring didFinishReceivingResourceWithName \(resourceName)")
            return
        }
        
        if let error = error {
            print("didFinishReceivingResourceWithName error:\(error.localizedDescription)")
            cleanPrototypeReception()
            cleanBackgroundReception()
            return
        }
        
        guard let localURL = localURL else {
            print("didFinishReceivingResourceWithName did not receive a proper file")
            cleanPrototypeReception()
            cleanBackgroundReception()
            return
        }
        
        print("*** didFinishReceivingResourceWithName \(resourceName)")
        
        let fileManager = FileManager.default
        
        if peerID == wizardCamPeer {
            let currentPrototypeVideoFileURL = self.videoModel.prototypeTrack!.fileURL
            
            if fileManager.fileExists(atPath: currentPrototypeVideoFileURL.path) {
                do {
                    try fileManager.removeItem(atPath: currentPrototypeVideoFileURL.path)
                } catch let error {
                    print("error occurred when deleting file prototype.mov: \(error)")
                    return
                }
            }
            
            do {
                try fileManager.copyItem(at: localURL, to: currentPrototypeVideoFileURL)
                self.videoModel.prototypeTrack?.hasVideoFile = true
            } catch {
                self.alert(error, title: "FileManager error", message: "Could not create prototype.mov")
                return
            }
            
        }
        if peerID == userCamPeer {
            let currentBackgroundVideoFileURL = self.videoModel.backgroundTrack!.fileURL
            
            if fileManager.fileExists(atPath: currentBackgroundVideoFileURL.path) {
                do {
                    try fileManager.removeItem(atPath: currentBackgroundVideoFileURL.path)
                } catch let error {
                    print("error occurred when deleting file background.mov: \(error)")
                    return
                }
            }
            
            do {
                try fileManager.copyItem(at: localURL, to: currentBackgroundVideoFileURL)
                self.videoModel.backgroundTrack?.hasVideoFile = true
            } catch {
                self.alert(error, title: "FileManager error", message: "Could not create background.mov")
                return
            }
        }
        
        
        if self.videoModel.prototypeTrack?.hasVideoFile == true && self.videoModel.backgroundTrack?.hasVideoFile == true{
            print("didFinishReceiving BOTH resources - trying to save in the DB")

            let weakSelf = self
            DispatchQueue.main.async {
                do {
                    try weakSelf.coreDataContext.save()
                    print("Saved successfuly in the DB")
                } catch {
                    weakSelf.alert(error, title: "DB", message: "Couldn't save video tracks after receiving their files")
                }
                weakSelf.canvasControllerMode = CanvasControllerPlayingMode(controller:weakSelf)
            }
        }
        
    }

    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        print("multipeer session didReceiveCertificate")
        certificateHandler(true)
    }
    
    //MARK: MCNearbyServiceBrowserDelegate
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        if let info = info {
            guard let value = info["role"], let rawValue = Int(value), let role = MontageRole(rawValue: rawValue) else {
                return
            }
            
            if [.undefined,.canvas].contains(role) {
                return
            }

            update(role: role, forPeer: peerID)

            let data = "MONTAGE_CANVAS".data(using: .utf8)
            if [wizardCamPeer,userCamPeer,mirrorPeer].contains(peerID) {
                print("browser NOT INVITING \(peerID.displayName)")
                return
            }
            print("browser.invitePeer \(peerID.displayName)")
            browser.invitePeer(peerID, to: multipeerSession, withContext: data, timeout: 30)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        //        browser.startBrowsingForPeers()
    }
    
    //-MARK: VideoPlayerDelegate
    
    func playPlayers() {
        let weakSelf = self
        
//        let playBlock = {
            weakSelf.prototypePlayer.play()
            weakSelf.backgroundPlayer.play()
            
            weakSelf.canvasControllerMode.resume(controller: weakSelf) //To the set the icon image and start recording user inputs
//        }
//
//        //TODO check this... suspicious
//        if CMTimeCompare(prototypePlayer.currentTime(), prototypePlayerItem!.duration) == 0 {
//            scrubbedToTime(0.0, completionBlock: playBlock)
//        } else {
//            playBlock()
//        }
    }
    
    func pausePlayers() {
        prototypePlayer.pause()
        backgroundPlayer.pause()
        
        canvasControllerMode.pause(controller: self) //This change the icon and stop recording user inputs
    }
    
    func playBackComplete() {
        //After playBackComplete the rate should be 0.0
        
        //        self.scrubberSlider.value = 0.0
        //        self.togglePlaybackButton.isSelected = false
        let weakSelf = self
//        backgroundPlayerItem?.cancelPendingSeeks()
//        backgroundPlayerItem?.seek(to: kCMTimeZero, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero) { (finishedBackgroundPlayerItem) in
//            weakSelf.prototypePlayerItem?.cancelPendingSeeks()
//            weakSelf.prototypePlayerItem?.seek(to: kCMTimeZero, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero) { (finishedPrototypePlayerItem) in
//                weakSelf.canvasControllerMode.pause(controller: weakSelf)
//            }
//        }
        pausePlayers()
        seekToTime(0.0)
    }
    
    func setCurrentTime(_ time:TimeInterval, duration:TimeInterval) {
        //        self.updateLabels(time,duration: duration)
        scrubberSlider.minimumValue = 0
        scrubberSlider.maximumValue = Float(duration)
        scrubberSlider.value = Float(time)
    }
    
    @IBAction func scrubbingDidStart() {
        self.pausePlayers()
        
        if let observer = self.periodicTimeObserver {
            prototypePlayer.removeTimeObserver(observer)
            self.periodicTimeObserver = nil
        }
    }
    
    @IBAction func scrubbingDidEnd() {
        //        self.updateLabels(CMTimeGetSeconds(self.player!.currentTime()),duration: CMTimeGetSeconds(self.playerItem!.duration))
        self.addPlayerItemPeriodicTimeObserver()
    }
    
    func seekToTime(_ time:TimeInterval, completionBlock:(()->Void)? = nil) {
        prototypePlayerItem?.cancelPendingSeeks()
        
        let seekingGroup = DispatchGroup()
        
        seekingGroup.enter()
        prototypePlayer.seek(to: CMTimeMakeWithSeconds(time, DEFAULT_TIMESCALE), toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero) { (completed) in
//        prototypePlayer.seek(to: CMTimeMakeWithSeconds(time, DEFAULT_TIMESCALE)) { (completed) in
            if !completed {
                print("prototypePlayer seek not completed in seekToTime")
            }
            seekingGroup.leave()
        }
        
        seekingGroup.enter()
        backgroundPlayerItem?.cancelPendingSeeks()
        backgroundPlayer.seek(to: CMTimeMakeWithSeconds(time, DEFAULT_TIMESCALE), toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero) { (completed) in
//        backgroundPlayer.seek(to: CMTimeMakeWithSeconds(time, DEFAULT_TIMESCALE)) { (completed) in
            if !completed {
                print("backgroundPlayer seek not completed in seekToTime")
            }
            seekingGroup.leave()
        }
        
        seekingGroup.notify(queue: DispatchQueue.main) {
            completionBlock?()
        }
    }
    
    //-MARK: Time Observers
    
    func addPlayerItemPeriodicTimeObserver() {
        if self.periodicTimeObserver != nil {
            print("We shouldn't call this method if there is already an observer addPlayerItemPeriodicTimeObserver()")
            return
        }
        
        // Create 0.5 second refresh interval - REFRESH_INTERVAL == 0.5
        let interval = CMTimeMakeWithSeconds(REFRESH_INTERVAL, DEFAULT_TIMESCALE)
        
        // Main dispatch queue
        let queue = DispatchQueue.main
        
        // Create callback block for time observer
        weak var weakSelf:CameraController! = self
        let callback = { (time:CMTime) -> Void in
            let currentTime = CMTimeGetSeconds(time)
            let duration = CMTimeGetSeconds(weakSelf.prototypePlayerItem!.duration)
            weakSelf.setCurrentTime(currentTime,duration:duration)
            //            weakSelf.updateFilmstripScrubber()
        }
        
        
        // Add observer and store pointer for future use
        self.periodicTimeObserver = prototypePlayer.addPeriodicTimeObserver(forInterval: interval, queue: queue, using:callback) as AnyObject?
    }
    
    func addDidPlayToEndItemEndObserverForPlayerItem() {
        weak var weakSelf:CameraController! = self

        self.itemEndObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: prototypePlayerItem, queue: OperationQueue.main, using: { (notification) -> Void in
            print("TRIGGERED addDidPlayToEndItemEndObserverForPlayerItem OBSERVER")
            weakSelf.playBackComplete()
        })
    }
    
    // MARK: Deinitialization of Streamers
    
    @objc func appWillWillEnterForeground(_ notification:Notification) {
        print("appWillWillEnterForeground")
        browser.startBrowsingForPeers()
        print("startBrowsingForPeers")
    }
    
    @objc func appWillResignActive(_ notification:Notification) {
        print("appWillResignActive")
//        for streamer in inputStreamers {
//            streamer.close()
//        }
        userCamStreamer?.close()
        wizardCamStreamer?.close()
        browser.stopBrowsingForPeers()
        print("stop browsing for peers")
    }
    
    @objc func appWillTerminate(_ notification:Notification) {
        print("appWillTerminate") //I think appWillResignActive is called before
        //        for streamer in inputStreamers {
        //            streamer.close()
        //        }
        
        userCamStreamer?.close()
        wizardCamStreamer?.close()
        browser.stopBrowsingForPeers()
        print("stop browsing for peers")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        print("viewWillDisappear")
        super.viewWillDisappear(animated)
        //        for streamer in inputStreamers {
        //            streamer.close()
        //        }
        userCamStreamer?.close()
        wizardCamStreamer?.close()
        browser.stopBrowsingForPeers()
        print("stop browsing for peers")
    }
}

extension CameraController:CanvasControllerModeDelegate {
    func startedLiveMode(mode:CanvasControllerLiveMode) {
        browser.startBrowsingForPeers()
    }
    
    func startedRecording(mode: CanvasControllerRecordingMode) {
        self.recordingIndicator.isHidden = false
        
        self.videoModel.prototypeTrack?.isRecordingInputs = true
        self.videoModel.backgroundTrack?.isRecordingInputs = true
        
        recordingIndicator.alpha = 0
        
        let options:UIViewAnimationOptions = [.allowUserInteraction,.autoreverse,.repeat]
        let weakSelf = self
        UIView.animate(withDuration: 0.5, delay: 0, options: options, animations: { () -> Void in
            weakSelf.recordingIndicator.alpha = 1.0
        }, completion: nil)
        
        saveButton.isEnabled = false
    }
    
    func cancelRecording(mode:CanvasControllerRecordingMode) {
        recordingIndicator.layer.removeAllAnimations()
        recordingIndicator.isHidden = true
        saveButton.isEnabled = true
        
        recordingControls.isHidden = true
        
        deleteVideoModel()
    }
    
    func cancelLiveMode(mode:CanvasControllerLiveMode) {
        deleteVideoModel()
    }
    
    func deleteVideoModel() {
        let weakSelf = self
        DispatchQueue.main.async {
            do {
                weakSelf.coreDataContext.delete(weakSelf.videoModel)
                try weakSelf.coreDataContext.save()
            } catch {
                weakSelf.alert(error, title: "DB", message: "Couldn't delete cancelled video")
            }
        }
    }
    
    func stopCamsStreaming() {
        for eachCam in cams {
            sendMessage(peerID: eachCam, dict: ["shouldStream":false])
        }
    }
    
    func stoppedRecording(mode: CanvasControllerRecordingMode) {
        recordingIndicator.layer.removeAllAnimations()
        recordingIndicator.isHidden = true
        saveButton.isEnabled = true
        
        recordingControls.isHidden = true
        
        self.videoModel.prototypeTrack?.isRecordingInputs = false
        self.videoModel.backgroundTrack?.isRecordingInputs = false
        
        var pausedTimeRangesToSend = [NSDictionary]()
        
        if let pausedTimeRanges = self.videoModel.pausedTimeRanges {
            for (index, eachPausedTimeRange) in pausedTimeRanges.enumerated() {
                print("\(index) pausedTimeRange \(eachPausedTimeRange)")
                if let dictPausedTimeRange = CMTimeRangeCopyAsDictionary(eachPausedTimeRange,kCFAllocatorDefault) {
                    pausedTimeRangesToSend.append(dictPausedTimeRange)
                }
            }
        }
        
        let dict = ["stopRecording":pausedTimeRangesToSend]
        let data = NSKeyedArchiver.archivedData(withRootObject: dict)
        
        do {
            try multipeerSession.send(data, toPeers: cams, with: .reliable)
        } catch let error as NSError {
            print("Could not send trigger to stop recording remote cams: \(error.localizedDescription)")
        }
    }
    func pausedRecording(mode:CanvasControllerRecordingMode) {
        recordingIndicator.layer.removeAllAnimations()
        recordingIndicator.alpha = 1.0
        recordingIndicator.textColor = UIColor.black
        
        self.videoModel.prototypeTrack?.isRecordingInputs = false
        self.videoModel.backgroundTrack?.isRecordingInputs = false
    }

    func resumedRecording(mode:CanvasControllerRecordingMode,pausedTimeRange:TimeRange?){
        recordingIndicator.textColor = UIColor.red
        recordingIndicator.alpha = 0
        
        let options:UIViewAnimationOptions = [.allowUserInteraction,.autoreverse,.repeat]
        let aRecordingIndicator = self.recordingIndicator
        UIView.animate(withDuration: 0.5, delay: 0, options: options, animations: { () -> Void in
            aRecordingIndicator?.alpha = 1.0
        }, completion: nil)
        
        if let pausedTimeRange = pausedTimeRange {
            videoModel.pausedTimeRanges?.append(pausedTimeRange)
        }
        
        self.videoModel.prototypeTrack?.isRecordingInputs = true
        self.videoModel.backgroundTrack?.isRecordingInputs = true

    }
    
    func startedPlaying(mode:CanvasControllerPlayingMode) {
        self.startPlayback()
    }
    
    func pausedPlaying(mode:CanvasControllerPlayingMode){
        playButton.setImage(UIImage(named:"play-icon"), for: UIControlState.normal)
        videoModel.backgroundTrack?.isRecordingInputs = false
        videoModel.prototypeTrack?.isRecordingInputs = false
    }
    func resumedPlaying(mode:CanvasControllerPlayingMode){
        playButton.setImage(UIImage(named:"pause-icon"), for: UIControlState.normal)
        videoModel.prototypeTrack?.isRecordingInputs = true
        videoModel.backgroundTrack?.isRecordingInputs = true
    }
    
    func playerItemOffset() -> TimeInterval {
        return prototypePlayerItem!.currentTime().seconds
    }
}

extension CameraController: CanvasViewDelegate {
    
    @objc func pannedOutsidePopopver() {
        if palettePopoverPresentationController != nil {
            presentedViewController?.dismiss(animated: false, completion: nil)
            palettePopoverPresentationController = nil
        }
    }
    
    func canvasTierRemoved(_ canvas: CanvasView, tier: Tier) {
        guard canvasControllerMode.isPlayingMode else {
            return
        }
        
        //I'm in playingMode
//        let syncLayer = canvas.associatedSyncLayer
        
        //TODO: We need to eliminate the associated animations, the rest happen in Tier >> prepareForDeletion
//        syncLayer?.removeAllAnimations()

    }
    
    func canvasTierAdded(_ canvas: CanvasView, tier: Tier) {
        tier.videoTrack?.deselectAllTiers()
        
        switch canvas {
        case prototypeCanvasView:
            prototypeTimeline?.select(tier:tier)
        case backgroundCanvasView:
            backgroundTimeline?.select(tier:tier)
        default:
            print("timeline for \(canvas) not found")
        }
        
         guard canvasControllerMode.isPlayingMode else {
            if canvasControllerMode.isRecording && canvasControllerMode.isPaused {
                if tier.appearAtTimes.isEmpty {
                    tier.shouldAppearAt(time:canvasControllerMode.currentTime)
                } else {
                    print("This is an error and it is happening because canvasTierAdded is called twice, check CanvasView >> touchesBegan/Ended")
                }
            }
            return
        }
        
        let shapeLayer = tier.shapeLayer
        canvas.removeAllSketches()
        let syncLayer = canvas.associatedSyncLayer
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        syncLayer?.addSublayer(shapeLayer)
        CATransaction.commit()
        
        switch prototypePlayer.timeControlStatus {
        case .playing:
            print("canvasTierAdded while playing: we need to create the animations, as always")
            tier.rebuildAnimations(forLayer:shapeLayer,totalRecordingTime: prototypePlayerItem!.duration.seconds)
        case .paused:
            print("canvasTierAdded while paused: appearedAtTimes = [\(prototypePlayerItem!.currentTime().seconds)]")
            if tier.appearAtTimes.isEmpty {
                tier.shouldAppearAt(time:prototypePlayerItem!.currentTime().seconds)
            } else {
                print("This is another error and it is happening because canvasTierAdded is called twice, check CanvasView >> touchesBegan/Ended")
            }
            
            tier.rebuildAnimations(forLayer:shapeLayer,totalRecordingTime: prototypePlayerItem!.duration.seconds)
        default:
            print("canvasTierAdded ignoring")
        }
    }
    
    func canvasTierModified(_ canvas: CanvasView, tier: Tier, type:TierModification) {
        switch canvasControllerMode {
        case is CanvasControllerLiveMode, is CanvasControllerRecordingMode:
            switch type {
                case .appear:
                    tier.shapeLayer.opacity = 1
                case .disappear:
                    tier.shapeLayer.opacity = 0
                default:
                    print("nothing")
            }
        case is CanvasControllerPlayingMode:
            //We redo the whole thing
            tier.rebuildAnimations(forLayer:tier.shapeLayer,totalRecordingTime: prototypePlayerItem!.duration.seconds)
        default:
            print("Unrecognized canvasControllerMode")
        }
        
    }
    
    func canvasLongPressed(_ canvas:CanvasView,touchLocation:CGPoint) {
        
        let paletteView = canvas.paletteView
        
        let paletteController = UIViewController()
        
        paletteController.view.translatesAutoresizingMaskIntoConstraints = false
        paletteController.modalPresentationStyle = UIModalPresentationStyle.popover
        let paletteHeight = paletteView.paletteHeight()
        
        paletteController.preferredContentSize = CGSize(width:Palette.initialWidth,height:paletteHeight)
        paletteController.view.frame = CGRect(x:0,y:0,width:Palette.initialWidth,height:paletteHeight)
        paletteView.frame = CGRect(x: 0, y: 0, width: paletteController.view.frame.width, height: paletteController.view.frame.height)
        paletteController.view.addSubview(paletteView)
        //        paletteView.frame = CGRect(x: 0, y: paletteController.view.frame.height - paletteHeight, width: paletteController.view.frame.width, height: paletteHeight)
        
        palettePopoverPresentationController = paletteController.popoverPresentationController
        
        paletteController.popoverPresentationController?.sourceView = canvas
        paletteController.popoverPresentationController?.sourceRect = CGRect(origin: touchLocation, size: CGSize.zero)
        
        let weakSelf = self
        present(paletteController, animated: true) {
            guard let v1 = paletteController.view?.superview?.superview?.superview else {
                return
            }
            
            guard let dimmingViewClass = NSClassFromString("UIDimmingView") else {
                return
            }
            for vx in v1.subviews {
                if vx.isKind(of: dimmingViewClass.self) {
                    let pan = UIPanGestureRecognizer(target: weakSelf, action: #selector(weakSelf.pannedOutsidePopopver))
                    pan.cancelsTouchesInView = false
                    pan.allowedTouchTypes = [NSNumber(value:UITouchType.stylus.rawValue)]
                    vx.addGestureRecognizer(pan)
                }
            }
        }
    }
    
    func canvasTierViewport(normalizedRect: CGRect) {
        videoModel.prototypeTrack?.viewportRect = normalizedRect
    }
    
    var currentTime: TimeInterval {
        return canvasControllerMode.currentTime
    }
    
    var shouldRecordInking: Bool {
        return canvasControllerMode.shouldRecordInking
    }
}

extension CameraController: UICollectionViewDelegate {
    
}

class TierCollectionDataSource:NSObject, UICollectionViewDataSource {
    var events = [CalendarEvent]()
    
    override init() {
        for _ in 0..<20 {
            events.append(CalendarEvent())
        }
    }
    
    func eventAt(indexPath:IndexPath) -> CalendarEvent {
        return events[indexPath.item]
    }
    
    func indexPathsOfEvents(betweenMinDayIndex minDayIndex:Int, maxDayIndex:Int,minStartHour:Int,maxStartHour:Int) -> [IndexPath] {
        var indexPaths = [IndexPath]()
        for (idx,event) in events.enumerated() {
            if event.day >= minDayIndex && event.day <= maxDayIndex && event.startHour >= minStartHour && event.startHour <= maxStartHour {
                let indexPath = IndexPath(item: idx, section: 0)
                indexPaths.append(indexPath)
            }
        }
        return indexPaths
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return events.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TIER_CELL", for: indexPath) as! TierCollectionViewCell
        let event = eventAt(indexPath: indexPath)
        cell.titleLabel.text = event.title
        return cell
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    
//    public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
//
//    }
    
//    public func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
//
//    }
    
//    public func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
//
//    }
    
//    public func indexTitles(for collectionView: UICollectionView) -> [String]? {
//
//    }
    
//    public func collectionView(_ collectionView: UICollectionView, indexPathForIndexTitle title: String, at index: Int) -> IndexPath {
//
//    }

}

class CalendarEvent {
    var title:String
    var day:Int
    var startHour:Int
    var durationInHours:Int
    
    init() {
        let randomID = arc4random_uniform(10000)
        title = "Event \(randomID)"
        day = Int(arc4random_uniform(7))
        startHour = Int(arc4random_uniform(20))
        durationInHours = Int(arc4random_uniform(5) + 1)
    }
    
}

extension CameraController: TimelineDelegate {
    func timelineDidStartViewporting() {
        if let canvasView = canvasControllerMode.isPlayingMode ? self.prototypePlayerCanvasView : self.prototypeCanvasView {
            canvasView.isViewporting = true
        }
    }
    
    func timeline(didSelectPrototypeTrack prototypeTrack:VideoTrack) {
        guard let selectedFileURL = prototypeTrack.loadedFileURL, let myFileURL = videoModel.prototypeTrack?.loadedFileURL else {
            return
        }
        
        let backupFileName = myFileURL.deletingPathExtension().lastPathComponent + "-backup." + myFileURL.pathExtension
        let backupFileURL = myFileURL.deletingLastPathComponent().appendingPathComponent(backupFileName)
        do {
            try FileManager.default.moveItem(at: myFileURL, to: backupFileURL)
        } catch {
            self.alert(error, title: "FileManager", message: "Couldn't backup the prototype video track \(myFileURL) to \(backupFileURL)")
            return
        }
        
        do {
            try FileManager.default.copyItem(at: selectedFileURL, to: myFileURL)
        } catch {
            self.alert(error, title: "FileManager", message: "Couldn't copy the selected prototype video track \(selectedFileURL) to \(myFileURL)")
            return
        }
        
        if canvasControllerMode.isPlayingMode {
            deinitPlaybackObjects()
            
            self.startPlayback()
        }
    }
    
    func timeline(didSelectNewVideo video: Video) {
        videoModel = video
        
        if canvasControllerMode.isPlayingMode {
            deinitPlaybackObjects()
            
            self.startPlayback()
        }
    }
}

//extension CameraController: TCMaskViewDelegate{
    //
    //    func tcMaskViewDidExit(mask: TCMask, image: UIImage) {
    //
    //    }
    //
    //    func tcMaskViewDidComplete(mask: TCMask, image: UIImage) {
    //        let outputImage = mask.cutout(image: image, resize: false)
    //        print(outputImage)
    //    }
    //
    ////    func tcMaskViewWillPushViewController(mask: TCMask, image: UIImage) -> UIViewController! {
    ////
    ////    }
    //
//}
