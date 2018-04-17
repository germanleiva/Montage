//
//  ViewController.swift
//  MontageMirrorMac
//
//  Created by Germán Leiva on 27/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import Cocoa
import MultipeerConnectivity

let streamingQueue1 = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_streaming_queue_1", qos: DispatchQoS.userInteractive)
let streamingQueue2 = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_streaming_queue_2", qos: DispatchQoS.userInteractive)

class ViewController: NSViewController, MCSessionDelegate, InputStreamOwnerDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    // MARK: InputStreamOwner
    
    var inputStreamHandlers = Set<InputStreamHandler>()
    
    func addInputStreamHandler(_ inputStreamHandler:InputStreamHandler) {
        inputStreamHandlers.insert(inputStreamHandler)
    }
    
    func removeInputStreamHandler(_ inputStreamHandler:InputStreamHandler) {
        inputStreamHandlers.remove(inputStreamHandler)
    }
    
    @IBOutlet weak var imageView:NSImageView! {
        didSet {
            //            ( Aspect Fill )
            imageView.imageScaling = .scaleAxesIndependently
            
            //            ( Aspect Fit )
            //            imageView.imageScaling = .scaleProportionallyUpOrDown
            
            //            ( Center Top )
            //            imageView.imageScaling = .scaleProportionallyDown
        }
    }
    @IBOutlet weak var overlayImageView:NSImageView! {
        didSet {
            //            ( Aspect Fill )
            overlayImageView.imageScaling = .scaleAxesIndependently
        }
    }
    
    let serviceType = "multipeer-video"
    
    let localPeerID = MCPeerID(displayName: "MacOS")
    var serverName:String?
    var camName:String?
    
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
    
    lazy var browser:MCNearbyServiceBrowser = {
        let _browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: "multipeer-video")
        _browser.delegate = self
        return _browser
    }()
    
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
            print("PEER CONNECTED: \(peerID.displayName)")
            if peerID.isEqual(connectedServer) {
                print("stopAdvertisingPeer")
                serviceAdvertiser.stopAdvertisingPeer()
                
                let timerBrowsing = Timer.init(timeInterval: 1, repeats: false, block: { [unowned self] (timer) in
                    print("Let's start browsing for a cam")
                    self.browser.startBrowsingForPeers()
                })
                timerBrowsing.fire()
            }
            if peerID.isEqual(connectedCam) {
                print("stopBrowsingForPeer")
                browser.stopBrowsingForPeers()
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
            if peerID.displayName.isEqual(camName) {
                camName = nil
                print("startBrowsing")
                browser.startBrowsingForPeers()
            }
            break
        }
    }
    
    var connectedServer:MCPeerID? {
        return self.multipeerSession.connectedPeers.first { (peer) -> Bool in
            return serverName?.isEqual(peer.displayName) ?? false
        }
    }
    var connectedCam:MCPeerID? {
        return self.multipeerSession.connectedPeers.first { (peer) -> Bool in
            return peer.displayName.isEqual(camName)
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        //        print("Received data from \(peerID.displayName) Read \(data.count) bytes")
        if let receivedDict = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String:Any] {
            for (messageType, value) in receivedDict {
                switch messageType {
                case "detectedRectangle":
                    //                    if let currentRectangle = value as? VNRectangleObservation {
                    //                        box = currentRectangle
                    //                    }
                    break
                default:
                    print("Unrecognized message in receivedDict \(messageType)")
                }
            }
            
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        let weakSelf = self
        if peerID.displayName.isEqual(camName) {
            readDataToInputStream(stream, owner:self, queue: streamingQueue1) { ciImage in
                guard let receivedImage = ciImage else {
                    return
                }
                let rep: NSCIImageRep = NSCIImageRep(ciImage: receivedImage)
                let nsImage: NSImage = NSImage(size: rep.size)
                nsImage.addRepresentation(rep)
                
                weakSelf.imageView.image = nsImage
            }
        }
        if serverName?.isEqual(peerID.displayName) ?? false  {
            readDataToInputStream(stream, owner:self, queue: streamingQueue2) { ciImage in
                guard let receivedImage = ciImage else {
                    return
                }
                guard let overlayImageView = weakSelf.overlayImageView else {
                    return
                }
                if overlayImageView.isHidden {
                    overlayImageView.isHidden = false
                }
                let rep: NSCIImageRep = NSCIImageRep(ciImage: receivedImage)
                let nsImage: NSImage = NSImage(size: rep.size)
                nsImage.addRepresentation(rep)
                
                weakSelf.overlayImageView.image = nsImage
            }
        }
    }
    
    func readDataToInputStream(_ iStream:InputStream,owner:InputStreamOwnerDelegate,queue:DispatchQueue,completion:((CIImage?)->())?) {
        let inputStreamHandler = InputStreamHandler(iStream,owner:owner,queue: queue)
        
        inputStreamHandler.completionBlock = completion
        
        iStream.open()
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
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("didNotStartBrowsingForPeers")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        if let info = info {
            guard let value = info["role"], let rawValue = Int(value), let role = MontageRole(rawValue: rawValue) else {
                return
            }
            
            if role == MontageRole.iphoneCam || role == MontageRole.iPadCam {
                let data = "MONTAGE_MIRROR".data(using: .utf8)
                camName = peerID.displayName
                browser.invitePeer(peerID, to: multipeerSession, withContext: data, timeout: 30)
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("lostPeer \(peerID.displayName)")
    }
}

