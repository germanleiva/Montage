//
//  OutputStreamHandler.swift
//  MontageCam
//
//  Created by Germán Leiva on 14/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import MultipeerConnectivity


protocol OutputStreamOwner:class {
    func addOutputStreamHandler(_ outputStreamHandler:OutputStreamHandler)
    
    func removeOutputStreamHandler(_ outputStreamHandler:OutputStreamHandler)
    
}

class OutputStreamHandler: NSObject,StreamDelegate {
    static let DATA_LENGTH = 4 * 1024 //4096
//    static let DATA_LENGTH = 8 * 1024 //8192

    var owner:OutputStreamOwner
    var len = DATA_LENGTH
    var byteIndex = 0
    var completionBlock:((UIImage?)->Void)? = nil
    var stream:OutputStream?
    var data:NSData
    var queue:DispatchQueue
    var isClosed = false
    
    init(_ stream:OutputStream,owner:OutputStreamOwner,data:NSData,queue:DispatchQueue) {
        self.stream = stream
        self.owner = owner
        self.data = data
        self.queue = queue
        super.init()
        owner.addOutputStreamHandler(self)
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
            weakSelf.owner.removeOutputStreamHandler(self)
            weakSelf.stream = nil
        }
    }
    
    //This function is called in the thread associated with stream.schedule(runLoop: main | current)
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        let weakSelf = self
        switch eventCode {
        case Stream.Event.openCompleted:
//            print("\(aStream.description) Stream.Event.openCompleted")
            break
        case Stream.Event.hasSpaceAvailable:
//            print("\(aStream.description) Stream.Event.hasSpaceAvailable")
            guard let oStream = weakSelf.stream else {
                return
            }
            queue.async {
                
                if (weakSelf.data.length > 0 && weakSelf.len >= 0 && (weakSelf.byteIndex <= weakSelf.data.length)) {
                    //                    print("\(stream.description) START | data.length: \(data.length)  byteIndex: \(byteIndex)  intended write len: \(len)")
                    weakSelf.len = (weakSelf.data.length - weakSelf.byteIndex) < OutputStreamHandler.DATA_LENGTH ? (weakSelf.data.length - weakSelf.byteIndex) : OutputStreamHandler.DATA_LENGTH;
                    
                    let bufferSize = weakSelf.len
                    
                    let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                    
                    defer {
                        bytes.deallocate(capacity: bufferSize)
                    }
                    
                    weakSelf.data.getBytes(bytes, range: NSMakeRange(weakSelf.byteIndex,weakSelf.len))
                    
                    if weakSelf.isClosed {
                        return
                    }
                    
                    let result = oStream.write(bytes, maxLength: weakSelf.len)
                    if result < 0 {
                        print("There was an error while writing \(oStream.streamError?.localizedDescription ?? "no error description")")
                        print("closing stream")
                        weakSelf.close()
                        return
                    }
                    
                    weakSelf.byteIndex += result
                    
                    //                print("\(stream?.description) END | data.length: \(data.length)  byteIndex: \(byteIndex)  next write len: \(len)")
                }
                
            }
            
            break
        case Stream.Event.endEncountered:
//            print("\(aStream.description) endEncountered")
            close()
            break
        case Stream.Event.errorOccurred:
            print("!!! errorOccurred, i will close the stream")
            close()
            break
        default:
            print("Not handling streaming event code \(eventCode)")
        }
    }
}
