//
//  ViewController.swift
//  MontageMirror
//
//  Created by Germán Leiva on 27/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import MultipeerConnectivity

enum MontageRole:Int {
    case undefined = 0
    case iphoneCam
    case iPadCam
    case mirror
    case watchMirror
    case canvas
}

let streamingQueue1 = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_streaming_queue_1", qos: DispatchQoS.userInteractive)
let streamingQueue2 = DispatchQueue(label: "fr.lri.ex-situ.Montage.serial_streaming_queue_2", qos: DispatchQoS.userInteractive)

class ViewController: UIViewController, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, InputStreamOwnerDelegate {
    // MARK: InputStreamOwner
    
    var inputStreamHandlers = Set<InputStreamHandler>()
    
    func addInputStreamHandler(_ inputStreamHandler:InputStreamHandler) {
        inputStreamHandlers.insert(inputStreamHandler)
    }
    
    func removeInputStreamHandler(_ inputStreamHandler:InputStreamHandler) {
        inputStreamHandlers.remove(inputStreamHandler)
    }
    
    @IBOutlet weak var imageView:UIImageView!
    @IBOutlet weak var overlayImageView:UIImageView!
    
    let serviceType = "multipeer-video"
    
    let localPeerID = MCPeerID(displayName: UIDevice.current.name)
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
        // Do any additional setup after loading the view, typically from a nib.
        chromaColor = UIColor.green
        
        print("startAdvertisingPeer")
        browser.startBrowsingForPeers()
        serviceAdvertiser.startAdvertisingPeer()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    //MARK: MCSessionDelegate Methods
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            print("PEER CONNECTED: \(peerID.displayName)")
            //            if peerID.isEqual(connectedServer) {
            //
            //                print("Let's start browsing for a cam")
            //                browser.startBrowsingForPeers()
            //            } //TODO testing
            if camName?.isEqual(peerID.displayName) ?? false && connectedServer != nil {
                print("stopAdvertisingPeer")
                serviceAdvertiser.stopAdvertisingPeer()
                browser.stopBrowsingForPeers()
            }
            break
        case .connecting:
            print("PEER CONNECTING: \(peerID.displayName)")
            break
        case .notConnected:
            print("PEER NOT CONNECTED: \(peerID.displayName)")
            if serverName?.isEqual(peerID.displayName) ?? false {
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
                    print("Unrecognized message in receivedDict \(receivedDict)")
                }
            }
            
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        let weakSelf = self
        if peerID.displayName.isEqual(camName) {
            streamingQueue1.async { [unowned self] in
                self.readDataToInputStream(stream, owner:self, queue: streamingQueue1) { ciImage in
                    guard let receivedImage = ciImage else {
                        return
                    }
                    weakSelf.imageView.image = UIImage(ciImage:receivedImage)
                }
            }
        }
        if serverName?.isEqual(peerID.displayName) ?? false {
            streamingQueue2.async { [unowned self] in
                self.readDataToInputStream(stream, owner:self, queue: streamingQueue2) { ciImage in
                    guard let receivedImage = ciImage else {
                        return
                    }
                    guard let overlayImageView = weakSelf.overlayImageView else {
                        return
                    }
                    if overlayImageView.isHidden {
                        overlayImageView.isHidden = false
                    }
                    overlayImageView.image = nil
                    overlayImageView.image = UIImage(ciImage:receivedImage)
                }
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

