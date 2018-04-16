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

let STATUS_KEYPATH  = "status"
let REFRESH_INTERVAL = Float64(0.5)

let sampleBufferQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.default)

//let streamingQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_streaming_queue")
let streamingQueue1 = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_streaming_queue1", qos: DispatchQoS.userInteractive)
let streamingQueue2 = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_streaming_queue2", qos: DispatchQoS.userInteractive)
let mirrorQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_mirror_queue", qos: DispatchQoS.userInteractive)
let mirrorQueue2 = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_mirror_queue_2", qos: DispatchQoS.userInteractive)
let fps = 24.0

class InputStreamHandlerOwner:NSObject, InputStreamOwnerDelegate {
    //    var _dcache = NSMutableDictionary(capacity: 30)
    var inputStreamHandlers = Set<InputStreamHandler>()
    
    // MARK: InputStreamOwner
    func addInputStreamHandler(_ inputStreamHandler:InputStreamHandler) {
        inputStreamHandlers.insert(inputStreamHandler)
    }
    
    func removeInputStreamHandler(_ inputStreamHandler:InputStreamHandler) {
        inputStreamHandlers.remove(inputStreamHandler)
    }
    
    func free() {
        for anInputStreamHandler in inputStreamHandlers {
            anInputStreamHandler.close()
        }
    }
}

class CameraController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate, StreamDelegate, OutputStreamOwner {
//    let dataSource = TierCollectionDataSource()
//    @IBOutlet weak var tiersCollectionView:UICollectionView! {
//        didSet {
//            tiersCollectionView.delegate = self
//            tiersCollectionView.dataSource = dataSource
//        }
//    }
    lazy var removeGreenFilter = {
        return colorCubeFilterForChromaKey(hueAngle: 120)
    }()

    var prototypeTimeline:TimelineViewController?
    var backgroundTimeline:TimelineViewController?
    
    var isMirrorMode = false

    var lastTimeSent = Date()
    // MARK: Streaming Multipeer
    
    var outputStreamHandlers = Set<OutputStreamHandler>()
    
    // MARK: OutputStreamOwner
    func addOutputStreamHandler(_ outputStreamHandler:OutputStreamHandler) {
        outputStreamHandlers.insert(outputStreamHandler)
    }
    
    func removeOutputStreamHandler(_ outputStreamHandler:OutputStreamHandler) {
        outputStreamHandlers.remove(outputStreamHandler)
    }
    
    var ownerStream1 = InputStreamHandlerOwner()
    var ownerStream2 = InputStreamHandlerOwner()
    
    let coreDataContext = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
    var videoModel:Video!
    
    var prototypeVideoFileURL:URL?
    var backgroundVideoFileURL:URL?
    
    //AVPlaying
    var prototypeComposition:AVMutableComposition?
    var backgroundComposition:AVMutableComposition?
    
    @IBOutlet weak var recordingLabel:UILabel! {
        didSet {
//            let strokeTextAttributes: [NSAttributedStringKey : Any] = [
//                NSAttributedStringKey.strokeColor : UIColor.black,
//                NSAttributedStringKey.foregroundColor : UIColor.white,
//                NSAttributedStringKey.strokeWidth : -2.0,
//                ]
//            
//            recordingLabel.attributedText = NSAttributedString(string: "Foo", attributes: strokeTextAttributes)
        }
    }
    
    @IBOutlet weak var modalNavigationItem:UINavigationItem!
    @IBOutlet weak var recordingIndicator:UILabel!
    @IBOutlet weak var recordingControls:UISegmentedControl! {
        didSet {
            recordingControls.isHidden = true
        }
    }
//    @IBOutlet weak var stopRecordingButton:UIButton! {
//        didSet {
//            stopRecordingButton.isHidden = true
//
//        }
//    }

    @IBOutlet weak var saveButton:UIBarButtonItem!
    @IBOutlet weak var playButton:UIButton!
    @IBOutlet weak var playButtonContainer:UIBarButtonItem!
    @IBOutlet weak var scrubberButtonItem:UIBarButtonItem!
    @IBOutlet weak var scrubberSlider:UISlider!
    @IBOutlet weak var prototypeProgressBar:UIProgressView!
    @IBOutlet weak var backgroundProgressBar:UIProgressView!
    
    var periodicTimeObserver:AnyObject? = nil
    var itemEndObserver:NSObjectProtocol? = nil
    var lastPlaybackRate = Float(0)
    var previousRate:Float?

    private static var observerContext = 0
    var displayLink:CADisplayLink!
    
    var isPlaying:Bool? {
        didSet {
            guard let areWePlaying = isPlaying else {
                return
            }
            if areWePlaying {
                playButton.setImage(UIImage(named:"pause-icon"), for: UIControlState.normal)
                videoModel.prototypeTrack?.startRecording(time: Date().timeIntervalSince1970 - self.prototypePlayerItem.currentTime().seconds)
                videoModel.backgroundTrack?.startRecording(time: Date().timeIntervalSince1970 - self.backgroundPlayerItem.currentTime().seconds)
            } else {
                playButton.setImage(UIImage(named:"play-icon"), for: UIControlState.normal)
                videoModel.backgroundTrack?.stopRecording(time: Date().timeIntervalSince1970)
                videoModel.backgroundTrack?.stopRecording(time: Date().timeIntervalSince1970)
                
            }
        }
    }
    var prototypePlayerItem:AVPlayerItem!
    var prototypePlayer:AVPlayer!
    
    @IBOutlet weak var prototypePlayerView:VideoPlayerView!

    var backgroundPlayerItem:AVPlayerItem!
    var backgroundPlayer:AVPlayer!
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
    
    lazy var recordingCanvasViewManager = {
        return RecordingCanvasViewManager(controller: self)
    }()
    lazy var playbackCanvasViewManager = {
        return PlaybackCanvasViewManager(controller: self)
    }()
    
    @IBOutlet weak var prototypeCanvasView:CanvasView! {
        didSet {
            prototypeCanvasView.videoTrack = videoModel.prototypeTrack!
            prototypeCanvasView.delegate = recordingCanvasViewManager
        }
    }
    var prototypePlayerCanvasView:CanvasView? {
        didSet {
            prototypePlayerCanvasView?.videoTrack = videoModel.prototypeTrack!
            prototypePlayerCanvasView?.delegate = playbackCanvasViewManager
        }
    }
    
    @IBOutlet weak var backgroundCanvasView:CanvasView! {
        didSet {
            backgroundCanvasView.videoTrack = videoModel.backgroundTrack!
            backgroundCanvasView.delegate = recordingCanvasViewManager
        }
    }
    var backgroundPlayerCanvasView:CanvasView? {
        didSet {
            backgroundPlayerCanvasView?.videoTrack = videoModel.backgroundTrack!
            backgroundPlayerCanvasView?.delegate = playbackCanvasViewManager
        }
    }
    var backgroundPlayerSyncLayer:AVSynchronizedLayer?
    
    var box = VNRectangleObservation(boundingBox: CGRect.zero)
    
//    @IBOutlet weak var playerView:UIView!
    @IBOutlet weak var backgroundFrameImageView: UIImageView!
    @IBOutlet weak var prototypeFrameImageView: UIImageView!
    
    // MARK: Multipeer
    let localPeerID = MCPeerID(displayName: UIDevice.current.name)
    lazy var multipeerSession:MCSession = {
        let _session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: MCEncryptionPreference.optional)
        _session.delegate = self
        return _session
    }()
    
    lazy var browser:MCNearbyServiceBrowser = {
        let _browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: "multipeer-video")
        _browser.delegate = self
        return _browser
    }()
    
    var peersRoles = [String:MontageRole]()

    var cams:[MCPeerID] {
        return multipeerSession.connectedPeers.filter {
            guard let role = peersRoles[$0.displayName] else {
                return false
            }
            return role == .iphoneCam || role == .iPadCam
        }
    }
    
    var camBackgroundPeer:MCPeerID? {
//        print("camBackgroundPeer, amount of connected peers \(multipeerSession.connectedPeers.count)")
        let connectedCams = cams
        
        if connectedCams.count < 2 {
            return nil
        }
        let result = connectedCams.first {
            guard let role = peersRoles[$0.displayName] else {
                return false
            }
            return role == .iphoneCam
        }
        if result == nil && connectedCams.count >= 2, let otherCam = camPrototypePeer {
            return connectedCams.first {!$0.isEqual(otherCam)}
        }
        return result
    }
    
    var camPrototypePeer:MCPeerID? {
        let connectedPeers = multipeerSession.connectedPeers
        let padCams = connectedPeers.filter {
            guard let role = peersRoles[$0.displayName] else {
                return false
            }
            return role == .iPadCam
        }
        let phoneCams = connectedPeers.filter {
            guard let role = peersRoles[$0.displayName] else {
                return false
            }
            return role == .iphoneCam
        }
        if padCams.isEmpty && !phoneCams.isEmpty {
            return phoneCams.first
        }
        return padCams.first
        
    }
    
    var mirrorPeer:MCPeerID? {
        return multipeerSession.connectedPeers.first {
            guard let role = peersRoles[$0.displayName] else {
                return false
            }
            return role == .mirror //|| role == .iphoneCam TODO for the AppleWatch
        }
    }
    
    // MARK: Properties
//    lazy var videoAsset = {
//        return AVAsset(url: outputURL)
//    }()
    
    //    var catImage = UIImage(named:"cat")!
//    var catCIImage = CIImage(image: UIImage(named:"cat")!)
    let context =  CIContext()
    var backgroundCameraFrame:CIImage?
    var prototypeCameraFrame:CIImage?

    //    lazy var detector:CIDetector = {
    //        return CIDetector(ofType: CIDetectorTypeRectangle,
    //                              context: ciContext,
    //                              options: [CIDetectorAccuracy: CIDetectorAccuracyHigh, CIDetectorAspectRatio: 16/9])!
    //    }()
    
    // MARK: Vision.framework variables
//    var requests = [VNRequest]()
    
    // MARK: AVFoundation variables
//    var captureSession:AVCaptureSession
    
//    var syncLayer:AVSynchronizedLayer?
    
//    lazy var playerItem = {
//        return AVPlayerItem(asset: videoAsset)
//    }()
//    lazy var player = {
//        return AVPlayer(playerItem: playerItem)
//    }()
//    lazy var playerLayer = {
//        return AVPlayerLayer(player: player)
//    }()
    
    var recordStartedAt:TimeInterval = -1
    var recordingPauseStartedAt:TimeInterval = -1
    var isRecording = false {
        didSet {
            if isRecording {
                recordingIndicator.alpha = 0
                
                let options:UIViewAnimationOptions = [.allowUserInteraction,.autoreverse,.repeat]
                UIView.animate(withDuration: 0.5, delay: 0, options: options, animations: { () -> Void in
                    self.recordingIndicator.alpha = 1.0
                }, completion: nil)
                
                isLive = false
                saveButton.isEnabled = false
            } else {
                recordingIndicator.layer.removeAllAnimations()
                recordingIndicator.isHidden = true
                saveButton.isEnabled = true
            }
        }
    }
    var isUserOverlayActive = false
    var isLive = true
    var isRecordingPaused = false {
        didSet {
            if isRecordingPaused {
                recordingIndicator.layer.removeAllAnimations()
                recordingIndicator.alpha = 1.0
                recordingIndicator.textColor = UIColor.black
            } else {
                
                recordingIndicator.textColor = UIColor.red
                recordingIndicator.alpha = 0
                
                let options:UIViewAnimationOptions = [.allowUserInteraction,.autoreverse,.repeat]
                UIView.animate(withDuration: 0.5, delay: 0, options: options, animations: { () -> Void in
                    self.recordingIndicator.alpha = 1.0
                }, completion: nil)
            }
        }
    }
    
    lazy var videoDataOutput:AVCaptureVideoDataOutput = {
        let deviceOutput = AVCaptureVideoDataOutput()
        deviceOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        deviceOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue)
        return deviceOutput
    }()
    
    var activeVideoInput:AVCaptureDeviceInput?
    
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp.mov")
    
    var videoDimensions = CMVideoDimensions(width: 1920, height: 1080)
    
    // MARK: Initializers
    
    required init?(coder aDecoder: NSCoder) {
//        captureSession = AVCaptureSession()
        super.init(coder: aDecoder)
    }
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
//        captureSession = AVCaptureSession()
        super.init(nibName:nibNameOrNil, bundle:nibBundleOrNil)
    }
    
    deinit {
        ownerStream1.free()
        ownerStream2.free()
        
        for anOutputStreamHandler in outputStreamHandlers {
            anOutputStreamHandler.close()
        }
        
        //TODO: revise
        /*
        prototypePlayerItem.removeObserver(self, forKeyPath: STATUS_KEYPATH, context: &CameraController.observerContext)
        if let observer = self.timeObserver {
            self.prototypePlayer.removeTimeObserver(observer)
            self.timeObserver = nil
        }
        if let observer = self.itemEndObserver {
            NotificationCenter.default.removeObserver(observer)
            self.itemEndObserver = nil
        }
         */
    }

    
    // MARK: View Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        //Let's stretch the scrubber
        scrubberSlider.frame = CGRect(origin: scrubberSlider.frame.origin, size: CGSize(width:view!.frame.width - 165,height:scrubberSlider.frame.height))

        // Do any additional setup after loading the view.
//        cloudKitInitialize()
        
        initializeCaptureSession()
        
        //Multipeer connectivity
        browser.startBrowsingForPeers()
        
//        let displayLink = CADisplayLink(target: self, selector: #selector(snapshotSketchOverlay))
//        displayLink.add(to: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
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
    
    func initializeCaptureSession() {
//        configureCaptureSession()

//        startCaptureSession()
//        setupVisionDetection()
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
            backgroundTimeline = segue.destination as? TimelineViewController
            backgroundTimeline?.videoTrack = videoModel.backgroundTrack
        }
        if "PROTOTYPE_TIMELINE_SEGUE" == segue.identifier {
            prototypeTimeline = segue.destination as? TimelineViewController
            prototypeTimeline?.videoTrack = videoModel.prototypeTrack
        }
    }
    
    // MARK: - Actions
    
    
    @IBAction func playPressed(_ sender:AnyObject?) {
        if isPlaying == nil || isPlaying == false {
            play()
        } else {
            pause()
        }
    }
    
    @IBAction func savePressed(_ sender: Any) {
        do {
            displayLink.isPaused = true

//            if let backgroundMutableComposition = backgroundComposition {
//
//                let exportSession = AVAssetExportSession(asset: backgroundMutableComposition, presetName: AVAssetExportPreset1280x720)
//
//                let filter = CIFilter(name: "CIGaussianBlur")!
//                let videoComposition = AVVideoComposition(asset: backgroundMutableComposition, applyingCIFiltersWithHandler: { request in
//                    let seekerGroup = DispatchGroup()
//
//                    seekerGroup.enter()
//                    self.backgroundPlayerItem.seek(to: request.compositionTime, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero, completionHandler: { (finished) in
//                        seekerGroup.leave()
//                    })
//
//                    seekerGroup.enter()
//                    self.prototypePlayerItem.seek(to: request.compositionTime, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero, completionHandler: { (finished) in
//                        seekerGroup.leave()
//                    })
//
//                    seekerGroup.notify(queue: DispatchQueue.main, execute: {
//                        self.getFramesForPlayback()
//
//                        // Clamp to avoid blurring transparent pixels at the image edges
//                        let source = request.sourceImage.clampedToExtent()
//                        filter.setValue(source, forKey: kCIInputImageKey)
//
//                        // Vary filter parameters based on video timing
//                        let seconds = CMTimeGetSeconds(request.compositionTime)
//                        filter.setValue(seconds * 10.0, forKey: kCIInputRadiusKey)
//
//                        // Crop the blurred output to the bounds of the original image
//                        let output = filter.outputImage!.cropped(to: request.sourceImage.extent)
//
//                        // Provide the filter output to the composition
//                        request.finish(with: output, context: nil)
//                    })
//                })
//
//                exportSession?.outputFileType = AVFileType.mov
//                exportSession?.outputURL = videoModel.file!
//                exportSession?.videoComposition = videoComposition
//
//                exportSession?.exportAsynchronously {
//                    print("export")
//                }
//
//
//            }
            
            try coreDataContext.save()
            dismiss(animated: true, completion: nil)
        } catch {
            alert(error, title: "DB Error", message: "Could not save recorded video") {
                self.dismiss(animated: true, completion: nil)
            }
        }
    }
    
    @IBAction func cancelPressed(_ sender: Any) {
        NotificationCenter.default.post(Notification(name:Notification.Name(rawValue: "DELETE_RECORDING_VIDEO")))
        stopRecordingPressed()
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func menuPressed(_ sender: UIBarButtonItem) {
        let alertController = UIAlertController(title: nil, message: "Actions", preferredStyle: .actionSheet)
        
        let goLiveAction = UIAlertAction(title: "Go Live", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            self.livePressed()
        })
        
        goLiveAction.isEnabled = !isLive
        
        let startRecordingAction = UIAlertAction(title: "Start Recording", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            self.startRecordingPressed()
        })
        
        startRecordingAction.isEnabled = !isRecording
        
        let searchCamAction = UIAlertAction(title: "Connect Camera", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            self.searchForCam()
        })
        
        searchCamAction.isEnabled = !isRecording

        
        let searchMirrorAction = UIAlertAction(title: "Connect Mirror", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            self.searchForMirror()
        })
        
        searchMirrorAction.isEnabled = !isRecording
        
        let maskAction = UIAlertAction(title: "Extract Sketch", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            self.maskPressed()
        })
        
        let calibrateAction = UIAlertAction(title: "Calibrate Chroma", style: .default, handler: { (alert: UIAlertAction!) -> Void in

        })
        
        let userOverlayAction = UIAlertAction(title: "Toggle User Overlay", style: .default, handler: { (alert: UIAlertAction!) -> Void in
            self.isUserOverlayActive = !self.isUserOverlayActive
        })
        
        maskAction.isEnabled = !isRecording
        
        alertController.addAction(goLiveAction)
        alertController.addAction(startRecordingAction)
        alertController.addAction(searchCamAction)
        alertController.addAction(searchMirrorAction)
        alertController.addAction(maskAction)
        alertController.addAction(calibrateAction)
        alertController.addAction(userOverlayAction)
        
        if let popoverController = alertController.popoverPresentationController {
            popoverController.barButtonItem = sender
        }
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    func livePressed() {
        if !isRecording {
            //We remove the displayLink used to compose the video players
            displayLink.remove(from: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
            prototypePlayerView.isHidden = true
            
            prototypePlayerCanvasView?.removeFromSuperview() //TODO discard properly?
            prototypePlayerCanvasView = nil
            
            prototypeCanvasView.isHidden = false
            prototypeCanvasView.isUserInteractionEnabled = true
            
            backgroundPlayerCanvasView?.removeFromSuperview() //TODO discard properly?
            backgroundPlayerCanvasView = nil
            backgroundPlayerSyncLayer?.removeFromSuperlayer()
            backgroundPlayerSyncLayer = nil
            
            backgroundCanvasView.isHidden = false
            backgroundCanvasView.isUserInteractionEnabled = true
            
            playButtonContainer.isEnabled = false
            playButton.isEnabled = false
            scrubberSlider.isEnabled = false
            scrubberButtonItem.isEnabled = false
            
            let dict = ["streaming":true]
            let data = NSKeyedArchiver.archivedData(withRootObject: dict)
            
            do {
                try multipeerSession.send(data, toPeers: cams, with: .reliable)
            } catch let error as NSError {
                print("Could not send trigger to start streaming remote cams: \(error.localizedDescription)")
            }
            
            isLive = true
        }
    }
    
    @IBAction func recordingControlChanged(_ sender:UISegmentedControl) {
        let selectedSegment = sender.selectedSegmentIndex
        
        if (selectedSegment == 0) {
            if isRecordingPaused {
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
        if isRecording {
            let startTime = CMTime(seconds: recordingPauseStartedAt - recordStartedAt, preferredTimescale: DEFAULT_TIMESCALE)
            let durationInSeconds = Date().timeIntervalSince1970 - recordingPauseStartedAt
            let pausedTimeRange = CMTimeRange(start: startTime, duration: CMTimeMakeWithSeconds(durationInSeconds, DEFAULT_TIMESCALE))
            
            videoModel.pausedTimeRanges?.append(pausedTimeRange)
            
            self.videoModel.prototypeTrack?.resumeRecording()
            self.videoModel.backgroundTrack?.resumeRecording()
            isRecordingPaused = false
            
        } else {
            print("resumeRecordingPressed when isRecording == false?")
        }
    }
    
    func pauseRecordingPressed() {
        if isRecording {
            recordingPauseStartedAt = Date().timeIntervalSince1970
            
            self.videoModel.prototypeTrack?.pauseRecording()
            self.videoModel.backgroundTrack?.pauseRecording()
            isRecordingPaused = true
            
        } else {
            print("pauseRecordingPressed when isRecording == false?")
        }
    }
    
    func stopRecordingPressed() {
        if isRecording {
            recordingControls.isHidden = true
            isRecording = false
            
            self.videoModel.prototypeTrack?.stopRecording(time:Date().timeIntervalSince1970)
            self.videoModel.backgroundTrack?.stopRecording(time:Date().timeIntervalSince1970)
            
            let dict = ["stopRecording":true]
            let data = NSKeyedArchiver.archivedData(withRootObject: dict)
            
            do {
                try multipeerSession.send(data, toPeers: cams, with: .reliable)
            } catch let error as NSError {
                print("Could not send trigger to stop recording remote cams: \(error.localizedDescription)")
            }
            
        } else {
            print("stopRecordingPressed when isRecording == false?")
        }
    }
    
    func startRecordingPressed() {
        if !isRecording {
            let startRecordingDate = Date().addingTimeInterval(3)
            recordStartedAt = startRecordingDate.timeIntervalSince1970
            
            recordingControls.isHidden = false
            
            countDownMethod()
            
            let timer = Timer(fire: startRecordingDate, interval: 0, repeats: false, block: { (timer) in
                self.isRecording = true
                self.recordingIndicator.isHidden = false

                self.videoModel.prototypeTrack?.startRecording(time:Date().timeIntervalSince1970)
                self.videoModel.backgroundTrack?.startRecording(time:Date().timeIntervalSince1970)
                print("START RECORDING!!!! NOW! \(Date().timeIntervalSince1970)")
                timer.invalidate()
            })
            RunLoop.main.add(timer, forMode: RunLoopMode.commonModes)

            let dict = ["startRecordingDate":startRecordingDate]
            let data = NSKeyedArchiver.archivedData(withRootObject: dict)
            
            do {
                try multipeerSession.send(data, toPeers: cams, with: .reliable)
            } catch let error as NSError {
                print("Could not send trigger to start recording the remote cams: \(error.localizedDescription)")
            }
            
        } else {
            print("startRecordingPressed when isRecording == true?")
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
    
    func sendMessage(peerID:MCPeerID,dict:[String:Any]) {
        let data = NSKeyedArchiver.archivedData(withRootObject: dict)

        do {
            try multipeerSession.send(data, toPeers: [peerID], with: .reliable)
        } catch let error as NSError {
            print("Could not send dict message: \(error.localizedDescription)")
        }
    }
    
    @objc func countDownMethod() {
        if (recordingLabel.isHidden) {
            view.bringSubview(toFront: recordingLabel)
            recordingLabel.isHidden = false
            recordingLabel.text = "3"
            self.perform(#selector(countDownMethod), with: nil, afterDelay: 1.0)
        } else if(recordingLabel.text! == "3") {
            recordingLabel.text = "2"
            self.perform(#selector(countDownMethod), with: nil, afterDelay: 1.0)
        } else if recordingLabel.text! == "2" {
            recordingLabel.text = "1"
            self.perform(#selector(countDownMethod), with: nil, afterDelay: 1.0)
        } else if recordingLabel.text! == "1" {
            recordingLabel.text = "GO"
            
            UIView.animate(withDuration: 0.5, animations: {[unowned self] in
                self.recordingLabel.alpha = 0
            }, completion: { [unowned self] (completed) in
                self.recordingLabel.isHidden = true
            })
        }
    }
    
    @IBAction func sliderChanged(_ sender:UISlider) {
//        let trackRect = scrubberSlider.trackRect(forBounds: scrubberSlider.bounds)
//        let thumbRect = scrubberSlider.thumbRect(forBounds: scrubberSlider.bounds, trackRect: trackRect, value: scrubberSlider.value)
        
        self.scrubbedToTime(Double(scrubberSlider.value))
    }
    
    // MARK: Capture Session
    
//    func startCaptureSession() {
//        let weakSelf = self
//        sampleBufferQueue.async {
//            weakSelf.captureSession.startRunning()
//        }
//    }
    
//    func stopSession() {
//        //Because we call stopSession in deinit we need to retain the variable
//        let captureSession = self.captureSession
//        sampleBufferQueue.async {
//            //In here, self is deallocated already
//            captureSession.stopRunning()
//        }
//    }
    
//    func configureCaptureSession() {
//        captureSession.sessionPreset = AVCaptureSession.Preset.medium
//
//        //Setup default video camera device
//        guard let videoDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
//            let alertController = UIAlertController(title: "Video not available", message: "Could not access the video camera device", preferredStyle: UIAlertControllerStyle.alert)
//            present(alertController, animated: true, completion: nil)
//            return
//        }
//
//        let videoInput:AVCaptureDeviceInput
//
//        do {
//            videoInput = try AVCaptureDeviceInput(device: videoDevice)
//        } catch let error as NSError {
//            let alertController = UIAlertController(title: "Video not available", message: "Could not access the video camera input: \(error.localizedDescription)", preferredStyle: UIAlertControllerStyle.alert)
//            present(alertController, animated: true, completion: nil)
//            return
//        }
//
//        videoDimensions = CMVideoFormatDescriptionGetDimensions(videoInput.device.activeFormat.formatDescription)
//
//        if captureSession.canAddInput(videoInput) {
//            captureSession.addInput(videoInput)
//            activeVideoInput = videoInput
//        }
//
//        //Setup default microphone
//        guard let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio) else {
//            let alertController = UIAlertController(title: "Audio not available", message: "Could not access the audio device", preferredStyle: UIAlertControllerStyle.alert)
//            present(alertController, animated: true, completion: nil)
//            return
//        }
//
//        let audioInput:AVCaptureDeviceInput
//
//        do {
//            audioInput = try AVCaptureDeviceInput(device: audioDevice)
//        } catch let error as NSError {
//            let alertController = UIAlertController(title: "Audio not available", message: "Could not access the audio input: \(error.localizedDescription)", preferredStyle: UIAlertControllerStyle.alert)
//            present(alertController, animated: true, completion: nil)
//            return
//        }
//
//        if captureSession.canAddInput(audioInput) {
//            captureSession.addInput(audioInput)
//        }
//
//        //Setup the movie file output
//
//        //        if captureSession.canAddOutput(movieFileOutput) {
//        //            captureSession.addOutput(movieFileOutput)
//        //        }
//
//        //Setup the video data output
//
//        if captureSession.canAddOutput(videoDataOutput) {
//            captureSession.addOutput(videoDataOutput)
//        }
//
//        let fileType = AVFileType.mov
//        if let videoSettings = videoDataOutput.recommendedVideoSettings(forVideoCodecType: AVVideoCodecType.h264, assetWriterOutputFileType: fileType) as? [String:Any] {
//            var extendedVideoSettings = videoSettings
//            //            extendedVideoSettings[AVVideoCompressionPropertiesKey] = [
//            //                AVVideoAverageBitRateKey : ,
//            //                AVVideoProfileLevelKey : AVVideoProfileLevelH264Main31, /* Or whatever profile & level you wish to use */
//            //                AVVideoMaxKeyFrameIntervalKey :
//            //            ]
//
//            movieWriter = MovieWriter(extendedVideoSettings)
//            movieWriter?.delegate = self
//        }
//    }
    
    // MARK: Movie Writer Delegate
    
//    func didWriteMovie(atURL outputURL:URL) {
//        print("Succesfuly created internal movie file at \(outputURL)")
//        prototypeVideoFileURL = outputURL
//    }
    
    func startPlayback() {
        //We should start showing the prototype AVPlayer and enabling the player controls
        guard let prototypeVideoFileURL = prototypeVideoFileURL, let backgroundVideoFileURL = backgroundVideoFileURL else {
            print("Cannot start playback, missing movie/s")
            return
        }
        
        let assetLoadingGroup = DispatchGroup();
        
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
        
        assetLoadingGroup.notify(queue: DispatchQueue.main) {[unowned self] in
            print("Prototype duration \(prototypeAsset.duration)")
            print("Background duration \(backgroundAsset.duration)")
            let smallestDuration = CMTimeCompare(backgroundAsset.duration, prototypeAsset.duration) < 0 ? backgroundAsset.duration : prototypeAsset.duration

            self.prototypeComposition = AVMutableComposition()
            guard let prototypeCompositionVideoTrack = self.prototypeComposition?.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                self.alert(nil, title: "Playback error", message: "Could not create compositionVideoTrack for prototype")
                return
            }
            //        let compositionAudioTrack = prototypeComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            
            guard let prototypeAssetVideoTrack = prototypeAsset.tracks(withMediaType: .video).first else {
                self.alert(nil, title: "Playback error", message: "The prototype video file does not have any video track")
                return
            }
            
            let prototypeCompositionVideoTimeRange = CMTimeRange(start: kCMTimeZero, duration: smallestDuration)
            
            do {
                try prototypeCompositionVideoTrack.insertTimeRange(prototypeCompositionVideoTimeRange, of: prototypeAssetVideoTrack, at: kCMTimeZero)
            } catch {
                self.alert(nil, title: "Playback error", message: "Could not insert video track in prototype  compositionVideoTrack")
                return
            }
            
            for pausedTimeRange in self.videoModel.pausedTimeRanges!.reversed() {
                print("Skipping \(pausedTimeRange)")
                prototypeCompositionVideoTrack.removeTimeRange(pausedTimeRange)
            }
            
            self.prototypePlayerItem = AVPlayerItem(asset: self.prototypeComposition!,automaticallyLoadedAssetKeys:["tracks","duration"])
            
            self.prototypePlayerItem.addObserver(self, forKeyPath: "rate", options: NSKeyValueObservingOptions.initial, context: &CameraController.observerContext)
            
            self.prototypePlayer = AVPlayer(playerItem: self.prototypePlayerItem)
            self.prototypePlayerView.player = self.prototypePlayer
            self.prototypePlayerView.isHidden = false
            self.prototypeCanvasView.isHidden = true
            self.prototypeCanvasView.isUserInteractionEnabled = false
            
            self.prototypePlayerItem.add(self.prototypeVideoOutput)
            
            self.backgroundComposition = AVMutableComposition()
            guard let backgroundCompositionVideoTrack = self.backgroundComposition?.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                self.alert(nil, title: "Playback error", message: "Could not create compositionVideoTrack for background")
                return
            }
            //        let compositionAudioTrack = prototypeComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            
            guard let backgroundAssetVideoTrack = backgroundAsset.tracks(withMediaType: .video).first else {
                self.alert(nil, title: "Playback error", message: "The background video file does not have any video track")
                return
            }
            
            let backgroundCompositionVideoTimeRange = CMTimeRange(start: kCMTimeZero, duration: smallestDuration)
            
            do {
                try backgroundCompositionVideoTrack.insertTimeRange(backgroundCompositionVideoTimeRange, of: backgroundAssetVideoTrack, at: kCMTimeZero)
            } catch {
                self.alert(nil, title: "Playback error", message: "Could not insert video track in background  compositionVideoTrack")
                return
            }
            
            for pausedTimeRange in self.videoModel.pausedTimeRanges!.reversed() {
                backgroundCompositionVideoTrack.removeTimeRange(pausedTimeRange)
            }
            
            self.backgroundPlayerItem = AVPlayerItem(asset: self.backgroundComposition!,automaticallyLoadedAssetKeys:["tracks","duration"])
            self.backgroundPlayer = AVPlayer(playerItem: self.backgroundPlayerItem)
            self.backgroundCanvasView.isHidden = true
            self.backgroundCanvasView.isUserInteractionEnabled = false
            
            //        let backgroundPlayerView = VideoPlayerView()
            //        backgroundPlayerView.translatesAutoresizingMaskIntoConstraints = false
            //        backgroundPlayerView.player = backgroundPlayer
            //        backgroundPlayerView.frame = CGRect(x: 0, y: 500, width: 480, height: 360)
            //        view.addSubview(backgroundPlayerView)
            
            self.backgroundPlayerItem.add(self.backgroundVideoOutput)
            self.backgroundVideoOutput.suppressesPlayerRendering = true
            
            //Prototype Player Canvas View
            self.prototypePlayerCanvasView = CanvasView(frame: self.view.convert(CGRect(origin:CGPoint.zero,size:self.prototypeCanvasView.frame.size), from: self.prototypeCanvasView))
            self.prototypePlayerCanvasView?.videoTrack = self.videoModel.prototypeTrack
            self.prototypePlayerCanvasView!.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(self.prototypePlayerCanvasView!)
            
            self.prototypePlayerView.syncLayer = AVSynchronizedLayer(playerItem: self.prototypePlayerItem)
            
            self.prototypePlayerCanvasView?.associatedSyncLayer = self.prototypePlayerView.syncLayer
            
            for tier in self.prototypePlayerCanvasView?.videoTrack.tiers!.array as! [Tier] {
                let shapeLayer = tier.shapeLayer
                
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.prototypePlayerView.syncLayer?.addSublayer(shapeLayer)
                CATransaction.commit()
                
                let (appearAnimation,strokeEndAnimation,transformationAnimation) = tier.buildAnimations()
                
                if let strokeEndAnimation = strokeEndAnimation {
                    shapeLayer.strokeEnd = 0
                    shapeLayer.add(strokeEndAnimation, forKey: strokeEndAnimation.keyPath!)
                }
                
                if let transformationAnimation = transformationAnimation {
                    shapeLayer.transform = CATransform3DIdentity
                    shapeLayer.add(transformationAnimation, forKey: transformationAnimation.keyPath!)
                }
                
                if let appearAnimation = appearAnimation {
                    shapeLayer.add(appearAnimation, forKey: appearAnimation.keyPath!)
                }
            }
            
            //Background Player Canvas View
            self.backgroundPlayerCanvasView = CanvasView(frame: self.view.convert(CGRect(origin:CGPoint.zero,size:self.backgroundCanvasView.frame.size), from: self.backgroundCanvasView))
            self.backgroundPlayerCanvasView?.videoTrack = self.videoModel.backgroundTrack
            self.backgroundPlayerCanvasView!.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(self.backgroundPlayerCanvasView!)
            
            self.backgroundPlayerSyncLayer = AVSynchronizedLayer(playerItem: self.backgroundPlayerItem)
            self.backgroundFrameImageView.layer.addSublayer(self.backgroundPlayerSyncLayer!)
            
            self.backgroundPlayerCanvasView?.associatedSyncLayer = self.backgroundPlayerSyncLayer
            
            for tier in self.backgroundPlayerCanvasView!.videoTrack.tiers!.array as! [Tier] {
                let shapeLayer = tier.shapeLayer
                
                self.backgroundPlayerSyncLayer!.addSublayer(shapeLayer)
                
                let (appearAnimation,strokeEndAnimation,transformationAnimation) = tier.buildAnimations()
                
                if let strokeEndAnimation = strokeEndAnimation {
                    shapeLayer.strokeEnd = 0
                    shapeLayer.add(strokeEndAnimation, forKey: strokeEndAnimation.keyPath!)
                }
                
                if let transformationAnimation = transformationAnimation {
                    shapeLayer.transform = CATransform3DIdentity
                    shapeLayer.add(transformationAnimation, forKey: transformationAnimation.keyPath!)
                }
                
                if let appearAnimation = appearAnimation {
                    shapeLayer.add(appearAnimation, forKey: appearAnimation.keyPath!)
                }
            }
            
            self.playButtonContainer.isEnabled = true
            self.playButton.isEnabled = true
            self.scrubberSlider.isEnabled = true
            self.scrubberButtonItem.isEnabled = true
            
            self.displayLink = CADisplayLink(target: self, selector: #selector(self.displayLinkDidRefresh(displayLink:)))
            self.displayLink.preferredFramesPerSecond = 30
            self.displayLink.isPaused = true
            self.displayLink.add(to: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
            
            self.prototypePlayerItem.addObserver(self, forKeyPath: STATUS_KEYPATH, options: NSKeyValueObservingOptions(rawValue: 0), context: &CameraController.observerContext)
//            self.prototypePlayer.addObserver(self, forKeyPath: "rate", options: NSKeyValueObservingOptions.initial, context: &CameraController.observerContext)

            
            self.backgroundPlayer.play()
            self.prototypePlayer.play()
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change:
        [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

        if let object = object, context! == &CameraController.observerContext {
            if prototypePlayerItem.isEqual(object) {
                guard prototypePlayerItem.status == AVPlayerItemStatus.readyToPlay else {
                    print("Error, failed to load video")
                    return
                }
                let duration = prototypePlayerItem.duration
                
                let weakSelf = self
                DispatchQueue.main.async(execute: { () -> Void in
                    weakSelf.setCurrentTime(CMTimeGetSeconds(kCMTimeZero),duration:CMTimeGetSeconds(duration))
                    weakSelf.displayLink.isPaused = false
                    weakSelf.addPlayerItemPeriodicTimeObserver()
                    weakSelf.addDidPlayToEndItemEndObserverForPlayerItem()
                })
            }
//            if prototypePlayer.isEqual(object) {
//                if let player = object as? AVPlayer {
//                    let currentRate = player.rate
//                    if previousRate == nil {
//                        previousRate = currentRate
//                    }
//                    if previousRate! > 0 && currentRate == 0 {
//                        //paused
//                        videoModel.backgroundTrack?.stopRecording()
//                        videoModel.backgroundTrack?.stopRecording()
//                    }
//                    if previousRate! == 0 && currentRate > 0 {
//                        //played
//                        videoModel.prototypeTrack?.startRecording()
//                        videoModel.backgroundTrack?.startRecording()
//                    }
//                    previousRate = currentRate
//                }
//            }
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
        
        getFramesForPlayback()
    }
    
    func getFramesForPlayback() {
        let currentMediaTime = CACurrentMediaTime()

        let prototypeItemTime = prototypeVideoOutput.itemTime(forHostTime: currentMediaTime)
        let backgroundItemTime = backgroundVideoOutput.itemTime(forHostTime: currentMediaTime)
        
        let weakSelf = self
        DispatchQueue.main.async {
            if let copiedSyncLayer = weakSelf.prototypePlayerView.syncLayer?.presentation(), let copiedCanvasLayer = weakSelf.prototypePlayerCanvasView?.canvasLayer.presentation() {
                weakSelf.snapshotSketchOverlay(layers:[copiedSyncLayer,copiedCanvasLayer],size:weakSelf.prototypePlayerView.frame.size)
            } else {
                print("Could not get presentation()")
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
                
                let weakSelf = self
                
                sampleBufferQueue.async {
                    if let obtainedBox = weakSelf.videoModel.backgroundTrack?.box(forItemTime: prototypeItemTime, adjustment: 0.035) {
                        weakSelf.box = obtainedBox
                    } else {
                        print("box(forItemTime: ...) returned nil")
                    }
                    weakSelf.applyFilterFromPrototypeToBackground(prototypePixelBuffer)
                }
            } else {
                print("prototypePixelBuffer FAIL")
            }
        }// else {
        //            print("prototypeVideoOutput NOT hasNewPixelBuffer")
        //        }
        
        //        print("---")
        //        if let backgroundPixelBuffer = backgroundPixelBuffer {
        //            externalCameraFrame = UIImage(ciImage: CIImage(cvPixelBuffer: backgroundPixelBuffer))
        //        }
        //
        //        if let prototypePixelBuffer = prototypePixelBuffer {
        //            applyFilterFromPrototypeToBackground(prototypePixelBuffer,ignoreSketchOverlay: true)
        //        }
    }
    
    // MARK: Video Output Sample Buffer Delegate
    
//    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//
//        movieWriter?.process(sampleBuffer: sampleBuffer)
//
//        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
//            return
//        }
//
//        // VERSION CORE IMAGE
//        /*
//         let monaLisa = CIImage(image: catImage)!
//         let backgroundImage = CIImage(cvPixelBuffer: pixelBuffer)
//
//         let colorMatrix = CIFilter(name:"CIColorMatrix")!
//
//         colorMatrix.setDefaults()
//         colorMatrix.setValue(backgroundImage, forKey: kCIInputImageKey)
//
//         colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
//         colorMatrix.setValue(CIVector(x: -5, y: 5, z: -5, w: 0), forKey: "inputGVector")
//         colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
//         colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
//         colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
//
//         let onlyGreenBackgroundImage = colorMatrix.outputImage!
//
//         if let rect = detector.features(in: onlyGreenBackgroundImage).first as? CIRectangleFeature {
//         //We got a rectangle detected
//
//         let perspectiveTransform = CIFilter(name: "CIPerspectiveTransform")!
//
//         perspectiveTransform.setValue(CIVector(cgPoint:rect.topLeft),
//         forKey: "inputTopLeft")
//         perspectiveTransform.setValue(CIVector(cgPoint:rect.topRight),
//         forKey: "inputTopRight")
//         perspectiveTransform.setValue(CIVector(cgPoint:rect.bottomRight),
//         forKey: "inputBottomRight")
//         perspectiveTransform.setValue(CIVector(cgPoint:rect.bottomLeft),
//         forKey: "inputBottomLeft")
//         perspectiveTransform.setValue(monaLisa,
//         forKey: kCIInputImageKey)
//
//         let composite = CIFilter(name: "CISourceAtopCompositing")!
//
//         composite.setValue(backgroundImage,
//         forKey: kCIInputBackgroundImageKey)
//         composite.setValue(perspectiveTransform.outputImage!,
//
//         forKey: kCIInputImageKey)
//
//         DispatchQueue.main.async {
//         self.imageView.image = UIImage(ciImage:composite.outputImage!)
//         }
//         return
//         }*/
//
//        // VERSION VISION
//        snapshotSketchOverlay(layer: prototypeCanvasView.canvasLayer,size: prototypeCanvasView.frame.size)
//
//        applyFilterFromPrototypeToBackground(pixelBuffer)
////        DispatchQueue.main.async {
////            self.imageView.image = self.currentFrame
////        }
//    }
    
    func cgImageBackedImage(withCIImage ciImage:CIImage) -> UIImage? {
        guard let ref = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let image = UIImage(cgImage: ref, scale: UIScreen.main.scale, orientation: UIImageOrientation.up)
        
        return image;
    }
    
    func applyFilterFromPrototypeToBackground(_ pixelBuffer:CVImageBuffer) {
        applyFilterFromPrototypeToBackground(source:CIImage(cvPixelBuffer: pixelBuffer))
    }
    
    func applyFilterFromPrototypeToBackground(source:CIImage) {

        let currentPrototypeAndOverlayFrame:CIImage
        
        if let overlay = sketchOverlay {
            let scaledSource = source.transformed(by: CGAffineTransform.identity.scaledBy(x: overlay.extent.width / source.extent.width, y: overlay.extent.height / source.extent.height ))
            
            let overlayFilter = CIFilter(name: "CISourceOverCompositing")!
            overlayFilter.setValue(scaledSource, forKey: kCIInputBackgroundImageKey)
            overlayFilter.setValue(overlay, forKey: kCIInputImageKey)
            
            currentPrototypeAndOverlayFrame = overlayFilter.outputImage!
        } else {
            currentPrototypeAndOverlayFrame = source
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
        
        guard let currentBrackgroundFrameImage = backgroundCameraFrame else {
            let weakSelf = self
            DispatchQueue.main.async {
                weakSelf.prototypeFrameImageView.image = UIImage(ciImage:source)
            }
            return
        }
        
        //If we have
            guard let scaleFilter = CIFilter(name: "CILanczosScaleTransform") else {
                return
            }
            scaleFilter.setValue(currentBrackgroundFrameImage, forKey: "inputImage")
            let increaseFactor = 1/0.25
            scaleFilter.setValue(increaseFactor, forKey: "inputScale")
            scaleFilter.setValue(1.0, forKey: "inputAspectRatio")
            
            guard let finalBackgroundFrameImage = scaleFilter.outputImage else {
                return
            }
            
            let perspectiveTransformFilter = CIFilter(name: "CIPerspectiveTransform")!
            
            let w = finalBackgroundFrameImage.extent.size.width
            let h = finalBackgroundFrameImage.extent.size.height
        
            let currentBox = box
        
            perspectiveTransformFilter.setValue(CIVector(cgPoint:CGPoint(x: currentBox.topLeft.x * w, y: h * (1 - currentBox.topLeft.y))), forKey: "inputTopLeft")
            perspectiveTransformFilter.setValue(CIVector(cgPoint:CGPoint(x: currentBox.topRight.x * w, y: h * (1 - currentBox.topRight.y))), forKey: "inputTopRight")
            perspectiveTransformFilter.setValue(CIVector(cgPoint:CGPoint(x: currentBox.bottomRight.x * w, y: h * (1 - currentBox.bottomRight.y))), forKey: "inputBottomRight")
            perspectiveTransformFilter.setValue(CIVector(cgPoint:CGPoint(x: currentBox.bottomLeft.x * w, y: h * (1 - currentBox.bottomLeft.y))), forKey: "inputBottomLeft")
            //        perspectiveTransform.setValue(CIVector(cgPoint:currentBox.topLeft.scaled(to: ciSize)), forKey: "inputTopLeft")
            //        perspectiveTransform.setValue(CIVector(cgPoint:currentBox.topRight.scaled(to: ciSize)), forKey: "inputTopRight")
            //        perspectiveTransform.setValue(CIVector(cgPoint:currentBox.bottomRight.scaled(to: ciSize)), forKey: "inputBottomRight")
            //        perspectiveTransform.setValue(CIVector(cgPoint:currentBox.bottomLeft.scaled(to: ciSize)), forKey: "inputBottomLeft")
            perspectiveTransformFilter.setValue(currentPrototypeAndOverlayFrame.oriented(CGImagePropertyOrientation.downMirrored),
                                                forKey: kCIInputImageKey)
            
            
            let composite = ChromaKeyFilter()
            composite.inputImage = finalBackgroundFrameImage
            composite.backgroundImage = perspectiveTransformFilter.outputImage
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
            
            //GHOST
        
            //We do a CIPerspectiveCorrection of the green area finalBackgroundFrameImage
            
            let perspectiveCorrection = CIFilter(name: "CIPerspectiveCorrection")!
        
//            perspectiveCorrection.setValue(CIVector(cgPoint:CGPoint(x: currentBox.topLeft.x, y: currentBox.topLeft.y)), forKey: "inputTopLeft")
//            perspectiveCorrection.setValue(CIVector(cgPoint:CGPoint(x: currentBox.topRight.x, y: currentBox.topRight.y)), forKey: "inputTopRight")
//            perspectiveCorrection.setValue(CIVector(cgPoint:CGPoint(x: currentBox.bottomRight.x, y: currentBox.bottomRight.y)), forKey: "inputBottomRight")
//            perspectiveCorrection.setValue(CIVector(cgPoint:CGPoint(x: currentBox.bottomLeft.x, y: currentBox.bottomLeft.y)), forKey: "inputBottomLeft")
        
            perspectiveCorrection.setValue(perspectiveTransformFilter.value(forKey: "inputTopLeft"),
                                           forKey: "inputTopLeft")
            perspectiveCorrection.setValue(perspectiveTransformFilter.value(forKey: "inputTopRight"),
                                           forKey: "inputTopRight")
            perspectiveCorrection.setValue(perspectiveTransformFilter.value(forKey: "inputBottomRight"),
                                           forKey: "inputBottomRight")
            perspectiveCorrection.setValue(perspectiveTransformFilter.value(forKey: "inputBottomLeft"),
                                           forKey: "inputBottomLeft")
        
            perspectiveCorrection.setValue(finalBackgroundFrameImage/*.oriented(CGImagePropertyOrientation.downMirrored)*/,
                                           forKey: kCIInputImageKey)
            
//            guard let scaleFilter2 = CIFilter(name: "CILanczosScaleTransform") else {
//                return
//            }
//            scaleFilter2.setValue(internalCameraFrame, forKey: "inputImage")
//            scaleFilter2.setValue(2.0, forKey: "inputScale")
//            scaleFilter2.setValue(1.0, forKey: "inputAspectRatio")
            
//            let composite2 = ChromaKeyFilter()
        
            if isUserOverlayActive, let ghost = perspectiveCorrection.outputImage?.oriented(CGImagePropertyOrientation.downMirrored) {
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
                
//                composite2.inputImage = transparencyMatrixEffect.outputImage
//                composite2.backgroundImage = source
//                composite2.activeColor = CIColor(red: 0, green: 1, blue: 0)
                
                if let compositeImage2 = composite2.outputImage {
                    let obtainedImage = UIImage(ciImage:compositeImage2)
                    let weakSelf = self
                    DispatchQueue.main.async {
                        weakSelf.prototypeFrameImageView.image = obtainedImage
                    }
                }
            } else {
                //No isUserOverlayActive
                let weakSelf = self
                DispatchQueue.main.async {
                    weakSelf.prototypeFrameImageView.image = UIImage(ciImage:source)
                }
            }
        
            if let compositeImage = composite.outputImage {
                let obtainedImage = UIImage(ciImage:compositeImage)
                let weakSelf = self
                DispatchQueue.main.async {
                    weakSelf.backgroundFrameImageView.image = obtainedImage
                }
            }
    }
    
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
        let b = cubeData.withUnsafeBufferPointer { Data(buffer: $0) }
        let data = b as NSData
        
        let colorCube = CIFilter(name: "CIColorCube", withInputParameters: [
            "inputCubeDimension": size,
            "inputCubeData": data
            ])
        return colorCube!
    }
    
    /***
    func visionDetection(_ sampleBuffer:CMSampleBuffer, outputImage:CIImage) {
        var requestOptions:[VNImageOption : Any] = [:]
        
        if let camData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            //            requestOptions = [.cameraIntrinsics:camData,.ciContext:ciContext]
            requestOptions = [.cameraIntrinsics:camData]
            
        }
        
        //        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: outputImage.pixelBuffer!, orientation: CGImagePropertyOrientation.downMirrored, options: requestOptions)
        
        let imageRequestHandler = VNImageRequestHandler(ciImage: outputImage, orientation: CGImagePropertyOrientation.downMirrored, options: requestOptions)
        
        do {
            try imageRequestHandler.perform(self.requests)
        } catch let error as NSError {
            print(error.localizedDescription)
        }
    }*/
    
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
    
    // MARK: Vision.framework
    /***
    func setupVisionDetection() {
        //        let textRequest = VNDetectTextRectanglesRequest(completionHandler: self.detect)
        //        textRequest.reportCharacterBoxes = true
        
        let rectangleRequest = VNDetectRectanglesRequest(completionHandler: self.detectRectanglesHandler)
        rectangleRequest.quadratureTolerance = 45
        rectangleRequest.minimumAspectRatio = 16/9
        rectangleRequest.maximumAspectRatio = 16/9
        //        rectangleRequest.minimumConfidence = 0 //default
        
        self.requests = [rectangleRequest]
    }*/
    /***
    func detectRectanglesHandler(request: VNRequest, error: Error?) {
        guard let observations = request.results else {
            print("no result")
            return
        }
        
        let result = observations.map({$0 as? VNRectangleObservation})
        
        DispatchQueue.main.async() {
            self.previewView.layer.sublayers?.removeSubrange(1...)
            for region in result {
                guard let detectedRectangle = region else {
                    continue
                }
                
                self.highlightRectangle(box:detectedRectangle)
                
            }
        }
    }*/
    
    //    func detectTextHandler(request: VNRequest, error: Error?) {
    //        guard let observations = request.results else {
    //            print("no result")
    //            return
    //        }
    //
    //        let result = observations.map({$0 as? VNTextObservation})
    //
    //        DispatchQueue.main.async() {
    //            self.previewView.layer.sublayers?.removeSubrange(1...)
    //            for region in result {
    //                guard let rg = region else {
    //                    continue
    //                }
    //
    //                self.highlightWord(box: rg)
    //
    //                if let boxes = region?.characterBoxes {
    //                    for characterBox in boxes {
    //                        self.highlightLetters(box: characterBox)
    //                    }
    //                }
    //            }
    //        }
    //    }
    /***
    func highlightRectangle(box: VNRectangleObservation) {
        let path = CGMutablePath()
        
        let topLeft = previewView.videoLayer.layerPointConverted(fromCaptureDevicePoint: box.topLeft)
        let topRight = previewView.videoLayer.layerPointConverted(fromCaptureDevicePoint: box.topRight)
        let bottomLeft = previewView.videoLayer.layerPointConverted(fromCaptureDevicePoint: box.bottomLeft)
        let bottomRight = previewView.videoLayer.layerPointConverted(fromCaptureDevicePoint: box.bottomRight)
        
        path.move(to: topLeft)
        path.addLine(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.closeSubpath()
        
        let outline = CAShapeLayer()
        
        outline.path = path
        //        outline.frame = CGRect(x: xCord, y: yCord, width: width, height: height)
        outline.borderWidth = 10
        outline.strokeColor = UIColor.red.cgColor
        outline.fillColor = UIColor.orange.cgColor
        
        previewView.layer.addSublayer(outline)
        
        //        print("TopR \(topRight) \(box.topRight)")
        //        print("TopL \(topLeft) \(box.topLeft)")
        //        print("BotR \(bottomRight) \(box.bottomRight)")
        //        print("BotL \(bottomLeft) \(box.bottomLeft)")
        
        //Core image points are in cartesian (y is going upwards insetead of downwards)
        //        var t = CGAffineTransform(scaleX: 1, y: -1)
        //        t = t.translatedBy(CGAffineTransform(translationX: 0, y: -box.boundingBox.size.height)
        //        let pointUIKit = CGPointApplyAffineTransform(pointCI, t)
        //        let rectUIKIT = CGRectApplyAffineTransform(rectCI, t)
        
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
    }*/
    
    //    func highlightWord(box: VNTextObservation) {
    //        guard let boxes = box.characterBoxes else {
    //            return
    //        }
    //
    //        var maxX: CGFloat = 9999.0
    //        var minX: CGFloat = 0.0
    //        var maxY: CGFloat = 9999.0
    //        var minY: CGFloat = 0.0
    //
    //        for char in boxes {
    //            if char.bottomLeft.x < maxX {
    //                maxX = char.bottomLeft.x
    //            }
    //            if char.bottomRight.x > minX {
    //                minX = char.bottomRight.x
    //            }
    //            if char.bottomRight.y < maxY {
    //                maxY = char.bottomRight.y
    //            }
    //            if char.topRight.y > minY {
    //                minY = char.topRight.y
    //            }
    //        }
    //
    //        let previewLayerContentRect = self.previewLayerContentRect()
    //
    //        let xCord = maxX * previewLayerContentRect.width
    //        let yCord = (1 - minY) * previewLayerContentRect.height + previewLayerContentRect.origin.y
    //        let width = (minX - maxX) * previewLayerContentRect.width
    //        let height = (minY - maxY) * previewLayerContentRect.height
    //
    //        let outline = CALayer()
    //        outline.frame = CGRect(x: xCord, y: yCord, width: width, height: height)
    //        outline.borderWidth = 2.0
    //        outline.borderColor = UIColor.red.cgColor
    //
    //        previewView.layer.addSublayer(outline)
    //    }
    
    //    func highlightLetters(box: VNRectangleObservation) {
    //        let previewLayerContentRect = self.previewLayerContentRect()
    //
    //        let xCord = box.topLeft.x * previewLayerContentRect.width
    //        let yCord = (1 - box.topLeft.y) * previewLayerContentRect.height + previewLayerContentRect.origin.y
    //        let width = (box.topRight.x - box.bottomLeft.x) * previewLayerContentRect.width
    //        let height = (box.topLeft.y - box.bottomLeft.y) * previewLayerContentRect.height
    //
    //        let outline = CALayer()
    //        outline.frame = CGRect(x: xCord, y: yCord, width: width, height: height)
    //        outline.borderWidth = 1.0
    //        outline.borderColor = UIColor.blue.cgColor
    //
    //        previewView.layer.addSublayer(outline)
    //    }
    //MARK: MCSessionDelegate Methods
    func setRole(peerID:MCPeerID,role:String) {
        let dict = ["role":role]
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
            
            if let connectedMirrorPeer = mirrorPeer, connectedMirrorPeer.isEqual(peerID) {
                //Let's notify the camPrototypePeer to connect to the mirror (if the mirror it's an actual mirror and not a .iphoneCam)
                if peersRoles[connectedMirrorPeer.displayName] == .mirror, let connectedCamPrototypePeer = camPrototypePeer {
                    sendMessage(peerID:connectedCamPrototypePeer,dict:["mirrorMode":true])
                }
            }
            
            if peerID.isEqual(camPrototypePeer) && (!isMirrorMode || mirrorPeer != nil){
                browser.stopBrowsingForPeers()
            }
            
            if peerID.isEqual(camPrototypePeer) {
                setRole(peerID: peerID, role: "prototype")
                if let connectedCamBackground = camBackgroundPeer {
                    setRole(peerID: connectedCamBackground, role: "background")
                }
            }
            
            if peerID.isEqual(camBackgroundPeer) {
                if let connectedCamPrototype = camPrototypePeer {
                    setRole(peerID: connectedCamPrototype, role: "prototype")
                }
                setRole(peerID: peerID, role: "background")
            }
            
            break
        case .connecting:
            print("PEER CONNECTING: \(peerID.displayName)")
            break
        case .notConnected:
            print("PEER NOT CONNECTED: \(peerID.displayName)")
        
            if camPrototypePeer == nil {
                browser.startBrowsingForPeers()
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
                    if let currentRectangle = value as? VNRectangleObservation {
                        box = currentRectangle
                    }
                    break
                case "savedBoxes":
                    if peerID.isEqual(camBackgroundPeer) {
                        if let savedBoxes = value as? [NSDictionary:VNRectangleObservation] {
                            videoModel.backgroundTrack?.recordedBoxes.removeAll()
                            for (timeBoxDictionary,box) in savedBoxes {
                                let timeBox = CMTimeMakeFromDictionary(timeBoxDictionary)
                                videoModel.backgroundTrack?.recordedBoxes.append((timeBox, box))
                            }
                        }
                    }
                default:
                    print("Unrecognized message in receivedDict \(receivedDict)")
                }
            }

        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        let weakSelf = self
        
        DispatchQueue.main.async {
            weakSelf.snapshotSketchOverlay(layers: [weakSelf.prototypeCanvasView.canvasLayer],size: weakSelf.prototypeCanvasView.frame.size)
        }
        
        if let connectedCamBackgroundPeer = camBackgroundPeer, peerID.displayName.isEqual(connectedCamBackgroundPeer.displayName) {
//            if let createAt = Double(streamName) {
//                let elapsedTimeSinceCreation = Date().timeIntervalSince1970 - createAt
//                print("connectedCamBackgroundPeer elapsedTimeSinceCreation: \(elapsedTimeSinceCreation * 1000)ms")
//            }
            
            readDataToInputStream(stream, owner:ownerStream1, queue: streamingQueue1) { ciImage in
                weakSelf.backgroundCameraFrame = ciImage
            }
        }
        if let connectedCamPrototypePeer = camPrototypePeer, peerID.displayName.isEqual(connectedCamPrototypePeer.displayName) {
//            if let createAt = Double(streamName) {
//                let elapsedTimeSinceCreation = Date().timeIntervalSince1970 - createAt
//                print("connectedCamPrototypePeer elapsedTimeSinceCreation: \(elapsedTimeSinceCreation * 1000)ms")
//            }
            
            readDataToInputStream(stream, owner:ownerStream2, queue: streamingQueue2) { ciImage in
                weakSelf.prototypeCameraFrame = ciImage
                if weakSelf.camBackgroundPeer == nil {
                    if let source = ciImage {
                        DispatchQueue.main.async {
                            weakSelf.prototypeFrameImageView.image = UIImage(ciImage:source)
                        }
                        if let connectedMirrorPeer = weakSelf.mirrorPeer {
                            let isPhoneMirror:Bool
                            
                            if let mirrorRole = weakSelf.peersRoles[connectedMirrorPeer.displayName], mirrorRole == MontageRole.iphoneCam {
                                isPhoneMirror = true
                            } else {
                                isPhoneMirror = false
                            }
                            
                            if Date().timeIntervalSince(weakSelf.lastTimeSent) >= (1 / fps) {
                                mirrorQueue.async {[unowned self] in
                                    if self.sketchOverlay == nil {
                                        return
                                    }

                                    var overlay = self.sketchOverlay!
                                    
                                    
                                    if isPhoneMirror {
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
                                    }
                                    
                                    guard let image = self.cgImageBackedImage(withCIImage: overlay) else {
                                        print("Could not build overly image to mirror")
                                        return
                                    }
                                    let currentDate = Date()
//                                    let streamName = "\(currentDate.description(with: Locale.current)) \(currentDate.timeIntervalSince1970)"
                                    let streamName = "\(currentDate.timeIntervalSince1970)"

                                    DispatchQueue.main.async {[unowned self] in
                                        
                                        let outputStream:OutputStream
                                        
                                        do {
                                            outputStream = try self.multipeerSession.startStream(withName: streamName, toPeer: connectedMirrorPeer)
                                        } catch let error as NSError {
                                            print("Couldn't crete output stream: \(error.localizedDescription)")
                                            return
                                        }
                                        
                                        guard let data = UIImagePNGRepresentation(image) else {
//                                        guard let UIImageJPEGRepresentation(image, 0.25) else {
                                            print("Could not build data to mirror")
                                            return
                                        }
                                        
                                        let outputStreamHandler = OutputStreamHandler(outputStream,owner:self,data: data as NSData,queue:mirrorQueue2)
                                        
                                        outputStream.delegate = outputStreamHandler
                                        outputStream.schedule(in: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
                                        outputStream.open()
                                        weakSelf.lastTimeSent = Date()
                                    }
                                }
                            }
                        }
                    }
                    
                    
                    return
                }
            }
        }
        sampleBufferQueue.async {
            if let receivedCIImage = weakSelf.prototypeCameraFrame {
                weakSelf.applyFilterFromPrototypeToBackground(source: receivedCIImage)
            }
        }
    }
    
    func readDataToInputStream(_ iStream:InputStream,owner:InputStreamOwnerDelegate,queue:DispatchQueue,completion:((CIImage?)->())?) {
        let inputStreamHandler = InputStreamHandler(iStream,owner:owner,queue: queue)
        
        inputStreamHandler.completionBlock = completion
        
        iStream.open()
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
        
        DispatchQueue.main.async {[unowned self] in
            if peerID.isEqual(self.camPrototypePeer) {
                self.prototypeFrameImageView.image = nil
                self.prototypeCanvasView.isHidden = true
                self.prototypeCanvasView.isUserInteractionEnabled = false
                
                self.prototypeReceptionProgress = progress
                
                DispatchQueue.main.async {
                    self.prototypeReceptionTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.updatePrototypeReceptionProgress), userInfo: nil, repeats: true)
                    self.prototypeReceptionTimer?.fire()
                }
            }
            if peerID.isEqual(self.camBackgroundPeer) {
                self.backgroundFrameImageView.image = nil
                self.backgroundCanvasView.isHidden = true
                self.backgroundCanvasView.isUserInteractionEnabled = false
                
                self.backgroundReceptionProgress = progress
                
                DispatchQueue.main.async {
                    self.backgroundReceptionTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(self.updateBackgroundReceptionProgress), userInfo: nil, repeats: true)
                    self.backgroundReceptionTimer?.fire()
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
            self.prototypeProgressBar.isHidden = true
            self.prototypeReceptionTimer?.invalidate()
        }
    }
    
    @objc func updateBackgroundReceptionProgress(){
        self.backgroundProgressBar.isHidden = false
        
        guard let receptionProgress = self.backgroundReceptionProgress else {
            self.backgroundReceptionTimer?.invalidate()
            return
        }
        
        self.backgroundProgressBar.progress = Float(receptionProgress.fractionCompleted)
        if receptionProgress.completedUnitCount >= receptionProgress.totalUnitCount {
            self.backgroundProgressBar.isHidden = true
            self.backgroundReceptionTimer?.invalidate()
        }
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard "MONTAGE_CAM_MOVIE" == resourceName else {
            print("Ignoring didFinishReceivingResourceWithName \(resourceName)")
            return
        }
        
        if let error = error {
            print("didFinishReceivingResourceWithName error:\(error.localizedDescription)")
            return
        }
        
        guard let localURL = localURL else {
            print("didFinishReceivingResourceWithName did not receive a proper file")
            return
        }
        
        DispatchQueue.main.async {[unowned self] in
            let fileManager = FileManager()
            if peerID.isEqual(self.camPrototypePeer) {
                guard let currentPrototypeVideoFileURL = self.videoModel.prototypeTrack!.fileURL else {
                    print("Cold not get fileURL of prototype")
                    return
                }

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
                    self.prototypeVideoFileURL = currentPrototypeVideoFileURL
                } catch {
                    self.alert(error, title: "FileManager error", message: "Could not create prototype.mov")
                    return
                }
                
            }
            if peerID.isEqual(self.camBackgroundPeer) {
                guard let currentBackgroundVideoFileURL = self.videoModel.backgroundTrack!.fileURL else {
                    print("Cold not get fileURL of background")
                    return
                }
                
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
                    self.backgroundVideoFileURL = currentBackgroundVideoFileURL
                } catch {
                    self.alert(error, title: "FileManager error", message: "Could not create background.mov")
                    return
                }
            }
            
            if self.prototypeVideoFileURL != nil && self.backgroundVideoFileURL != nil {
                self.startPlayback()
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
            
            if [MontageRole.undefined,MontageRole.canvas].contains(role) {
                return
            }

            peersRoles.updateValue(role, forKey: peerID.displayName)

            let data = "MONTAGE_CANVAS".data(using: .utf8)
            if peerID.isEqual(camPrototypePeer) || peerID.isEqual(camBackgroundPeer) || peerID.isEqual(mirrorPeer) {
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
    
    // MARK: Stream Delegate
    
    /*
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case Stream.Event.openCompleted:
            break
        case Stream.Event.hasBytesAvailable:
//            print("\(aStream.description) Stream.Event.hasBytesAvailable \(_dcache.count)")
            if let executable:ReadDataInputStream = _dcache.object(forKey: aStream.description) as? ReadDataInputStream {
                streamingQueue.async {
                    executable()
                }
            } else {
                print("Something happened, right?")
            }
            break
        case Stream.Event.endEncountered:
            print("\(aStream.description) endEncountered")
            aStream.close()
            aStream.remove(from: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
            aStream.delegate = nil
            _dcache.removeObject(forKey: aStream.description)
            print("_dcache count: \(_dcache.count)")
            break
        case Stream.Event.errorOccurred:
            print("Stream status: \(aStream.streamStatus)")
            break
        default:
            print("Not handling streaming event code \(eventCode)")
        }
    }
    */
    //-MARK: VideoPlayerDelegate
    
    func play() {
        let playBlock = { [unowned self] in
            self.prototypePlayer.play()
            self.backgroundPlayer.play()
            self.isPlaying = true
        }
        
        if CMTimeCompare(prototypePlayer.currentTime(), prototypePlayerItem.duration) == 0 {
            scrubbedToTime(0.0, completionBlock: playBlock)
        } else {
            playBlock()
        }
    }
    
    func pause() {
        self.lastPlaybackRate = prototypePlayer.rate
        prototypePlayer.pause()
        backgroundPlayer.pause()
        isPlaying = false
    }
    
    func playBackComplete() {
        //After playBackComplete the rate should be 0.0
        
        //        self.scrubberSlider.value = 0.0
        //        self.togglePlaybackButton.isSelected = false
        isPlaying = false
    }
    
    func setCurrentTime(_ time:TimeInterval, duration:TimeInterval) {
        //        self.updateLabels(time,duration: duration)
        scrubberSlider.minimumValue = 0
        scrubberSlider.maximumValue = Float(duration)
        scrubberSlider.value = Float(time)
    }
    
    @IBAction func scrubbingDidStart() {
        self.pause()
        
        if let observer = self.periodicTimeObserver {
            prototypePlayer.removeTimeObserver(observer)
            self.periodicTimeObserver = nil
        }
    }
    
    @IBAction func scrubbingDidEnd() {
        //        self.updateLabels(CMTimeGetSeconds(self.player!.currentTime()),duration: CMTimeGetSeconds(self.playerItem!.duration))
        self.addPlayerItemPeriodicTimeObserver()
        if self.lastPlaybackRate > 0 {
            play()
        }
    }
    
    func scrubbedToTime(_ time:TimeInterval, completionBlock:(()->Void)? = nil) {
        prototypePlayerItem.cancelPendingSeeks()
        
        let seekingGroup = DispatchGroup()
        
        seekingGroup.enter()
        prototypePlayer.seek(to: CMTimeMakeWithSeconds(time, DEFAULT_TIMESCALE), toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero) { (completed) in
            seekingGroup.leave()
        }
        
        seekingGroup.enter()
        backgroundPlayerItem.cancelPendingSeeks()
        backgroundPlayer.seek(to: CMTimeMakeWithSeconds(time, DEFAULT_TIMESCALE), toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero) { (completed) in
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
            let duration = CMTimeGetSeconds(weakSelf.prototypePlayerItem.duration)
            weakSelf.setCurrentTime(currentTime,duration:duration)
            //            weakSelf.updateFilmstripScrubber()
        }
        
        
        // Add observer and store pointer for future use
        self.periodicTimeObserver = prototypePlayer.addPeriodicTimeObserver(forInterval: interval, queue: queue, using:callback) as AnyObject?
    }
    
    func addDidPlayToEndItemEndObserverForPlayerItem() {
        weak var weakSelf:CameraController! = self

        self.itemEndObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: prototypePlayerItem, queue: OperationQueue.main, using: { (notification) -> Void in
            weakSelf.prototypePlayer.seek(to: kCMTimeZero, completionHandler: { (finished) -> Void in
                weakSelf.playBackComplete()
            })
        })
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

class CanvasViewManager:NSObject, CanvasViewDelegate {
    var controller:CameraController
    
    var canvasView:CanvasView!
    var canvasViewPlayer:VideoPlayerView!
    
    init(controller:CameraController) {
        self.controller = controller
    }
    
    var palettePopoverPresentationController:UIPopoverPresentationController?
    
    @objc func pannedOutsidePopopver() {
        if palettePopoverPresentationController != nil {
            controller.presentedViewController?.dismiss(animated: false, completion: nil)
            palettePopoverPresentationController = nil
        }
    }
    
    func canvasTierAdded(_ canvas: CanvasView, tier: Tier) {
        preconditionFailure("This method must be overridden")
    }
    
    func canvasTierModified(_ canvas: CanvasView, tier: Tier) {
        preconditionFailure("This method must be overridden")
    }
    
    
    func playerItemOffset() -> TimeInterval {
        preconditionFailure("This method must be overridden")
    }
    
    func canvasLongPressed(_ canvas:CanvasView,touchLocation:CGPoint) {
        
        let paletteView = canvas.paletteView
        
        let paletteController = UIViewController()
        
        paletteController.view.translatesAutoresizingMaskIntoConstraints = false
        paletteController.modalPresentationStyle = UIModalPresentationStyle.popover;
        let paletteHeight = paletteView.paletteHeight()
        
        paletteController.preferredContentSize = CGSize(width:Palette.initialWidth,height:paletteHeight)
        paletteController.view.frame = CGRect(x:0,y:0,width:Palette.initialWidth,height:paletteHeight)
        paletteView.frame = CGRect(x: 0, y: 0, width: paletteController.view.frame.width, height: paletteController.view.frame.height)
        paletteController.view.addSubview(paletteView)
        //        paletteView.frame = CGRect(x: 0, y: paletteController.view.frame.height - paletteHeight, width: paletteController.view.frame.width, height: paletteHeight)
        
        palettePopoverPresentationController = paletteController.popoverPresentationController
        
        paletteController.popoverPresentationController?.sourceView = canvas
        paletteController.popoverPresentationController?.sourceRect = CGRect(origin: touchLocation, size: CGSize.zero)
        
        controller.present(paletteController, animated: true) {[unowned self] in
            guard let v1 = paletteController.view?.superview?.superview?.superview else {
                return
            }
            
            guard let dimmingViewClass = NSClassFromString("UIDimmingView") else {
                return
            }
            for vx in v1.subviews {
                if vx.isKind(of: dimmingViewClass.self) {
                    let pan = UIPanGestureRecognizer(target: self, action: #selector(self.pannedOutsidePopopver))
                    pan.cancelsTouchesInView = false
                    pan.allowedTouchTypes = [NSNumber(value:UITouchType.stylus.rawValue)]
                    vx.addGestureRecognizer(pan)
                }
            }
        }
    }
    
    
}

class RecordingCanvasViewManager:CanvasViewManager {
    override func canvasTierAdded(_ canvas: CanvasView, tier: Tier) {
        
    }
    
    override func canvasTierModified(_ canvas: CanvasView, tier: Tier) {
        
    }
    
    override func playerItemOffset() -> TimeInterval {
        return 0
    }
}

class PlaybackCanvasViewManager:CanvasViewManager {
    
    
    
    override func canvasTierAdded(_ canvas: CanvasView, tier: Tier) {
        let shapeLayer = tier.shapeLayer
        canvas.removeAllSketches()
//        let syncLayer = controller.backgroundPlayerSyncLayer
//        let syncLayer = controller.prototypePlayerView.syncLayer
        let syncLayer = canvas.associatedSyncLayer

//        controller.backgroundPlayerSyncLayer?.addSublayer(shapeLayer)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        syncLayer?.addSublayer(shapeLayer)
        CATransaction.commit()
        
        switch controller.prototypePlayer.timeControlStatus {
        case .playing:
            let (appearAnimation,strokeEndAnimation,transformationAnimation) = tier.buildAnimations()
            
            if let strokeEndAnimation = strokeEndAnimation {
                shapeLayer.strokeEnd = 0
                shapeLayer.add(strokeEndAnimation, forKey: strokeEndAnimation.keyPath!)
            }
            
            if let transformationAnimation = transformationAnimation {
                shapeLayer.transform = CATransform3DIdentity
                shapeLayer.add(transformationAnimation, forKey: transformationAnimation.keyPath!)
            }
            
            if let appearAnimation = appearAnimation {
                shapeLayer.add(appearAnimation, forKey: appearAnimation.keyPath!)
            }
        case .paused:
            let animationKeyTime = controller.prototypePlayerItem.currentTime().seconds
            let animationDuration = controller.prototypePlayerItem.duration.seconds
            let appearAnimation = CAKeyframeAnimation()
            appearAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
            appearAnimation.calculationMode = kCAAnimationDiscrete
            appearAnimation.keyPath = "opacity"
            appearAnimation.values = [0,1,1]
            appearAnimation.keyTimes = [0,NSNumber(value:animationKeyTime/animationDuration),1]
            appearAnimation.duration = animationDuration
            appearAnimation.fillMode = kCAFillModeForwards //to keep opacity = 1 after completing the animation
            appearAnimation.isRemovedOnCompletion = false
            
            shapeLayer.add(appearAnimation, forKey: appearAnimation.keyPath!)
        default:
            print("ignoring")
        }

    }
    
    override func canvasTierModified(_ canvas: CanvasView, tier: Tier) {
        //We redo the whole thing
        let shapeLayer = tier.shapeLayer
        shapeLayer.removeAllAnimations()
        
        let (appearAnimation,strokeEndAnimation,transformationAnimation) = tier.buildAnimations()
        
        if let strokeEndAnimation = strokeEndAnimation {
            shapeLayer.strokeEnd = 0
            shapeLayer.add(strokeEndAnimation, forKey: strokeEndAnimation.keyPath!)
        }
        
        if let transformationAnimation = transformationAnimation {
            shapeLayer.transform = CATransform3DIdentity
            shapeLayer.add(transformationAnimation, forKey: transformationAnimation.keyPath!)
        }
        
        if let appearAnimation = appearAnimation {
            shapeLayer.add(appearAnimation, forKey: appearAnimation.keyPath!)
        }
    }
    
    override func playerItemOffset() -> TimeInterval {
        return controller.prototypePlayerItem.currentTime().seconds
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
