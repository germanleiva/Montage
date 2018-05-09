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
}

@objc(Tier)
public class Tier: NSManagedObject {
    var isRecordingInputs:Bool {
        return videoTrack!.isRecordingInputs
    }
    var startedRecordingAt:TimeInterval {
        return videoTrack!.startedRecordingAt
    }
    var endedRecordingAt:TimeInterval {
        return videoTrack!.endedRecordingAt
    }

    var recordedInputs = [(TimeInterval,Transformation)]()
    
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
    
    func translationDelta(_ delta:CGPoint) {
        let translation = self.translation ?? CGPoint.zero
        self.translation = CGPoint(x: translation.x + delta.x,y: translation.y + delta.y)
        
        if isRecordingInputs {
//            recordedInputs.append((Date().timeIntervalSince1970,.translation(delta: delta)))
            recordedInputs.append((Date().timeIntervalSince1970 - videoTrack!.startedRecordingAt,.transform(affineTransform: currentTransformation)))
        }
    }
    
    func rotationDelta(_ delta:CGFloat) {
        let rotation = self.rotation ?? CGFloat(0)
        self.rotation = rotation + delta
        
        if isRecordingInputs {
//            recordedInputs.append((Date().timeIntervalSince1970,.rotation(angle: delta)))
            recordedInputs.append((Date().timeIntervalSince1970 - videoTrack!.startedRecordingAt,.transform(affineTransform: currentTransformation)))
        }
    }
    
    func scalingDelta(_ delta:CGPoint) {
        let scaling = self.scaling ?? CGPoint(x:1,y:1)
        self.scaling = CGPoint(x: scaling.x * delta.x,y: scaling.y * delta.y)
        
        if isRecordingInputs {
//            recordedInputs.append((Date().timeIntervalSince1970,.scaling(delta: delta)))
            recordedInputs.append((Date().timeIntervalSince1970 - videoTrack!.startedRecordingAt,.transform(affineTransform: currentTransformation)))
        }
    }
    
    // MARK: Path
    var hasNoPoints:Bool {
        return sketch!.pathActions!.isEmpty
    }
    
    func addFirstPoint(_ touchLocation:CGPoint,timestamp:TimeInterval) {
        sketch?.move(to:touchLocation)

        mutableShapeLayerPath.move(to: touchLocation)
        shapeLayer.didChangeValue(for: \CAShapeLayer.path)
        
        if isRecordingInputs {
            recordedInputs.append((timestamp - videoTrack!.startedRecordingAt, .move(point: touchLocation)))
        }
        
        appearedAt = NSNumber(value:timestamp - videoTrack!.startedRecordingAt)
        print("addFirstPoint appearedAt \(appearedAt)")
    }
    
    func addPoint(_ touchLocation:CGPoint,timestamp:TimeInterval) {
        sketch?.addLine(to:touchLocation)
        
        mutableShapeLayerPath.addLine(to: touchLocation)
        shapeLayer.didChangeValue(for: \CAShapeLayer.path)
        
        if isRecordingInputs {
            recordedInputs.append((timestamp - videoTrack!.startedRecordingAt, .addLine(point: touchLocation)))
        }
    }
    
    func strokeEndChanged(_ percentage:CGFloat, timestamp:TimeInterval) {
        if isRecordingInputs {
            recordedInputs.append((timestamp  - videoTrack!.startedRecordingAt, Transformation.changeStrokeEnd(strokeEndPercentage: percentage)))
        }
    }
    
    // MARK: Animation
    
    func buildAnimations() -> (appearAnimation:CAKeyframeAnimation?,strokeEndAnimation:CAKeyframeAnimation?,transformationAnimation:CAKeyframeAnimation?) {
        
        var animations = [CAKeyframeAnimation]()
        
        let path = CGMutablePath()
        
        var totalDistance:CGFloat = 0
        var lastPoint = CGPoint.zero
        var values = [CGFloat]()
        var keyTimes = [NSNumber]()
        
        var transformValues = [CATransform3D]()
        var transformKeyTimes = [NSNumber]()
        
        var firstStrokeTimestamp:TimeInterval?
        var lastStrokeTimestamp:TimeInterval!
        
        var firstTransformTimestamp:TimeInterval?
        var lastTransformTimestamp:TimeInterval!
        
        for (timestamp,transformation) in recordedInputs {
            let timeToCheck = CMTime(seconds: timestamp, preferredTimescale: DEFAULT_TIMESCALE)
            let pauseOffset = self.pauseOffset(timeToCheck)
            
            switch transformation {
            case let .move(point):
                path.move(to: point)
                lastPoint = point
                break
            case let .addLine(point):
                path.addLine(to: point)
                totalDistance += point.distance(lastPoint)

                lastPoint = point
                lastStrokeTimestamp = timestamp - pauseOffset
                break
            case .transform(_):
                lastTransformTimestamp = timestamp - pauseOffset
                break
            case .changeStrokeEnd(_):
                lastStrokeTimestamp = timestamp - pauseOffset
                break
            default:
                print("not supported transformation")
            }
        }
        
        var accumDistance:CGFloat = 0
        var currentPoint:CGPoint?
        
        for (timestamp,transformation) in recordedInputs {
            let timeToCheck = CMTime(seconds: timestamp, preferredTimescale: DEFAULT_TIMESCALE)
            let pauseOffset = self.pauseOffset(timeToCheck)
            
            let correctedTimestamp = timestamp - pauseOffset
            
            switch transformation {
            case let .move(point):
                currentPoint = point
                if firstStrokeTimestamp == nil {
                    firstStrokeTimestamp = correctedTimestamp
                }
                let totalDuration = lastStrokeTimestamp - firstStrokeTimestamp!
                let percentage = (correctedTimestamp - firstStrokeTimestamp!) / totalDuration
                keyTimes.append(NSNumber(value:percentage))
                break
            case let .addLine(point):
                values.append(CGFloat(accumDistance/totalDistance))
                if let lastPoint = currentPoint {
                    accumDistance += point.distance(lastPoint)
                }
                currentPoint = point
                if firstStrokeTimestamp == nil {
                    firstStrokeTimestamp = correctedTimestamp
                }
                let totalDuration = lastStrokeTimestamp - firstStrokeTimestamp!
                let percentage = (correctedTimestamp - firstStrokeTimestamp!) / totalDuration
                keyTimes.append(NSNumber(value:percentage))
                break
            case let .changeStrokeEnd(strokeEndPercentage):
                values.append(strokeEndPercentage)

                //Workaround
                if firstStrokeTimestamp == nil {
                    //This means that I don't have recordedInputs of the inking, so we use the timestamp of the changeStrokeEnd
                    firstStrokeTimestamp = correctedTimestamp
                }
                
                let totalDuration = lastStrokeTimestamp - firstStrokeTimestamp!
                let percentage = (correctedTimestamp - firstStrokeTimestamp!) / totalDuration
                keyTimes.append(NSNumber(value:percentage))
                break
            case let .transform(affineTransform):
                if firstTransformTimestamp == nil {
                    firstTransformTimestamp = correctedTimestamp
                }
                transformValues.append(CATransform3DMakeAffineTransform(affineTransform))
                let totalDuration = lastTransformTimestamp - firstTransformTimestamp!
                let percentage = (correctedTimestamp - firstTransformTimestamp!) / totalDuration
                transformKeyTimes.append(NSNumber(value:percentage))
                
                break
            default:
                print("not supported transformation")
            }
        }
        
//        values.removeLast()
        var strokeEndAnimation:CAKeyframeAnimation?

        if !values.isEmpty {
            
            let animationDuration = lastStrokeTimestamp - firstStrokeTimestamp!
            
            strokeEndAnimation = CAKeyframeAnimation()
            strokeEndAnimation!.beginTime = firstStrokeTimestamp! //AVCoreAnimationBeginTimeAtZero
            strokeEndAnimation!.calculationMode = kCAAnimationDiscrete
            strokeEndAnimation!.keyPath = "strokeEnd"
            strokeEndAnimation!.values = values
            strokeEndAnimation!.keyTimes = keyTimes
            strokeEndAnimation!.duration = animationDuration
            //        animation.isAdditive = true
            strokeEndAnimation!.fillMode = kCAFillModeForwards //to keep strokeEnd = 1 after completing the animation
            strokeEndAnimation!.isRemovedOnCompletion = false
            
            animations.append(strokeEndAnimation!)
        }
        
        var transformAnimation:CAKeyframeAnimation?
        if !transformValues.isEmpty {
            transformAnimation = CAKeyframeAnimation()
            transformAnimation!.beginTime = firstTransformTimestamp! //AVCoreAnimationBeginTimeAtZero
            transformAnimation!.calculationMode = kCAAnimationDiscrete
            transformAnimation!.keyPath = "transform"
            transformAnimation!.values = transformValues
            transformAnimation!.keyTimes = transformKeyTimes
            transformAnimation!.duration = lastTransformTimestamp - firstTransformTimestamp!
            //        animation.isAdditive = true
            transformAnimation!.fillMode = kCAFillModeForwards //to keep strokeEnd = 1 after completing the animation
            transformAnimation!.isRemovedOnCompletion = false
            
            animations.append(transformAnimation!)
        }
        
        var appearAnimation:CAKeyframeAnimation?
        
        var animationKeyTime = 0.0
        
        if appearedAt != nil {
            animationKeyTime = appearedAt!.doubleValue
        }

        let timeToCheck = CMTime(seconds: animationKeyTime, preferredTimescale: DEFAULT_TIMESCALE)
        let pauseOffset = self.pauseOffset(timeToCheck)
        
        //TODO check this for pause
        if let pauseIntersection = videoTrack?.video?.pausedTimeRanges?.first(where: { $0.containsTime(timeToCheck) }) {
            let endedTime = CMTime(seconds: endedRecordingAt - startedRecordingAt, preferredTimescale: DEFAULT_TIMESCALE)
            let durationPauseOffset = videoTrack?.video?.pausedTimeRanges?.reduce(0.0, { (result, pausedRange) -> TimeInterval in
                if  pausedRange.start < endedTime && pausedRange.end < endedTime {
                    return result + pausedRange.duration.seconds
                } else {
                    return result
                }
            }) ?? 0.0
            
            print("durationPauseOffset \(durationPauseOffset)")
            
            let animationDuration = endedRecordingAt - startedRecordingAt - durationPauseOffset
            appearAnimation = CAKeyframeAnimation()
            appearAnimation!.beginTime = AVCoreAnimationBeginTimeAtZero
            appearAnimation!.calculationMode = kCAAnimationDiscrete
            appearAnimation!.keyPath = "opacity"
            appearAnimation!.values = [0,1,1]
            appearAnimation!.keyTimes = [0,NSNumber(value:(pauseIntersection.start.seconds - pauseOffset)/animationDuration),1]
            appearAnimation!.duration = animationDuration
            appearAnimation!.fillMode = kCAFillModeForwards //to keep opacity = 1 after completing the animation
            appearAnimation!.isRemovedOnCompletion = false
        } else {
            let animationDuration = endedRecordingAt - startedRecordingAt //TODO: not considering pause - durationPauseOffset
            
            let appearAnimation = CAKeyframeAnimation()
            appearAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
            appearAnimation.calculationMode = kCAAnimationDiscrete
            appearAnimation.keyPath = "opacity"
            appearAnimation.values = [0,1,1]
            appearAnimation.keyTimes = [0,NSNumber(value:animationKeyTime/animationDuration),1]
            appearAnimation.duration = animationDuration
            appearAnimation.fillMode = kCAFillModeForwards //to keep opacity = 1 after completing the animation
            appearAnimation.isRemovedOnCompletion = false
        }
        
        //CAAnimationGroup do not work with AVSyncronizedLayer
//        let strokeAndMove = CAAnimationGroup()
//        strokeAndMove.animations = [strokeEndAnimation, transformAnimation]
//        strokeAndMove.beginTime = AVCoreAnimationBeginTimeAtZero
//        strokeAndMove.duration = endedRecordingAt - startedRecordingAt

//        print("-----> \(appearedAt)")
        
        return (appearAnimation,strokeEndAnimation,transformAnimation)
    }
    
    var isSelected:Bool {
        get {
            return self.selected
        }
        set(newValue) {
            self.selected = newValue
        }
    }
    
    func pauseOffset(_ timeToCheck:CMTime) -> TimeInterval {
        return videoTrack?.video?.pausedTimeRanges?.reduce(0.0, { (result, pausedRange) -> TimeInterval in
            if pausedRange.start < timeToCheck && pausedRange.end < timeToCheck {
                return result + pausedRange.duration.seconds
            } else {
                return result
            }
        }) ?? 0.0
    }
}
