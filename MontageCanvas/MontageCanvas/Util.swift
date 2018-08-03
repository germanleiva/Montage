//
//  Util.swift
//  Montage
//
//  Created by Germán Leiva on 05/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import CoreData
import Vision

let offsetUptimeTo1970 = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
let DEFAULT_TIMESCALE = Int32(600)

extension NSObjectProtocol {
    
    var className: String {
        return String(describing: Self.self)
    }
}

extension UITouch {
    var timestamp1970:TimeInterval {
        return self.timestamp + offsetUptimeTo1970
    }
}

struct Globals {
    static var initialStrokeColor = UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0)
    static var initialFillColor = UIColor.clear
    static var initialLineWidth:Float = 10.0
    static var outIsPressedDown = false
    static var inIsPressedDown = false
    static var documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    static var temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    static var defaultRenderSize = CGSize(width: 1280,height: 720)

}

public typealias Rect = CGRect
public typealias RectangleObservation = VNRectangleObservation
public typealias Time = CMTime
public typealias TimeRange = CMTimeRange

public enum MutablePathAction:Int32 {
    case move = 0
    case addLine
}

public class PathAction: NSObject, NSCoding {
    var cgPoint:CGPoint
    var action:MutablePathAction
    var relativeTimeStamp:TimeInterval

    init(_ action:MutablePathAction,_ point:CGPoint,_ timestamp:TimeInterval) {
        self.action = action
        self.cgPoint = point
        self.relativeTimeStamp = timestamp
    }

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(action.rawValue, forKey: "action")
        aCoder.encode(cgPoint, forKey: "cgPoint")
        aCoder.encode(relativeTimeStamp, forKey: "relativeTimeStamp")
    }

    public required init?(coder aDecoder: NSCoder) {
        action = MutablePathAction(rawValue: aDecoder.decodeInt32(forKey: "action"))!
        cgPoint = aDecoder.decodeCGPoint(forKey: "cgPoint")
        relativeTimeStamp = aDecoder.decodeDouble(forKey: "relativeTimeStamp")
        
        super.init()
    }
    
    func clone() -> PathAction {
        return PathAction(action,cgPoint,relativeTimeStamp)
        
    }
}

public class PointWrapper: NSObject, NSCoding {
    var cgPoint:CGPoint
    
    init(_ point:CGPoint) {
        self.cgPoint = point
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(cgPoint, forKey: "cgPoint")
    }
    
    public required init?(coder aDecoder: NSCoder) {
        cgPoint = aDecoder.decodeCGPoint(forKey: "cgPoint")
        super.init()
    }

}

public class AffineTransformWrapper: NSObject, NSCoding {
    var cgAffineTransform:CGAffineTransform
    
    init(_ affineTransform:CGAffineTransform) {
        self.cgAffineTransform = affineTransform
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(cgAffineTransform, forKey: "cgAffineTransform")
    }
    
    public required init?(coder aDecoder: NSCoder) {
        cgAffineTransform = aDecoder.decodeCGAffineTransform(forKey: "cgAffineTransform")
        super.init()
    }
}

extension CGPoint {
    func distance(_ other:CGPoint) -> CGFloat {
        return hypot(self.x - other.x, self.y - other.y)
    }
    func scaled(to size: CGSize) -> CGPoint {
        return CGPoint(x: self.x * size.width, y: self.y * size.height)
    }
}

extension UIViewController {
    func alert(_ error: Error?, title:String, message:String, completion: (()->Void)? = nil) {
        let messageWithError:String
        if let error = error {
            messageWithError = "\(message) : \(error.localizedDescription)"
        } else {
            messageWithError = message
        }
        let alert = UIAlertController(title: title, message: messageWithError, preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: { (action) in
            alert.dismiss(animated: true, completion: nil)
        }))
        self.present(alert, animated: true, completion: completion)
    }
}

extension NSManagedObject {
    var isReallyDeleted:Bool {
        return isDeleted || managedObjectContext == nil
    }
}
