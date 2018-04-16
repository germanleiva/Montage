//
//  Sketch+CoreDataClass.swift
//  Montage
//
//  Created by Germán Leiva on 12/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//
//

import Foundation
import CoreData

@objc(Sketch)
public class Sketch: NSManagedObject {
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        strokeColor = Globals.initialStrokeColor
        lineCap = "round"
        fillColor = Globals.initialFillColor
        lineWidth = Globals.initialLineWidth
        
        pathActions = [PathAction]()
    }
    
    func move(to point:CGPoint) {
        pathActions?.append(PathAction(.move,point))
        _cachedMutablePath = nil
    }
    
    func addLine(to point:CGPoint) {
        pathActions?.append(PathAction(.addLine,point))
        _cachedMutablePath = nil
    }
    
    var pathLength:CGFloat {
        var previousPoint:CGPoint?
        var length:CGFloat = 0
        
        for pathAction in pathActions! {
            let point = pathAction.cgPoint
            
            switch pathAction.action {
            case .move:
                break
            case .addLine:
                if let lastPoint = previousPoint {
                    length += point.distance(lastPoint)
                }
                break
            }
            
            previousPoint = point
        }
        return length
    }
    
    private var _cachedMutablePath:CGMutablePath? = nil
    var mutablePath:CGMutablePath {
        if _cachedMutablePath == nil {
            let mutablePath = CGMutablePath()
            
            for pathAction in pathActions! {
                let point = pathAction.cgPoint

                switch pathAction.action {
                case .move:
                    mutablePath.move(to:point)
                    break
                case .addLine:
                    mutablePath.addLine(to:point)
                    break
                }
            }
            
            _cachedMutablePath = mutablePath
        }
        
        return _cachedMutablePath!
    }
    
    func buildShapeLayer(for tier:Tier) -> CAShapeLayer {
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = mutablePath.mutableCopy()
        shapeLayer.strokeColor = tier.strokeColor?.cgColor ?? strokeColor!.cgColor
        shapeLayer.lineCap = lineCap!
        shapeLayer.fillColor = tier.fillColor?.cgColor ?? fillColor!.cgColor
        shapeLayer.lineWidth = tier.lineWidth == 0 ? CGFloat(lineWidth) : CGFloat(tier.lineWidth)
        return shapeLayer
    }
}
