//
//  Tier+CoreDataClass.swift
//  Montage
//
//  Created by Germán Leiva on 12/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//
//

import Foundation
import CoreData
import AVFoundation

enum Transformation {
    case move(point:CGPoint)
    case addLine(point:CGPoint)
    case transform(affineTransform:CGAffineTransform)
    case changeStrokeEnd(strokeEndPercentage:CGFloat)
    case changeStrokeStart(strokeStartPercentage:CGFloat)
}

enum TierModification {
    case rotated
    case moved
    case scaled
    case appear
    case disappear
    case strokeStart
    case strokeEnd
}

@objc(Tier)
public class Tier: NSManagedObject {
    var recordedPathInputs = [(TimeInterval,Transformation)]()
    var recordedStrokeStartInputs = [(TimeInterval,Transformation)]()
    var recordedStrokeEndInputs = [(TimeInterval,Transformation)]()
//    var recordedOpacityInputs = [(TimeInterval,Transformation)]()
    var recordedTransformInputs = [(TimeInterval,Transformation)]()

    var translation:CGPoint?  {
        get {
            return translationValue?.cgPoint
        }
        set(newValue) {
            if let newValue = newValue {
                translationValue = PointWrapper(newValue)
            }
            self.applyCurrentTransformation()
        }
    }
    var rotation:CGFloat? {
        get {
            return CGFloat(rotationValue)
        }
        set(newValue) {
            if let newValue = newValue {
                rotationValue = Float(newValue)
            }
            self.applyCurrentTransformation()
        }
    }
    var scaling:CGPoint? {
        get {
            return scalingValue?.cgPoint
        }
        set(newValue) {
            if let newValue = newValue {
                scalingValue = PointWrapper(newValue)
            }
            self.applyCurrentTransformation()
        }
    }
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        sketch = Sketch(context: managedObjectContext!)
    }
    
    var appearAtTimes:[TimeInterval] {
        get {
            if innerAppearAtTimes == nil {
                innerAppearAtTimes = [NSNumber]()
            }
            return innerAppearAtTimes!.map { $0.doubleValue }
        }
        set(newValue) {
            print("Setting appearAtTimes \(newValue) for \(objectID)")
            innerAppearAtTimes = newValue.map { NSNumber(value:$0) }
        }
    }
    
    var disappearAtTimes:[TimeInterval] {
        get {
            if innerDisappearAtTimes == nil {
                innerDisappearAtTimes = [NSNumber]()
            }
            return innerDisappearAtTimes!.map { $0.doubleValue }
        }
        set(newValue) {
            print("Setting disappearAtTimes \(newValue) for \(objectID)")
            innerDisappearAtTimes = newValue.map { NSNumber(value:$0) }
        }

    }
    
    public override func prepareForDeletion() {
        self.shapeLayer.removeFromSuperlayer()
        self.shapeLayer.removeAllAnimations()
        self._shapeLayer = nil
        super.prepareForDeletion()
    }
    
    var _shapeLayer:CAShapeLayer? = nil
    var shapeLayer:CAShapeLayer {
        if _shapeLayer == nil {
            _shapeLayer = self.buildShapeLayer()
        }
        return _shapeLayer!
    }
    
    func buildShapeLayer() -> CAShapeLayer {
        return sketch!.buildShapeLayer(for: self)
    }
    
    func redrawShapeLayer() {
        let potentialSuperlayer = shapeLayer.superlayer
        shapeLayer.removeFromSuperlayer()
        _shapeLayer = nil //Destroys the cache _shapeLayer
        let newLayer = shapeLayer
        if let superLayer = potentialSuperlayer {
            superLayer.addSublayer(newLayer)
        }
    }
        
    var mutableShapeLayerPath:CGMutablePath {
        return shapeLayer.path! as! CGMutablePath
    }
    
    var currentTransformation:CGAffineTransform {
        let bounds = mutableShapeLayerPath.boundingBoxOfPath //TODO: should I use the path of my sketch?
        let center = CGPoint(x: bounds.midX,y: bounds.midY)
        var transform = CGAffineTransform.identity
        
        // Start with the translation
        if let translation = translation {
            transform = transform.translatedBy(x: translation.x, y: translation.y)
        }
        
        // Apply rotation
        if let rotation = rotation {
            //To rotate acoording to the center we translate there, scale, and we undo it
            transform = transform.translatedBy(x: center.x, y: center.y).rotated(by: rotation).translatedBy(x: -center.x, y: -center.y)
        }
        
        // Apply scaling
        if let scaling = scaling {
            //To scale acoording to the center we translate there, scale, and we undo it
            transform = transform.translatedBy(x: center.x, y: center.y).scaledBy(x: scaling.x, y: scaling.y).translatedBy(x: -center.x, y: -center.y)
        }
        return transform
    }
    
    func applyCurrentTransformation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.setAffineTransform(currentTransformation)
        CATransaction.commit()
    }
    
    func translationDelta(_ delta:CGPoint, timestamp:TimeInterval?) {
        let translation = self.translation ?? CGPoint.zero
        self.translation = CGPoint(x: translation.x + delta.x,y: translation.y + delta.y)
        
        if let timestamp = timestamp {
//            recordedInputs.append((Date().timeIntervalSince1970,.translation(delta: delta)))
            recordedTransformInputs.append((timestamp,.transform(affineTransform: currentTransformation)))
        }
    }
    
    func rotationDelta(_ delta:CGFloat, timestamp:TimeInterval?) {
        let rotation = self.rotation ?? CGFloat(0)
        self.rotation = rotation + delta
        
        if let timestamp = timestamp {
//            recordedInputs.append((Date().timeIntervalSince1970,.rotation(angle: delta)))
            recordedTransformInputs.append((timestamp,.transform(affineTransform: currentTransformation)))
        }
    }
    
    func scalingDelta(_ delta:CGPoint, timestamp:TimeInterval?) {
        let scaling = self.scaling ?? CGPoint(x:1,y:1)
        self.scaling = CGPoint(x: scaling.x * delta.x,y: scaling.y * delta.y)
        
        if let timestamp = timestamp {
//            recordedInputs.append((Date().timeIntervalSince1970,.scaling(delta: delta)))
            recordedTransformInputs.append((timestamp,.transform(affineTransform: currentTransformation)))
        }
    }
    
    // MARK: Path
    var hasNoPoints:Bool {
        return sketch!.pathActions!.isEmpty
    }
    
    func addFirstPoint(_ touchLocation:CGPoint,timestamp:TimeInterval?, shouldRecord:Bool) {
        sketch?.move(to:touchLocation)

        mutableShapeLayerPath.move(to: touchLocation)
        shapeLayer.didChangeValue(for: \CAShapeLayer.path)
        
        if shouldRecord, let timestamp = timestamp {
            print("saving addFirstPoint with normalized timestamp \(timestamp)")
            recordedPathInputs.append((timestamp, .move(point: touchLocation)))
        }
    }
    
    func addPoint(_ touchLocation:CGPoint,timestamp:TimeInterval?, shouldRecord:Bool) {
        sketch?.addLine(to:touchLocation)
        
        mutableShapeLayerPath.addLine(to: touchLocation)
        shapeLayer.didChangeValue(for: \CAShapeLayer.path)
        
        if shouldRecord, let timestamp = timestamp {
            print("saving addPoint with normalized timestamp \(timestamp)")
            recordedPathInputs.append((timestamp, .addLine(point: touchLocation)))
        }
    }
    
    func strokeEndChanged(_ percentage:CGFloat, timestamp:TimeInterval?) {
        if let timestamp = timestamp {
            recordedStrokeEndInputs.append((timestamp, .changeStrokeEnd(strokeEndPercentage: percentage)))
        }
    }
    
    func strokeStartChanged(_ percentage:CGFloat, timestamp:TimeInterval?) {
        if let timestamp = timestamp {
            recordedStrokeStartInputs.append((timestamp, .changeStrokeStart(strokeStartPercentage: percentage)))
        }
    }
    
    // MARK: Animation
    
    func rebuildAnimations(forLayer shapeLayer:CAShapeLayer, totalRecordingTime:TimeInterval) {
        let (appearAnimation,inkAnimation,strokeEndAnimation,strokeStartAnimation,transformationAnimation) = buildAnimations(totalRecordingTime:totalRecordingTime)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.opacity = 1 //When animations are active, the shape opacity should always start at 1 (visible)
        CATransaction.commit()
        
        shapeLayer.removeAnimation(forKey: "appearAnimation")
        if let appearAnimation = appearAnimation {
            shapeLayer.add(appearAnimation, forKey: "appearAnimation")
        }
        
        shapeLayer.removeAnimation(forKey: "inkAnimation")
        if let inkAnimation = inkAnimation {
//            CATransaction.begin()
//            CATransaction.setDisableActions(true)
//            shapeLayer.strokeEnd = 0
//            CATransaction.commit()
            shapeLayer.add(inkAnimation, forKey: "inkAnimation")
        }
        
        shapeLayer.removeAnimation(forKey: "strokeEndAnimation")
        if let strokeEndAnimation = strokeEndAnimation {
//            CATransaction.begin()
//            CATransaction.setDisableActions(true)
//            shapeLayer.strokeEnd = 1
//            CATransaction.commit()
            shapeLayer.add(strokeEndAnimation, forKey: "strokeEndAnimation")
        }
        
        shapeLayer.removeAnimation(forKey: "strokeStartAnimation")
        if let strokeStartAnimation = strokeStartAnimation {
            //            CATransaction.begin()
            //            CATransaction.setDisableActions(true)
            //            shapeLayer.strokeEnd = 1
            //            CATransaction.commit()
            shapeLayer.add(strokeStartAnimation, forKey: "strokeStartAnimation")
        }
        
        shapeLayer.removeAnimation(forKey: "transformationAnimation")
        if let transformationAnimation = transformationAnimation {
//            CATransaction.begin()
//            CATransaction.setDisableActions(true)
//            shapeLayer.transform = CATransform3DIdentity
//            CATransaction.commit()
            shapeLayer.add(transformationAnimation, forKey: "transformationAnimation")
        }
    }
    
    func buildAnimations(totalRecordingTime:TimeInterval) -> (appearAnimation:CAKeyframeAnimation?,inkAnimation:CAKeyframeAnimation?,strokeEndAnimation:CAKeyframeAnimation?,strokeStartAnimation:CAKeyframeAnimation?,transformationAnimation:CAKeyframeAnimation?) {
        print("buildAnimations >> START \(self)")

        var inkAnimation:CAKeyframeAnimation?
        
        if let totalDistance = sketch?.pathLength, !recordedPathInputs.isEmpty {
            
            var accumDistance:CGFloat = 0
            var currentPoint:CGPoint?
            
            let animationDuration = totalRecordingTime
            
            var inkValues = [CGFloat(0)]
            var keyTimes = [NSNumber(value:0)]
            
            for (timestamp, pathTransformation) in recordedPathInputs {
                switch pathTransformation {
                case let .move(point):
                    currentPoint = point
                    let percentage = timestamp / animationDuration
                    keyTimes.append(NSNumber(value:percentage))
                case let .addLine(point):
                    inkValues.append(CGFloat(accumDistance/totalDistance))
                    if let lastPoint = currentPoint {
                        accumDistance += point.distance(lastPoint)
                    }
                    currentPoint = point
                    let percentage = timestamp / animationDuration
                    keyTimes.append(NSNumber(value:percentage))
                default:
                    print("does not apply to recordedPathInputs")
                }
            }
            
            if !inkValues.isEmpty {
                let newStrokeEndAnimation = CAKeyframeAnimation()
                newStrokeEndAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
                newStrokeEndAnimation.calculationMode = kCAAnimationDiscrete
                newStrokeEndAnimation.keyPath = "strokeEnd"
                newStrokeEndAnimation.values = inkValues
                newStrokeEndAnimation.keyTimes = keyTimes
                newStrokeEndAnimation.duration = animationDuration
                newStrokeEndAnimation.fillMode = kCAFillModeForwards //the changes caused by the animation will hang around
                newStrokeEndAnimation.isRemovedOnCompletion = false
                
                inkAnimation = newStrokeEndAnimation
                
                print("buildAnimations >> inkAnimation: \(newStrokeEndAnimation.debugDescription)")
            }
        }
        
        var strokeEndAnimation:CAKeyframeAnimation?
        
        if !recordedStrokeEndInputs.isEmpty {
            
            let animationDuration = totalRecordingTime
            
            var strokeEndValues = [CGFloat(1)]
            var keyTimes = [NSNumber(value:0)]

            for (timestamp, strokeChangedTransformation) in recordedStrokeEndInputs {
                switch strokeChangedTransformation {
                case let .changeStrokeEnd(strokeEndPercentage):
                    strokeEndValues.append(strokeEndPercentage)
                    
                    let percentage = timestamp / animationDuration
                    keyTimes.append(NSNumber(value:percentage))
                default:
                    print("does not apply to recordedStrokeEndInputs")
                }
            }
            
            if !strokeEndValues.isEmpty {
                let newStrokeEndAnimation = CAKeyframeAnimation()
                newStrokeEndAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
                newStrokeEndAnimation.calculationMode = kCAAnimationDiscrete
                newStrokeEndAnimation.keyPath = "strokeEnd"
                newStrokeEndAnimation.values = strokeEndValues
                newStrokeEndAnimation.keyTimes = keyTimes
                newStrokeEndAnimation.duration = animationDuration
                newStrokeEndAnimation.fillMode = kCAFillModeForwards //the changes caused by the animation will hang around
                newStrokeEndAnimation.isRemovedOnCompletion = false
                
                strokeEndAnimation = newStrokeEndAnimation
                
                print("buildAnimations >> strokeEndAnimation: \(newStrokeEndAnimation.debugDescription)")
            }
        }
        
        var strokeStartAnimation:CAKeyframeAnimation?
        
        if !recordedStrokeStartInputs.isEmpty {
            
            let animationDuration = totalRecordingTime
            
            var strokeStartValues = [CGFloat(0)]
            var keyTimes = [NSNumber(value:0)]
            
            for (timestamp, strokeChangedTransformation) in recordedStrokeStartInputs {
                switch strokeChangedTransformation {
                case let .changeStrokeStart(strokeStartPercentage):
                    strokeStartValues.append(strokeStartPercentage)
                    
                    let percentage = timestamp / animationDuration
                    keyTimes.append(NSNumber(value:percentage))
                default:
                    print("does not apply to recordedStrokeStartInputs")
                }
            }
            
            if !strokeStartValues.isEmpty {
                let newStrokeStartAnimation = CAKeyframeAnimation()
                newStrokeStartAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
                newStrokeStartAnimation.calculationMode = kCAAnimationDiscrete
                newStrokeStartAnimation.keyPath = "strokeStart"
                newStrokeStartAnimation.values = strokeStartValues
                newStrokeStartAnimation.keyTimes = keyTimes
                newStrokeStartAnimation.duration = animationDuration
                newStrokeStartAnimation.fillMode = kCAFillModeForwards //the changes caused by the animation will hang around
                newStrokeStartAnimation.isRemovedOnCompletion = false
                
                strokeStartAnimation = newStrokeStartAnimation
                
                print("buildAnimations >> strokeStartnimation: \(newStrokeStartAnimation.debugDescription)")
            }
        }
        
        var transformationAnimation:CAKeyframeAnimation?
        
        if !recordedTransformInputs.isEmpty {
            
            let animationDuration = totalRecordingTime
            
            var transformValues = [CATransform3DIdentity]
            var transformKeyTimes = [NSNumber(value:0)]
            
            for (timestamp, transformTransformation) in recordedTransformInputs {
                switch transformTransformation {
                case let .transform(affineTransform):
                    transformValues.append(CATransform3DMakeAffineTransform(affineTransform))
                    let percentage = timestamp / animationDuration
                    transformKeyTimes.append(NSNumber(value:percentage))
                default:
                    print("does not apply to recordedTransformInputs")
                }
            }
            
            if !transformValues.isEmpty {
                let newTransformAnimation = CAKeyframeAnimation()
                newTransformAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
                newTransformAnimation.calculationMode = kCAAnimationDiscrete
                newTransformAnimation.keyPath = "transform"
                newTransformAnimation.values = transformValues
                newTransformAnimation.keyTimes = transformKeyTimes
                newTransformAnimation.duration = animationDuration
                newTransformAnimation.fillMode = kCAFillModeForwards //the changes caused by the animation will hang around
                newTransformAnimation.isRemovedOnCompletion = false
                
                transformationAnimation = newTransformAnimation
                
                print("buildAnimations >> transformationAnimation: \(transformationAnimation.debugDescription)")
            }
        }
        
        var toggleAnimation:CAKeyframeAnimation?
        
        let animationDuration = totalRecordingTime
        
        var calculatedValues = [(Double,Int)]()
        
        let appearAtTimesToCheck:[TimeInterval]
        
        if appearAtTimes.isEmpty {
            appearAtTimesToCheck = [animationDuration * 0.0001] //At the 0.01% of the animationDuration
        } else {
            appearAtTimesToCheck = appearAtTimes
        }
        
        for eachAppearanceTime in appearAtTimesToCheck {
            let percentage = eachAppearanceTime / animationDuration
            calculatedValues.append((percentage,1))
        }
        
        for eachDisappearanceTime in [0] + disappearAtTimes + [totalRecordingTime] {
            let percentage = eachDisappearanceTime / animationDuration
            calculatedValues.append((percentage,0))
        }
        
        calculatedValues.sort { $0.0 < $1.0 }
        
        let keyTimes = calculatedValues.map { NSNumber(value:$0.0) }
        let opacityValues = calculatedValues.map { $0.1 }
        
        toggleAnimation = CAKeyframeAnimation()
        toggleAnimation!.beginTime = AVCoreAnimationBeginTimeAtZero
        toggleAnimation!.calculationMode = kCAAnimationDiscrete
        toggleAnimation!.keyPath = "opacity"
        toggleAnimation!.values = opacityValues
        toggleAnimation!.keyTimes = keyTimes
        toggleAnimation!.duration = animationDuration
        toggleAnimation!.fillMode = kCAFillModeForwards //the changes caused by the animation will hang around
        toggleAnimation!.isRemovedOnCompletion = false
        
        print("buildAnimations >> toggleAnimation: \(toggleAnimation!.debugDescription)")
        //CAAnimationGroup do not work with AVSyncronizedLayer
        //        let strokeAndMove = CAAnimationGroup()
        //        strokeAndMove.animations = [strokeEndAnimation, transformAnimation]
        //        strokeAndMove.beginTime = AVCoreAnimationBeginTimeAtZero
        //        strokeAndMove.duration = endedRecordingAt - startedRecordingAt
        
        //        print("-----> \(appearedAt)")
        print("buildAnimations >> FINISH")
            
        return (toggleAnimation,inkAnimation,strokeEndAnimation,strokeStartAnimation,transformationAnimation)
    }
    
    var isSelected:Bool {
        get {
            return self.selected
        }
        set(newValue) {
            self.selected = newValue
        }
    }
}
