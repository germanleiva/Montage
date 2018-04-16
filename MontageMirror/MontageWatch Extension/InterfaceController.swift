//
//  InterfaceController.swift
//  MontageWatch Extension
//
//  Created by Germán Leiva on 27/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import WatchKit
import Foundation
import WatchConnectivity

class InterfaceController: WKInterfaceController, WCSessionDelegate {
    @IBOutlet weak var interfaceImage:WKInterfaceImage!
    var watchConnectivitySession:WCSession!
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Configure interface objects here.
    }
    
    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
        setupWatchSession()
    }
    
    func setupWatchSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            
            watchConnectivitySession = session
        }
    }
    
    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }
    
    @IBAction func chromaPressed() {
        print("chromaPressed")
    }
    
    @IBAction func mirrorPressed() {
        print("mirrorPressed")
    }
    
    //WCSessionDelegate
    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        if let obtainedImage = UIImage(data: messageData) {
            interfaceImage.setImage(obtainedImage)
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("activationDidCompleteWith \(activationState)")
    }
}


