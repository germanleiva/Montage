//
//  BoxObservation+CoreDataClass.swift
//  
//
//  Created by Germán Leiva on 29/07/2018.
//
//

import Foundation
import CoreData
import AVFoundation
import Vision

@objc(BoxObservation)
public class BoxObservation: NSManagedObject {
    lazy var time:CMTime = {
        return CMTime(value:value,timescale:timescale)
    }()
}
