//
//  OutputStreamer.swift
//  CamEmitter
//
//  Created by Germán Leiva on 12/04/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import MultipeerConnectivity

public protocol OutputStreamerDelegate:class {
    func didClose(streamer:OutputStreamer)
}

public class OutputStreamer: NSObject, StreamDelegate {
    public weak var delegate:OutputStreamerDelegate?
    public private(set) var peerID:MCPeerID
    var outputStream:OutputStream
    var isInitialized = false
    public var initialChunk:Data? {
        didSet {
            if initialChunk != oldValue {
                isInitialized = false
            }
        }
    }
    var pendingData = [Data]()
    var canSendDirectly = false
    let writingQueue:DispatchQueue
    var isRunning = false {
        didSet {
            print("Running changed \(peerID.description) isRunning \(isRunning)")
        }
    }
    
    public init(_ peerID:MCPeerID, outputStream:OutputStream, initialChunk:Data?) {
        self.peerID = peerID
        self.outputStream = outputStream
        self.initialChunk = initialChunk
        self.writingQueue = DispatchQueue(label: "writingQueue-\(peerID.description) \(Date())")
        
        super.init()
        
        outputStream.delegate = self
        outputStream.schedule(in: RunLoop.main, forMode: RunLoopMode.commonModes)
        outputStream.open()
        
        self.isRunning = true //I couldn't put this on openCompleted because there was a bug on iPhone, and hasSpaceAvailable was called before
    }
    
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard let oStream = aStream as? OutputStream else {
            return
        }
        switch eventCode {
        case .openCompleted:
            print("Stream.Event.openCompleted \(oStream.description)")
        case .hasSpaceAvailable:
//            print("Stream.Event.hasSpaceAvailable \(oStream.description)")
            
            let weakSelf = self
            writingQueue.async {
                weakSelf._sendData()
            }
        case .hasBytesAvailable:
            print("Stream.Event.hasBytesAvailable \(oStream.description)")
        case .endEncountered:
            print("Stream.Event.endEncountered \(oStream.description)")
            print("deleting stream because Stream.Event.endEncountered")
            close()
        case .errorOccurred:
            print("Stream.Event.errorOccurred \(oStream.streamStatus)")
            print("deleting stream because Stream.Event.errorOccurred")
            close()
        default:
            print("Unrecognized Stream.Event \(oStream.streamStatus)")
        }
    }
    
    public func sendData(_ chunk:Data) {
        let weakSelf = self
        writingQueue.async {
            if !weakSelf.isRunning {
                return
            }
            weakSelf.pendingData.append(chunk)
            if weakSelf.canSendDirectly {
                weakSelf._sendData()
            }
        }
    }
    
    private func _sendData() {
        canSendDirectly = false
        
        guard let chunk = pendingData.first else {
            canSendDirectly = true
            return
        }
        
        if !isRunning {
            return
        }
        
        if !isInitialized {
            guard let firstChunk = initialChunk else {
                print("Not initialized but initialChunk is not ready")
                return
            }
            let initResult = outputStream.write(firstChunk.bytes, maxLength: firstChunk.count)
            
            if initResult >= firstChunk.count {
                isInitialized = true
            } else {
                if initResult <= 0 {
                    print("Error during initialization")
                }
            }
        }
        
        let writeResult = outputStream.write(chunk.bytes, maxLength: chunk.count)
        
        if writeResult == 0 {
            print("End encountered writeResult \(peerID.description) = \(writeResult)")
            close()
            return
        }
        
        if writeResult > 0 {
//            print("Succesfully written \(peerID.description) \(writeResult)")
            if writeResult < chunk.count {
                print("Unsuccesfully written the whole chunk, discarding the chunk")
            }
        } else {
            //writeResult < 0
            print("Error during write \(peerID.description) \(writeResult)")
            return //We need to return because if we emptyed the pendingData, remove the first will throw an error
        }
        
        pendingData.remove(at: 0)
    }

    public func close() {
        let weakSelf = self
        
        writingQueue.async {

            guard weakSelf.isRunning else {
                return
            }
        
            weakSelf.isRunning = false
        
            DispatchQueue.main.async {
                weakSelf.outputStream.delegate = nil
                weakSelf.outputStream.remove(from: RunLoop.main, forMode: RunLoopMode.commonModes)
                weakSelf.outputStream.close()
                weakSelf.delegate?.didClose(streamer: weakSelf)
            }
        }
    }
}
