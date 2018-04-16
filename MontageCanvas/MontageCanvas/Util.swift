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

let offsetUptimeTo1970 = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
let DEFAULT_TIMESCALE = Int32(600)

extension UITouch {
    var timestamp1970:TimeInterval {
        return self.timestamp + offsetUptimeTo1970
    }
}

enum MontageRole:Int {
    case undefined = 0
    case iphoneCam
    case iPadCam
    case mirror
    case watchMirror
    case canvas
}

struct Globals {
    static var initialStrokeColor = UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0)
    static var initialFillColor = UIColor.clear
    static var initialLineWidth:Float = 10.0
    static var outIsPressedDown = false
    static var inIsPressedDown = false
    static var documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
}


public typealias TimeRange = CMTimeRange

public enum MutablePathAction:Int {
    case move = 0
    case addLine
}

public class PathAction: NSObject, NSCoding {
    var cgPoint:CGPoint
    var action:MutablePathAction

    init(_ action:MutablePathAction,_ point:CGPoint) {
        self.action = action
        self.cgPoint = point
    }

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(action.rawValue, forKey: "action")
        aCoder.encode(cgPoint, forKey: "cgPoint")
    }

    public required init?(coder aDecoder: NSCoder) {
        action = MutablePathAction(rawValue: aDecoder.decodeInteger(forKey: "action"))!
        cgPoint = aDecoder.decodeCGPoint(forKey: "cgPoint")

        super.init()
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

extension CGPoint {
    func distance(_ other:CGPoint) -> CGFloat {
        return hypot(self.x - other.x, self.y - other.y)
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
        self.present(alert, animated: true, completion: completion)
    }
}

extension NSManagedObject {
    var isReallyDeleted:Bool {
        return isDeleted || managedObjectContext == nil
    }
}
