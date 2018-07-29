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
    
    convenience init(moc:NSManagedObjectContext, time: CMTime, rectangleObservation: VNRectangleObservation) {
        let entity = NSEntityDescription.entity(forEntityName: "BoxObservation", in: moc)
        self.init(entity: entity!, insertInto: moc)

        self.value = time.value
        self.timescale = time.timescale

        self.observation = rectangleObservation
    }
}
