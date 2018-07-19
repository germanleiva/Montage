//
//  InputStreamer.swift
//  CamReceiver
//
//  Created by Germán Leiva on 14/04/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import MultipeerConnectivity
import AVFoundation

public protocol InputStreamerDelegate:class {
    func inputStreamer(_ streamer:InputStreamer, decodedImage ciImage:CIImage)
    func didClose(_ streamer:InputStreamer)
}

let naluTypesStrings:[UInt8:String] = [
    0: "Unspecified (non-VCL)",
    1: "Coded slice of a non-IDR picture (VCL)", // P frame
    2: "Coded slice data partition A (VCL)",
    3: "Coded slice data partition B (VCL)",
    4: "Coded slice data partition C (VCL)",
    5: "Coded slice of an IDR picture (VCL)", // I frame
    6: "Supplemental enhancement information (SEI) (non-VCL)",
    7: "Sequence parameter set (non-VCL)", // SPS parameter
    8: "Picture parameter set (non-VCL)", // PPS parameter
    9: "Access unit delimiter (non-VCL)",
    10: "End of sequence (non-VCL)",
    11: "End of stream (non-VCL)",
    12: "Filler data (non-VCL)",
    13: "Sequence parameter set extension (non-VCL)",
    14: "Prefix NAL unit (non-VCL)",
    15: "Subset sequence parameter set (non-VCL)",
    16: "Reserved (non-VCL)",
    17: "Reserved (non-VCL)",
    18: "Reserved (non-VCL)",
    19: "Coded slice of an auxiliary coded picture without partitioning (non-VCL)",
    20: "Coded slice extension (non-VCL)",
    21: "Coded slice extension for depth view components (non-VCL)",
    22: "Reserved (non-VCL)",
    23: "Reserved (non-VCL)",
    24: "STAP-A Single-time aggregation packet (non-VCL)",
    25: "STAP-B Single-time aggregation packet (non-VCL)",
    26: "MTAP16 Multi-time aggregation packet (non-VCL)",
    27: "MTAP24 Multi-time aggregation packet (non-VCL)",
    28: "FU-A Fragmentation unit (non-VCL)",
    29: "FU-B Fragmentation unit (non-VCL)",
    30: "Unspecified (non-VCL)",
    31: "Unspecified (non-VCL)",
]

enum NaluType:UInt8 {
    case sps = 7
    case pps = 8
    case nonIDR = 1
    case IDR = 5
    case SEI = 6
}

let sepdata = Data([0x0,0x0,0x0,0x1])
public let simpleSepdata = Data([0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x1])

public class InputStreamer: NSObject, VideoDecoderDelegate, StreamDelegate {
    public private(set) var peerID: MCPeerID
    public weak var delegate:InputStreamerDelegate?
    var stream:InputStream
    var readingQueue:DispatchQueue
    var savedDataSampleBuffer = Data()
    var decoder: H264Decoder?
    public var isSimpleData = false
    var isRunning = false {
        didSet {
            print("Running changed \(peerID.description) isRunning \(isRunning)")
        }
    }
    
    public init(_ peerID:MCPeerID, stream:InputStream) {
        self.peerID = peerID
        self.stream = stream
        self.readingQueue = DispatchQueue(label: "readingQueue-\(peerID.description) \(Date())")
        super.init()
        
        self.stream.delegate = self
        self.stream.schedule(in: RunLoop.main, forMode: RunLoopMode.commonModes)
        self.stream.open()
        
        self.isRunning = true 
    }
    
    // -MARK: VideoDecoderDelegate
    func sampleOutput(video sampleBuffer: CMSampleBuffer) {
        //        print("**** decoded \(Date().timeIntervalSinceReferenceDate)")
        
        guard let cvImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let finalImage = CIImage(cvImageBuffer: cvImageBuffer)
        
        guard let aDelegate = self.delegate else {
            return
        }
        
        DispatchQueue.main.async {
            aDelegate.inputStreamer(self, decodedImage:finalImage)
        }
    }
    
    // Stream delegate
    
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard let iStream = aStream as? InputStream else {
            return
        }
        switch eventCode {
        case .openCompleted:
            print("Stream.Event.openCompleted \(iStream.description)")
        case .hasSpaceAvailable:
            print("Stream.Event.hasSpaceAvailable \(iStream.streamStatus)")
        case .hasBytesAvailable:
//            print("Stream.Event.hasBytesAvailable \(iStream.description)")
            let weakSelf = self
            readingQueue.async {[unowned self] in
                if !weakSelf.isRunning {
                    return
                }
                
                let bufferSize = 8 * 1024
                
                let readingSampleBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                
                defer {
                    readingSampleBuffer.deallocate()
                }
                
                let readResult = iStream.read(readingSampleBuffer, maxLength: bufferSize)
                
                if readResult < 0 {
                    print("error readResult < 0: \(readResult)")
                    print("error in InputStreamHandler: \(iStream.streamError?.localizedDescription ?? "no error description")")
                    return
                }
                
                if readResult > 0 {
                    //                print("readResult > 0: \(readResult)")
                    self.savedDataSampleBuffer.append(readingSampleBuffer,count:readResult)
                    
                    let readingDataSampleBuffer = self.savedDataSampleBuffer
                    
                    if weakSelf.isSimpleData {
                        //The simpleData is just a bunch of bytes that end with simpleSepdata
                        let searchRange:Range<Data.Index> = 0 ..< readingDataSampleBuffer.count
                        guard let nextRange = readingDataSampleBuffer.range(of: simpleSepdata, options: [], in: searchRange) else {
                            //We need to keep reading
                            return
                        }
                        
                        let imageData = self.savedDataSampleBuffer.subdata(in: 0..<nextRange.lowerBound)

                        if self.savedDataSampleBuffer.count > nextRange.upperBound {
                            self.savedDataSampleBuffer = self.savedDataSampleBuffer.subdata(in: nextRange.upperBound + 1 ..< self.savedDataSampleBuffer.count)
                        } else {
                            self.savedDataSampleBuffer.removeAll()
                        }

//                        print("Trying to decode imageData into CIImage")
                        if let finalImage = CIImage(data: imageData) {
//                            print("Decoding successful, imageData into CIImage")
                            DispatchQueue.main.async {
                                weakSelf.delegate?.inputStreamer(self, decodedImage:finalImage)
                            }
                        } else {
                            print("Decoding failed, imageData into CIImage")
                        }
                        return
                    }
                    
                    guard readingDataSampleBuffer.count > 4 else {
                        print("not enough data")
                        return
                    }
                    
                    let searchRange:Range<Data.Index> = sepdata.count ..< readingDataSampleBuffer.count
                    var nextRange = readingDataSampleBuffer.range(of: sepdata, options: [], in: searchRange)
                    
                    if nextRange == nil {
                        //There are no chunks
                        return
                    }
                    
                    let firstChunk = readingDataSampleBuffer.subdata(in: 0..<nextRange!.lowerBound)
                    
                    if NaluType.sps.rawValue == firstChunk.bytes[4] & 0x1F {
                        //                    print("The first chunk is a SPS NALU")
                        //We need 2 more chunks, PPS and (IDR or SEI)
                        //                    guard chunks.count >= 3 else {
                        //                        print("We wait for PPS and IDR or SEI")
                        //                        return
                        //                    }
                        
                        let dataWithoutFirstChunk = readingDataSampleBuffer.advanced(by: firstChunk.count)
                        nextRange = dataWithoutFirstChunk.range(of: sepdata, options: [], in: sepdata.count..<dataWithoutFirstChunk.count)
                        
                        if nextRange == nil {
                            print("There is no second chunk and it is needed")
                            return
                        }
                        
                        let secondChunk = dataWithoutFirstChunk.subdata(in: 0..<nextRange!.lowerBound)
                        
                        guard NaluType.pps.rawValue == secondChunk.bytes[4] & 0x1F else {
                            print("Second chunk was expected to be PPS")
                            return
                        }
                        
                        let dataWithoutSecondChunk = dataWithoutFirstChunk.advanced(by: secondChunk.count)
                        nextRange = dataWithoutSecondChunk.range(of: sepdata, options: [], in: sepdata.count..<dataWithoutSecondChunk.count)
                        
                        if nextRange == nil {
                            print("There is no third chunk and it is needed")
                            return
                        }
                        
                        let thirdChunk = dataWithoutSecondChunk.subdata(in: 0..<nextRange!.lowerBound)
                        
                        let thirdNaluType = thirdChunk.bytes[4] & 0x1F
                        guard NaluType.nonIDR.rawValue == thirdNaluType || NaluType.IDR.rawValue == thirdNaluType || NaluType.SEI.rawValue == thirdNaluType else {
                            print("Third chunk was expected to be Non-IDR or IDR or SEI: \(thirdNaluType) \(thirdChunk.bytes[4])")
                            return
                        }
                        
                        var newFirst = Data()
                        newFirst.append(firstChunk)
                        newFirst.append(secondChunk)
                        newFirst.append(thirdChunk)
                        
                        self.interpretRawFrameData(newFirst.bytes)
                        
                        self.savedDataSampleBuffer = self.savedDataSampleBuffer.subdata(in: newFirst.count ..< self.savedDataSampleBuffer.count)
                        
                        return
                    } else {
                        //                    print("first chunk is not SPS, it has type \(firstChunk.bytes[4] & 0x1F)")
                        
                        //This last nextRange has the last delimiter range
                        nextRange = readingDataSampleBuffer.range(of: sepdata, options: Data.SearchOptions.backwards, in: sepdata.count..<readingDataSampleBuffer.count)
                        
                        if nextRange == nil {
                            return
                        }
                        
                        var bigChunk = readingDataSampleBuffer.subdata(in: 0..<nextRange!.lowerBound)
                        
                        var i = sepdata.count
                        var chunkInit = 0
                        let lastIndexToCheck = bigChunk.count - sepdata.count
                        while i <= lastIndexToCheck {
                            if [bigChunk[i],bigChunk[i+1],bigChunk[i+2],bigChunk[i+3]] == sepdata.bytes {
                                let nextChunk = bigChunk.subdata(in: chunkInit..<i)
                                self.interpretRawFrameData(nextChunk.bytes)
                                chunkInit = i
                                i += sepdata.count
                            } else {
                                i += 1
                            }
                        }
                        
                        bigChunk.removeFirst(chunkInit)
                        
                        if bigChunk.count > 0 {
                            self.interpretRawFrameData(bigChunk.bytes)
                        }
                        
                        //This last nextRange has the last delimiter range
                        self.savedDataSampleBuffer = self.savedDataSampleBuffer.subdata(in: nextRange!.lowerBound ..< self.savedDataSampleBuffer.count)
                    }
                    
                } else {
                    print("readResult == 0")
                }
            }
            
        case .endEncountered:
            print("Stream.Event.endEncountered \(iStream.description)")
            close()
        //            browser.startBrowsingForPeers()
        case .errorOccurred:
            print("Stream.Event.errorOccurred \(iStream.streamStatus)")
            close()
        //            browser.startBrowsingForPeers()
        default:
            print("Unrecognized Stream.Event \(iStream.streamStatus)")
        }
    }
    
    public func close() {
        let weakSelf = self
        
        weakSelf.readingQueue.async {
            
            guard weakSelf.isRunning else {
                return
            }
            
            weakSelf.isRunning = false
            
            DispatchQueue.main.async {
                weakSelf.stream.delegate = nil
                weakSelf.stream.remove(from: RunLoop.main, forMode: RunLoopMode.commonModes)
                weakSelf.stream.close()
                weakSelf.delegate?.didClose(weakSelf)
            }
        }
        
    }
    
    private var formatDesc: CMVideoFormatDescription?
    
    //    private var decompressionSession: VTDecompressionSession?
    /*
     Ideally, whoever calls this function would be returned the displayable frame.
     Still figuring that one out. In the meantime this stuff works.
     */
    func interpretRawFrameData(_ inmmutableFrameData: [UInt8]) {
        //        print("**** start decoding \(Date().timeIntervalSinceReferenceDate)")
        var frameData = inmmutableFrameData
        var naluType = frameData[4] & 0x1F
        if naluType != 7 && formatDesc == nil { return }
        
        // Replace start code with the size
        var frameSize = CFSwapInt32HostToBig(UInt32(frameData.count - 4))
        memcpy(&frameData, &frameSize, 4)
        
        // The start indices for nested packets. Default to 0.
        var ppsStartIndex = 0
        var frameStartIndex = 0
        
        var sps: Array<UInt8>?
        var pps: Array<UInt8>?
        
        /*
         Generally, SPS, PPS, and IDR frames from the camera will come packaged together
         while B/P frames will come individually. For the sake of flexibility this code
         does not reflect this bitstream format specifically.
         Sometimes we are receiveing SPS, PPS and B/P frames packed together for simplicity
         */
        
        // SPS parameters
        if naluType == 7 {
            //            print("===== NALU type SPS")
            for i in 4..<40 {
                if frameData[i] == 0 && frameData[i+1] == 0 && frameData[i+2] == 0 && frameData[i+3] == 1 {
                    ppsStartIndex = i // Includes the start header
                    sps = Array(frameData[4..<i])
                    
                    // Set naluType to the nested packet's NALU type
                    naluType = frameData[i + 4] & 0x1F
                    break
                }
            }
        }
        
        // PPS parameters
        if naluType == 8 {
            //            print("===== NALU type PPS")
            for i in ppsStartIndex+4..<ppsStartIndex+34 {
                if frameData[i] == 0 && frameData[i+1] == 0 && frameData[i+2] == 0 && frameData[i+3] == 1 {
                    frameStartIndex = i
                    pps = Array(frameData[ppsStartIndex+4..<i])
                    
                    // Set naluType to the nested packet's NALU type
                    naluType = frameData[i+4] & 0x1F
                    break
                }
            }
            
            if let sps = sps, let pps = pps, !createFormatDescription(sps: sps, pps: pps) {
                print("===== ===== Failed to create formatDesc")
                return
            }
            //            if !createDecompressionSession() {
            //                print("===== ===== Failed to create decompressionSession")
            //                return
            //            }
        }
        
        if (naluType == 1 || naluType == 5 || naluType == 6) && decoder != nil {
            //            print("===== NALU type \(naluType)")
            // If this is successful, the callback will be called
            // The callback will send the decoded, decompressed frame to the delegate
            decodeFrameData(Array(frameData[frameStartIndex...]))
            return
        }
        
        print("unrecognized NALU type \(naluType)")
    }
    
    private func decodeFrameData(_ frameData: [UInt8]) {
        let bufferPointer = UnsafeMutablePointer<UInt8>(mutating: frameData)
        
        // Replace the start code with the size of the NALU
        var frameSize = CFSwapInt32HostToBig(UInt32(frameData.count - 4))
        memcpy(bufferPointer, &frameSize, 4)
        
        //        var outputBuffer: CVPixelBuffer? = nil
        var blockBuffer: CMBlockBuffer? = nil
        var status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                        bufferPointer,
                                                        frameData.count,
                                                        kCFAllocatorNull,
                                                        nil, 0, frameData.count,
                                                        0, &blockBuffer)
        
        guard status == kCMBlockBufferNoErr else {
            let errorMessage = SecCopyErrorMessageString(status, nil) as String?
            print("Error: CMBlockBufferCreateWithMemoryBlock returned status \(errorMessage ?? "no description")")
            return
        }
        
        var sampleBuffer: CMSampleBuffer?
        let sampleSizeArray = [frameData.count]
        
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           formatDesc,
                                           1, 0, nil,
                                           1, sampleSizeArray,
                                           &sampleBuffer)
        
        
        guard let buffer = sampleBuffer else {
            print("CMSampleBufferCreateReady returned nil")
            return
        }
        
        guard status == kCMBlockBufferNoErr else {
            let errorMessage = SecCopyErrorMessageString(status, nil) as String?
            print("Error: CMSampleBufferCreateReady returned status \(errorMessage ?? "no description")")
            return
        }
        
        //        DispatchQueue.main.async {
        ////            print("SAMPLE BUFFER: \(buffer)")
        //            self.videoPlayerView.sampleBufferDisplayLayer.enqueue(buffer)
        //        }
        
        let attachments: CFArray? = CMSampleBufferGetSampleAttachmentsArray(buffer, true)
        
        if let attachmentsArray = attachments {
            let dic = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, 0), to: CFMutableDictionary.self)
            
            CFDictionarySetValue(dic,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            
            // Decompress
            //ADDED instead
            status = decoder?.decodeSampleBuffer(buffer) ?? noErr //noErr if decoder == nil
            
            /*
             var flagOut = VTDecodeInfoFlags(rawValue: 0)
             status = VTDecompressionSessionDecodeFrame(decompressionSession!, buffer,
             [], &outputBuffer, &flagOut)
             */
            guard status == kCMBlockBufferNoErr else {
                let errorMessage = SecCopyErrorMessageString(status, nil) as String?
                print("Error: VTDecompressionSessionDecodeFrame returned status \(errorMessage ?? "no description")")
                return
            }
            /* The "CMSampleBuffer" can be returned here and passed to an AVSampleBufferDisplayLayer.
             I tried it and the picture was ugly. Instead I decompress with VideoToolbox and then
             display the resultant CVPixelLayer. Looks great.
             */
        }
    }
    
    private func createFormatDescription(sps: [UInt8], pps: [UInt8]) -> Bool {
        formatDesc = nil
        
        let pointerSPS = UnsafePointer<UInt8>(sps)
        let pointerPPS = UnsafePointer<UInt8>(pps)
        
        let dataParamArray = [pointerSPS, pointerPPS]
        let parameterSetPointers = UnsafePointer<UnsafePointer<UInt8>>(dataParamArray)
        
        let sizeParamArray = [sps.count, pps.count]
        let parameterSetSizes = UnsafePointer<Int>(sizeParamArray)
        
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, parameterSetPointers, parameterSetSizes, 4, &formatDesc)
        
        guard status == kCMBlockBufferNoErr else {
            let errorMessage = SecCopyErrorMessageString(status, nil) as String?
            print("Error: CMVideoFormatDescriptionCreateFromH264ParameterSets returned status \(errorMessage ?? "no description")")
            return false
        }
        
        //ADded instead
        if decoder == nil {
            decoder = H264Decoder()
            decoder?.delegate = self
        }
        decoder?.formatDescription = formatDesc
        
        return true
    }
}
