//
//  ViewController.swift
//  MontageMirror
//
//  Created by Germán Leiva on 27/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import MultipeerConnectivity
import Streamer
import WatchConnectivity

let fps = 30.0

let watchQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_watch_queue", qos: DispatchQoS.userInteractive)

class ViewController: UIViewController, MCSessionDelegate, InputStreamerDelegate, MCNearbyServiceAdvertiserDelegate, WCSessionDelegate {
    // MARK: InputStreamerDelegate
    var inputStreamer:InputStreamer?
    var inputStreamerSketches:InputStreamer?
    var viewportRect:CGRect? //normalized
    
    let context = CIContext()
    var lastSketchFrame:CIImage?
    var lastPrototypeFrame:CIImage? {
        didSet {
            //WATCH
            if self.watchConnectivitySession?.isReachable ?? false {
                guard let finalImage = lastPrototypeFrame else {
                    return
                }
                
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
                    
                    if let currentOverlayImage = self.lastSketchFrame {
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
        }
    }
    
    func cgImageBackedImage(withCIImage ciImage:CIImage) -> UIImage? {
        guard let ref = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let image = UIImage(cgImage: ref, scale: UIScreen.main.scale, orientation: UIImageOrientation.up)
        
        return image
    }
    
    func inputStreamer(_ streamer: InputStreamer, decodedImage ciImage: CIImage) {
        switch streamer {
        case inputStreamer:
            let finalProtoypeFrame:CIImage
            if let normalizedViewportRect = viewportRect {
                let totalWidth = ciImage.extent.width
                let totalHeight = ciImage.extent.height
                
                let croppingRect = CGRect(x: normalizedViewportRect.origin.x * totalWidth,
                                          y: normalizedViewportRect.origin.y * totalHeight,
                                          width: normalizedViewportRect.width * totalWidth,
                                          height: normalizedViewportRect.height * totalHeight)
                
                finalProtoypeFrame = ciImage.cropped(to: croppingRect)
            } else {
                finalProtoypeFrame = ciImage
            }
            
            lastPrototypeFrame = finalProtoypeFrame
            imageView.image = finalProtoypeFrame
        case inputStreamerSketches:
            lastSketchFrame = ciImage

            guard let overlayImageView = overlayImageView else {
                return
            }
//            if overlayImageView.isHidden {
//                overlayImageView.isHidden = false
//            }
            
            overlayImageView.image = nil
            overlayImageView.image = UIImage(ciImage:ciImage)

        default:
            print("Unrecognized streamer")
        }
    }
    
    func didClose(_ streamer: InputStreamer) {
        if streamer == inputStreamer {
            inputStreamer = nil
            print("didClose InputStreamer")
        }
        if streamer == inputStreamerSketches {
            inputStreamer = nil
            print("didClose InputStreamer for the sketches")
        }
    }
    
    @IBOutlet weak var overlayImageView:UIImageView!
    @IBOutlet weak var imageView:MetalImageView!
    
    let serviceType = "multipeer-video"
    
    let localPeerID = MCPeerID(displayName: UIDevice.current.name)
    var serverName:String?
    
    lazy var multipeerSession:MCSession = {
        let _session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .none)
        _session.delegate = self
        return _session
    }()
    
    lazy var serviceAdvertiser:MCNearbyServiceAdvertiser = {
        let info = ["role":String(describing:MontageRole.mirror.rawValue)]
        let _serviceAdvertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: info, serviceType: serviceType)
        _serviceAdvertiser.delegate = self
        return _serviceAdvertiser
    }()
    
    var chromaColor = UIColor.green {
        didSet {
            imageView.backgroundColor = chromaColor
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupWatchSession()
        // Do any additional setup after loading the view, typically from a nib.
        chromaColor = UIColor.green
        
        print("startAdvertisingPeer")
        serviceAdvertiser.startAdvertisingPeer()
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
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //MARK: MCSessionDelegate Methods
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            print("WHO's CONNECTED? \(peerID.displayName)")
            
            if peerID == connectedServer {
                print("SERVER PEER CONNECTED: \(peerID.displayName)")
                
                print("stopAdvertisingPeer")
                serviceAdvertiser.stopAdvertisingPeer()
            } else {
                sendMessage(peerID: peerID, dict: ["ARE_YOU_WIZARD_CAM":true])
            }
            break
        case .connecting:
            print("PEER CONNECTING: \(peerID.displayName)")
            break
        case .notConnected:
            print("PEER NOT CONNECTED: \(peerID.displayName)")
            if serverName == peerID.displayName {
                serverName = nil
                overlayImageView.backgroundColor = UIColor.green
                print("startAdvertisingPeer")
                serviceAdvertiser.startAdvertisingPeer()
            }
            if peerID == connectedWizardCam {
                connectedWizardCam = nil
            }
            break
        }
    }
    
    var connectedServer:MCPeerID? {
        return self.multipeerSession.connectedPeers.first { (peer) -> Bool in
            return peer.displayName == serverName
        }
    }
    var connectedWizardCam:MCPeerID?
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
//        print("Received data from \(peerID.displayName) Read \(data.count) bytes")
        if let receivedDict = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String:Any] {
            for (messageType, value) in receivedDict {
                switch messageType {
                case "I_AM_WIZARD_CAM":
                    //                    if let currentRectangle = value as? VNRectangleObservation {
                    //                        box = currentRectangle
                    //                    }
                    print("\(peerID.displayName) is the new wizardCam")
                    connectedWizardCam = peerID
                case "viewport":
                    //                    if let currentRectangle = value as? VNRectangleObservation {
                    //                        box = currentRectangle
                    //                    }
                    viewportRect = value as? CGRect
                default:
                    print("Unrecognized message in receivedDict \(messageType)")
                }
            }
            
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        //        print("didReceive stream from someone")
        
        if serverName == peerID.displayName {
            inputStreamerSketches = InputStreamer(peerID,stream:stream)
            inputStreamerSketches?.isSimpleData = true
            inputStreamerSketches?.delegate = self
        } else {
            inputStreamer = InputStreamer(peerID,stream:stream)
            inputStreamer?.delegate = self
        }
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        
    }
    
    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        print("multipeer session didReceiveCertificate")
        certificateHandler(true)
    }
    
    // MARK: MCNearbyServiceAdvertiserDelegate
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        if let data = context, let stringData = String(data: data, encoding: .utf8), stringData == "MONTAGE_CANVAS" {
            serverName = peerID.displayName
//            imageView.isHidden = false
            overlayImageView.backgroundColor = UIColor.clear
            invitationHandler(true,multipeerSession)
        } else {
            invitationHandler(false,multipeerSession)
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
}

