 //
//  InputStreamHandler.swift
//  Montage
//
//  Created by Germán Leiva on 14/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import Cocoa
import MultipeerConnectivity

protocol InputStreamOwnerDelegate:class {
    func addInputStreamHandler(_ inputStreamHandler:InputStreamHandler)
    
    func removeInputStreamHandler(_ inputStreamHandler:InputStreamHandler)
    
}

class InputStreamHandler: NSObject,StreamDelegate {
    static let DATA_LENGTH = 8 * 1024 //8192
    
    var owner:InputStreamOwnerDelegate
    var mdata = NSMutableData()
    var len = DATA_LENGTH
    var completionBlock:((CIImage?)->Void)? = nil
    var stream:InputStream?
    var queue:DispatchQueue
    var isClosed = false
    
    //The init method not necesarilly is being executed in the streamingQueue
    init(_ stream:InputStream,owner:InputStreamOwnerDelegate,queue:DispatchQueue) {
        self.stream = stream
        self.owner = owner
        self.queue = queue
        super.init()
        owner.addInputStreamHandler(self)
        
        stream.delegate = self
        stream.schedule(in: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
        
    }
    
    deinit {
        close()
    }
    
    func close() {
        isClosed = true
        
        guard let aStream = stream else {
            return
        }
        let weakSelf = self
        DispatchQueue.main.async {
            aStream.close()
            aStream.remove(from: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
            aStream.delegate = nil
            weakSelf.owner.removeInputStreamHandler(self)
            weakSelf.stream = nil
        }
    }
    
    //This function is called in the thread associated with stream.schedule(runLoop: main | current)
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        let weakSelf = self
        switch eventCode {
        case Stream.Event.openCompleted:
            //            print("Stream.Event.openCompleted \(aStream.description)")
            break
        case Stream.Event.hasSpaceAvailable:
            //            print("Stream.Event.hasSpaceAvailable \(aStream.streamStatus)")
            break
        case Stream.Event.hasBytesAvailable:
            //            print("Stream.Event.hasBytesAvailable \(aStream.description)")
            guard let iStream = weakSelf.stream else {
                return
            }
            queue.async {
                let bufferSize = weakSelf.len
                
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                
                defer {
                    buf.deallocate(capacity: bufferSize)
                }
                
                if weakSelf.isClosed {
                    return
                }
                
                let readResult = iStream.read(buf, maxLength: bufferSize)
                
                if readResult < 0 {
                    //                    print("error in InputStreamHandler: \(iStream.streamError?.localizedDescription ?? "no error description")")
                    //                    print("I will close the stream")
                    weakSelf.close()
                    return
                }
                
                if readResult > 0 {
                    weakSelf.mdata.append(buf, length: readResult)
                    weakSelf.len = readResult
                } else {
                    let obtainedImage = CIImage(data: weakSelf.mdata as Data)
                    DispatchQueue.main.async {
                        weakSelf.completionBlock?(obtainedImage)
                    }
                }
            }
            
            break
        case Stream.Event.endEncountered:
            //            print("Stream.Event.endEncountered \(aStream.description)")
            weakSelf.close()
            break
        case Stream.Event.errorOccurred:
            print("Stream.Event.errorOccurred \(aStream.streamStatus)")
            weakSelf.close()
            break
        default:
            print("Unrecognized Stream.Event \(aStream.streamStatus)")
        }
    }
}

