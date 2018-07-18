//
//  ViewController.swift
//  MontageMirrorMac
//
//  Created by Germán Leiva on 27/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import Cocoa
import MultipeerConnectivity
import Streamer

let streamerQueue = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_streaming_queue", qos: DispatchQoS.userInteractive)

class ViewController: NSViewController, MCSessionDelegate, InputStreamerDelegate, MCNearbyServiceAdvertiserDelegate/*, MCNearbyServiceBrowserDelegate*/ {
    
    // MARK: InputStreamerDelegate
    var inputStreamer:InputStreamer?
    var inputStreamerSketches:InputStreamer?
    
    func inputStreamer(_ streamer: InputStreamer, decodedImage ciImage: CIImage) {
//        streamerQueue.async {
            ////            weakSelf.setImageOpenGL(view: weakSelf.backgroundFrameImageView, image: ciImage)

//            let rep: NSCIImageRep = NSCIImageRep(ciImage: ciImage)
//            let nsImage: NSImage = NSImage(size: rep.size)
//            nsImage.addRepresentation(rep)
//
//            DispatchQueue.main.async {
//                weakSelf.imageView.image = nsImage
//            }
            
//            weakSelf.setImageOpenGL(view: self.openGLView, image: ciImage)
//        }
        
//        DispatchQueue.main.async {
//            weakSelf.imageView.imageContentMode = YUCIImageViewContentMode.center
        //        }
        
        switch streamer {
        case inputStreamer:
            imageView.image = ciImage
        case inputStreamerSketches:
            guard let overlayImageView = overlayImageView else {
                return
            }
            if overlayImageView.isHidden {
                overlayImageView.isHidden = false
            }
            let rep: NSCIImageRep = NSCIImageRep(ciImage: ciImage)
            let nsImage: NSImage = NSImage(size: rep.size)
            nsImage.addRepresentation(rep)
            
            overlayImageView.image = nsImage
        default:
            print("Unrecognized streamer")
        }
    }
    
    func didClose(_ streamer: InputStreamer) {
        if streamer.isEqual(inputStreamer) {
            inputStreamer = nil
            print("didClose InputStreamer")
        }
        if streamer.isEqual(inputStreamerSketches) {
            inputStreamer = nil
            print("didClose InputStreamer for the sketches")
        }
    }
    
    @IBOutlet weak var overlayImageView:NSImageView! {
        didSet {
            //            ( Aspect Fill )
            overlayImageView.imageScaling = .scaleAxesIndependently
        }
    }
    @IBOutlet weak var imageView: MetalImageView!
//        {
//        didSet {
//            self.imageView.renderer = YUCIImageRenderingSuggestedRenderer()
//        }
//    }
    
//    @IBOutlet weak var imageView:NSImageView! {
//        didSet {
//            //            ( Aspect Fill )
//            imageView.imageScaling = .scaleAxesIndependently
//
//            //            ( Aspect Fit )
//            //            imageView.imageScaling = .scaleProportionallyUpOrDown
//
//            //            ( Center Top )
//            //            imageView.imageScaling = .scaleProportionallyDown
//        }
//    }
    
    let serviceType = "multipeer-video"
    
    let localPeerID = MCPeerID(displayName: "MacOS")
    var serverName:String?
    
    lazy var multipeerSession:MCSession = {
        let _session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: MCEncryptionPreference.optional)
        _session.delegate = self
        return _session
    }()
    
    lazy var serviceAdvertiser:MCNearbyServiceAdvertiser = {
        let info = ["role":String(describing:MontageRole.mirror.rawValue)]
        let _serviceAdvertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: info, serviceType: serviceType)
        _serviceAdvertiser.delegate = self
        return _serviceAdvertiser
    }()
    
//    lazy var browser:MCNearbyServiceBrowser = {
//        let _browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: "multipeer-video")
//        _browser.delegate = self
//        return _browser
//    }()
    
    var chromaColor = NSColor.green {
        didSet {
            view.layer?.backgroundColor = chromaColor.cgColor
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
        chromaColor = NSColor.green
        
        print("startAdvertisingPeer")
        serviceAdvertiser.startAdvertisingPeer()
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    //MARK: MCSessionDelegate Methods
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            print("WHO's CONNECTED? \(peerID.displayName)")

            if peerID.isEqual(connectedServer) {
                print("SERVER PEER CONNECTED: \(peerID.displayName)")

                print("stopAdvertisingPeer")
                serviceAdvertiser.stopAdvertisingPeer()
                
//                let timerBrowsing = Timer.init(timeInterval: 1, repeats: false, block: { [unowned self] (timer) in
//                    print("Let's start browsing for a cam")
//                    self.browser.startBrowsingForPeers()
//                })
//                timerBrowsing.fire()
            } else {
                sendMessage(peerID: peerID, dict: ["ARE_YOU_WIZARD_CAM":true])
            }
            break
        case .connecting:
            print("PEER CONNECTING: \(peerID.displayName)")
            break
        case .notConnected:
            print("PEER NOT CONNECTED: \(peerID.displayName)")
            if serverName?.isEqual(peerID.displayName) ?? false  {
                serverName = nil
                print("startAdvertisingPeer")
                serviceAdvertiser.startAdvertisingPeer()
            }
            if peerID.isEqual(connectedWizardCam) {
                connectedWizardCam = nil
            }
            break
        }
    }
    
    var connectedServer:MCPeerID? {
        return self.multipeerSession.connectedPeers.first { (peer) -> Bool in
            return serverName?.isEqual(peer.displayName) ?? false
        }
    }
    var connectedWizardCam:MCPeerID?
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("Received data from \(peerID.displayName) Read \(data.count) bytes")
        if let receivedDict = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String:Any] {
            for (messageType, value) in receivedDict {
                switch messageType {
                case "I_AM_WIZARD_CAM":
                    //                    if let currentRectangle = value as? VNRectangleObservation {
                    //                        box = currentRectangle
                    //                    }
                    print("\(peerID.displayName) is the new wizardCam")
                    connectedWizardCam = peerID
                default:
                    print("Unrecognized message in receivedDict \(messageType)")
                }
            }
            
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("didReceive stream from someone")
        
        
        if serverName?.isEqual(peerID.displayName) ?? false  {
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
            imageView.isHidden = false
            invitationHandler(true,multipeerSession)
        } else {
            invitationHandler(false,multipeerSession)
        }
    }
    
    // MARK: MCNearbyServiceBrowserDelegate
    
//    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
//        print("didNotStartBrowsingForPeers")
//    }
//
//    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
//        if let info = info {
//            guard let value = info["role"], let rawValue = Int(value), let role = MontageRole(rawValue: rawValue) else {
//                return
//            }
//
//            if role == MontageRole.wizardCam {
//                let data = "MONTAGE_MIRROR".data(using: .utf8)
//                camName = peerID.displayName
//                browser.invitePeer(peerID, to: multipeerSession, withContext: data, timeout: 30)
//            }
//        }
//    }
//
//    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
//        print("lostPeer \(peerID.displayName)")
//    }
    
    func sendMessage(peerID:MCPeerID,dict:[String:Any?]) {
        let data = NSKeyedArchiver.archivedData(withRootObject: dict)
        
        do {
            try multipeerSession.send(data, toPeers: [peerID], with: .reliable)
        } catch let error as NSError {
            print("Could not send dict message: \(error.localizedDescription)")
        }
    }
}

