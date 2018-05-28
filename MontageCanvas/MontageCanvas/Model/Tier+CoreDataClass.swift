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

    var recordedPathInputs = [(TimeInterval,Transformation)]()
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
    
    // MARK: Animation
    
//    func buildAnimations2() -> (appearAnimation:CAKeyframeAnimation?,strokeEndAnimation:CAKeyframeAnimation?,transformationAnimation:CAKeyframeAnimation?) {
//
//        var animations = [CAKeyframeAnimation]()
//
//        let path = CGMutablePath()
//
//        var totalDistance:CGFloat = 0
//        var lastPoint = CGPoint.zero
//        var values = [CGFloat]()
//        var keyTimes = [NSNumber]()
//
//        var transformValues = [CATransform3D]()
//        var transformKeyTimes = [NSNumber]()
//
//        var firstStrokeTimestamp:TimeInterval?
//        var lastStrokeTimestamp:TimeInterval!
//
//        var firstTransformTimestamp:TimeInterval?
//        var lastTransformTimestamp:TimeInterval!
//
//        for (timestamp,transformation) in recordedInputs {
//            let timeToCheck = CMTime(seconds: timestamp, preferredTimescale: DEFAULT_TIMESCALE)
//            let pauseOffset = self.pauseOffset(timeToCheck)
//
//            switch transformation {
//            case let .move(point):
//                path.move(to: point)
//                lastPoint = point
//                break
//            case let .addLine(point):
//                path.addLine(to: point)
//                totalDistance += point.distance(lastPoint)
//
//                lastPoint = point
//                lastStrokeTimestamp = timestamp - pauseOffset
//                break
//            case .transform(_):
//                lastTransformTimestamp = timestamp - pauseOffset
//                break
//            case .changeStrokeEnd(_):
//                lastStrokeTimestamp = timestamp - pauseOffset
//                break
//            default:
//                print("not supported transformation")
//            }
//        }
//
//        var accumDistance:CGFloat = 0
//        var currentPoint:CGPoint?
//
//        for (timestamp,transformation) in recordedInputs {
//            let timeToCheck = CMTime(seconds: timestamp, preferredTimescale: DEFAULT_TIMESCALE)
//            let pauseOffset = self.pauseOffset(timeToCheck)
//
//            let correctedTimestamp = timestamp - pauseOffset
//
//            switch transformation {
//            case let .move(point):
//                currentPoint = point
//                if firstStrokeTimestamp == nil {
//                    firstStrokeTimestamp = correctedTimestamp
//                }
//                let totalDuration = lastStrokeTimestamp - firstStrokeTimestamp!
//                let percentage = (correctedTimestamp - firstStrokeTimestamp!) / totalDuration
//                keyTimes.append(NSNumber(value:percentage))
//                break
//            case let .addLine(point):
//                values.append(CGFloat(accumDistance/totalDistance))
//                if let lastPoint = currentPoint {
//                    accumDistance += point.distance(lastPoint)
//                }
//                currentPoint = point
//                if firstStrokeTimestamp == nil {
//                    firstStrokeTimestamp = correctedTimestamp
//                }
//                let totalDuration = lastStrokeTimestamp - firstStrokeTimestamp!
//                let percentage = (correctedTimestamp - firstStrokeTimestamp!) / totalDuration
//                keyTimes.append(NSNumber(value:percentage))
//                break
//            case let .changeStrokeEnd(strokeEndPercentage):
//                values.append(strokeEndPercentage)
//
//                //Workaround
//                if firstStrokeTimestamp == nil {
//                    //This means that I don't have recordedInputs of the inking, so we use the timestamp of the changeStrokeEnd
//                    firstStrokeTimestamp = correctedTimestamp
//                }
//
//                let totalDuration = lastStrokeTimestamp - firstStrokeTimestamp!
//                let percentage = (correctedTimestamp - firstStrokeTimestamp!) / totalDuration
//                keyTimes.append(NSNumber(value:percentage))
//                break
//            case let .transform(affineTransform):
//                if firstTransformTimestamp == nil {
//                    firstTransformTimestamp = correctedTimestamp
//                }
//                transformValues.append(CATransform3DMakeAffineTransform(affineTransform))
//                let totalDuration = lastTransformTimestamp - firstTransformTimestamp!
//                let percentage = (correctedTimestamp - firstTransformTimestamp!) / totalDuration
//                transformKeyTimes.append(NSNumber(value:percentage))
//
//                break
//            default:
//                print("not supported transformation")
//            }
//        }
//
////        values.removeLast()
//        var strokeEndAnimation:CAKeyframeAnimation?
//
//        if !values.isEmpty {
//
//            let animationDuration = lastStrokeTimestamp - firstStrokeTimestamp!
//
//            strokeEndAnimation = CAKeyframeAnimation()
//            strokeEndAnimation!.beginTime = firstStrokeTimestamp! //AVCoreAnimationBeginTimeAtZero
//            strokeEndAnimation!.calculationMode = kCAAnimationDiscrete
//            strokeEndAnimation!.keyPath = "strokeEnd"
//            strokeEndAnimation!.values = values
//            strokeEndAnimation!.keyTimes = keyTimes
//            strokeEndAnimation!.duration = animationDuration
//            //        animation.isAdditive = true
//            strokeEndAnimation!.fillMode = kCAFillModeForwards //to keep strokeEnd = 1 after completing the animation
//            strokeEndAnimation!.isRemovedOnCompletion = false
//
//            animations.append(strokeEndAnimation!)
//        }
//
//        var transformAnimation:CAKeyframeAnimation?
//        if !transformValues.isEmpty {
//            transformAnimation = CAKeyframeAnimation()
//            transformAnimation!.beginTime = firstTransformTimestamp! //AVCoreAnimationBeginTimeAtZero
//            transformAnimation!.calculationMode = kCAAnimationDiscrete
//            transformAnimation!.keyPath = "transform"
//            transformAnimation!.values = transformValues
//            transformAnimation!.keyTimes = transformKeyTimes
//            transformAnimation!.duration = lastTransformTimestamp - firstTransformTimestamp!
//            //        animation.isAdditive = true
//            transformAnimation!.fillMode = kCAFillModeForwards //to keep strokeEnd = 1 after completing the animation
//            transformAnimation!.isRemovedOnCompletion = false
//
//            animations.append(transformAnimation!)
//        }
//
//        var appearAnimation:CAKeyframeAnimation?
//
//        var animationKeyTime = 0.0
//
//        if appearedAt != nil {
//            animationKeyTime = appearedAt!.doubleValue
//        }
//
//        let timeToCheck = CMTime(seconds: animationKeyTime, preferredTimescale: DEFAULT_TIMESCALE)
//        let pauseOffset = self.pauseOffset(timeToCheck)
//
//        //TODO check this for pause
//        if let pauseIntersection = videoTrack?.video?.pausedTimeRanges?.first(where: { $0.containsTime(timeToCheck) }) {
//            let endedTime = CMTime(seconds: endedRecordingAt - startedRecordingAt, preferredTimescale: DEFAULT_TIMESCALE)
//            let durationPauseOffset = videoTrack?.video?.pausedTimeRanges?.reduce(0.0, { (result, pausedRange) -> TimeInterval in
//                if  pausedRange.start < endedTime && pausedRange.end < endedTime {
//                    return result + pausedRange.duration.seconds
//                } else {
//                    return result
//                }
//            }) ?? 0.0
//
//            print("durationPauseOffset \(durationPauseOffset)")
//
//            let animationDuration = endedRecordingAt - startedRecordingAt - durationPauseOffset
//            appearAnimation = CAKeyframeAnimation()
//            appearAnimation!.beginTime = AVCoreAnimationBeginTimeAtZero
//            appearAnimation!.calculationMode = kCAAnimationDiscrete
//            appearAnimation!.keyPath = "opacity"
//            appearAnimation!.values = [0,1,1]
//            appearAnimation!.keyTimes = [0,NSNumber(value:(pauseIntersection.start.seconds - pauseOffset)/animationDuration),1]
//            appearAnimation!.duration = animationDuration
//            appearAnimation!.fillMode = kCAFillModeForwards //to keep opacity = 1 after completing the animation
//            appearAnimation!.isRemovedOnCompletion = false
//        } else {
//            let animationDuration = endedRecordingAt - startedRecordingAt //TODO: not considering pause - durationPauseOffset
//
//            let appearAnimation = CAKeyframeAnimation()
//            appearAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
//            appearAnimation.calculationMode = kCAAnimationDiscrete
//            appearAnimation.keyPath = "opacity"
//            appearAnimation.values = [0,1,1]
//            appearAnimation.keyTimes = [0,NSNumber(value:animationKeyTime/animationDuration),1]
//            appearAnimation.duration = animationDuration
//            appearAnimation.fillMode = kCAFillModeForwards //to keep opacity = 1 after completing the animation
//            appearAnimation.isRemovedOnCompletion = false
//        }
//
//        //CAAnimationGroup do not work with AVSyncronizedLayer
////        let strokeAndMove = CAAnimationGroup()
////        strokeAndMove.animations = [strokeEndAnimation, transformAnimation]
////        strokeAndMove.beginTime = AVCoreAnimationBeginTimeAtZero
////        strokeAndMove.duration = endedRecordingAt - startedRecordingAt
//
////        print("-----> \(appearedAt)")
//
//        return (appearAnimation,strokeEndAnimation,transformAnimation)
//    }
    
    func rebuildAnimations(forLayer shapeLayer:CAShapeLayer, totalRecordingTime:TimeInterval) {
        let (appearAnimation,inkAnimation,strokeEndAnimation,transformationAnimation) = buildAnimations(totalRecordingTime:totalRecordingTime)

        shapeLayer.removeAnimation(forKey: "appearAnimation")
        if let appearAnimation = appearAnimation {
            shapeLayer.add(appearAnimation, forKey: "appearAnimation")
        }
        
        shapeLayer.removeAnimation(forKey: "inkAnimation")
        if let inkAnimation = inkAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shapeLayer.strokeEnd = 0
            CATransaction.commit()
            shapeLayer.add(inkAnimation, forKey: "inkAnimation")
        }
        
        shapeLayer.removeAnimation(forKey: "strokeEndAnimation")
        if let strokeEndAnimation = strokeEndAnimation {
            shapeLayer.add(strokeEndAnimation, forKey: "strokeEndAnimation")
        }
        
        shapeLayer.removeAnimation(forKey: "transformationAnimation")
        if let transformationAnimation = transformationAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shapeLayer.transform = CATransform3DIdentity
            CATransaction.commit()
            shapeLayer.add(transformationAnimation, forKey: "transformationAnimation")
        }
    }
    
    func buildAnimations(totalRecordingTime:TimeInterval) -> (appearAnimation:CAKeyframeAnimation?,inkAnimation:CAKeyframeAnimation?,strokeEndAnimation:CAKeyframeAnimation?,transformationAnimation:CAKeyframeAnimation?) {
        
        var inkAnimation:CAKeyframeAnimation?
        
        if let totalDistance = sketch?.pathLength,
            let firstStrokeTimestamp = recordedPathInputs.first?.0,
            let lastStrokeTimestamp = recordedPathInputs.last?.0 {
            
            var accumDistance:CGFloat = 0
            var currentPoint:CGPoint?
            
            let animationDuration = lastStrokeTimestamp - firstStrokeTimestamp
            
            var inkValues = [CGFloat]()
            var keyTimes = [NSNumber]()
            
            for (timestamp, pathTransformation) in recordedPathInputs {
                switch pathTransformation {
                case let .move(point):
                    currentPoint = point
                    let percentage = (timestamp - firstStrokeTimestamp) / animationDuration
                    keyTimes.append(NSNumber(value:percentage))
                case let .addLine(point):
                    inkValues.append(CGFloat(accumDistance/totalDistance))
                    if let lastPoint = currentPoint {
                        accumDistance += point.distance(lastPoint)
                    }
                    currentPoint = point
                    let percentage = (timestamp - firstStrokeTimestamp) / animationDuration
                    keyTimes.append(NSNumber(value:percentage))
                default:
                    print("does not apply to recordedPathInputs")
                }
            }
            
            if !inkValues.isEmpty {
                let newStrokeEndAnimation = CAKeyframeAnimation()
                newStrokeEndAnimation.beginTime = firstStrokeTimestamp //AVCoreAnimationBeginTimeAtZero
                newStrokeEndAnimation.calculationMode = kCAAnimationDiscrete
                newStrokeEndAnimation.keyPath = "strokeEnd"
                newStrokeEndAnimation.values = inkValues
                newStrokeEndAnimation.keyTimes = keyTimes
                newStrokeEndAnimation.duration = animationDuration
                newStrokeEndAnimation.fillMode = kCAFillModeForwards //to keep strokeEnd = 1 after completing the animation
                newStrokeEndAnimation.isRemovedOnCompletion = false
                
                inkAnimation = newStrokeEndAnimation
            }
        }
        
        var strokeEndAnimation:CAKeyframeAnimation?
        
        if let firstStrokeTimestamp = recordedStrokeEndInputs.first?.0,
            let lastStrokeTimestamp = recordedStrokeEndInputs.last?.0 {
            
            let animationDuration = lastStrokeTimestamp - firstStrokeTimestamp
            
            var strokeEndValues = [CGFloat]()
            var keyTimes = [NSNumber]()
            
            for (timestamp, strokeChangedTransformation) in recordedStrokeEndInputs {
                switch strokeChangedTransformation {
                case let .changeStrokeEnd(strokeEndPercentage):
                    strokeEndValues.append(strokeEndPercentage)
                    
                    let percentage = (timestamp - firstStrokeTimestamp) / animationDuration
                    keyTimes.append(NSNumber(value:percentage))
                default:
                    print("does not apply to recordedStrokeEndInputs")
                }
            }
            
            if !strokeEndValues.isEmpty {
                let newStrokeEndAnimation = CAKeyframeAnimation()
                newStrokeEndAnimation.beginTime = firstStrokeTimestamp //AVCoreAnimationBeginTimeAtZero
                newStrokeEndAnimation.calculationMode = kCAAnimationDiscrete
                newStrokeEndAnimation.keyPath = "strokeEnd"
                newStrokeEndAnimation.values = strokeEndValues
                newStrokeEndAnimation.keyTimes = keyTimes
                newStrokeEndAnimation.duration = animationDuration
                newStrokeEndAnimation.fillMode = kCAFillModeForwards //to keep strokeEnd = 1 after completing the animation
                newStrokeEndAnimation.isRemovedOnCompletion = false
                
                strokeEndAnimation = newStrokeEndAnimation
            }
        }
        
        var transformationAnimation:CAKeyframeAnimation?
        
        if let firstTransformTimestamp = recordedTransformInputs.first?.0,
            let lastTransformTimestamp = recordedTransformInputs.last?.0 {
            
            let animationDuration = lastTransformTimestamp - firstTransformTimestamp
            
            var transformValues = [CATransform3D]()
            var transformKeyTimes = [NSNumber]()
            
            for (timestamp, transformTransformation) in recordedTransformInputs {
                switch transformTransformation {
                case let .transform(affineTransform):
                    transformValues.append(CATransform3DMakeAffineTransform(affineTransform))
                    let percentage = (timestamp - firstTransformTimestamp) / animationDuration
                    transformKeyTimes.append(NSNumber(value:percentage))
                default:
                    print("does not apply to recordedTransformInputs")
                }
            }
            
            if !transformValues.isEmpty {
                let newTransformAnimation = CAKeyframeAnimation()
                newTransformAnimation.beginTime = firstTransformTimestamp //AVCoreAnimationBeginTimeAtZero
                newTransformAnimation.calculationMode = kCAAnimationDiscrete
                newTransformAnimation.keyPath = "transform"
                newTransformAnimation.values = transformValues
                newTransformAnimation.keyTimes = transformKeyTimes
                newTransformAnimation.duration = animationDuration
                newTransformAnimation.fillMode = kCAFillModeForwards //to keep strokeEnd = 1 after completing the animation
                newTransformAnimation.isRemovedOnCompletion = false
                
                transformationAnimation = newTransformAnimation
            }
        }
        
        var toggleAnimation:CAKeyframeAnimation?
        
        if appearedAtTimes == nil {
            appearedAtTimes = [0]
        }
        if dissappearAtTimes == nil {
            dissappearAtTimes = [NSNumber(value:0),NSNumber(value:totalRecordingTime)]
        }
        
        if let firstAppearanceTime = appearedAtTimes?.first?.doubleValue,
            let lastDisappearanceTime = dissappearAtTimes?.last?.doubleValue {
            
            if firstAppearanceTime == 0, let firstDisappearanceTime = dissappearAtTimes?.first?.doubleValue, firstDisappearanceTime == 0 {
                dissappearAtTimes?.removeFirst()
            }
            
            let animationDuration = totalRecordingTime

            var calculatedValues = [(Double,Int)]()
            
            for eachAppearanceTime in (appearedAtTimes!.map { $0.doubleValue }) {
                let percentage = eachAppearanceTime / animationDuration
                calculatedValues.append((percentage,1))
            }

            for eachDissappearanceTime in (dissappearAtTimes!.map { $0.doubleValue }) {
                let percentage = eachDissappearanceTime / animationDuration
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
            toggleAnimation!.fillMode = kCAFillModeForwards //to keep opacity = 1 after completing the animation
            toggleAnimation!.isRemovedOnCompletion = false
        }
        //CAAnimationGroup do not work with AVSyncronizedLayer
        //        let strokeAndMove = CAAnimationGroup()
        //        strokeAndMove.animations = [strokeEndAnimation, transformAnimation]
        //        strokeAndMove.beginTime = AVCoreAnimationBeginTimeAtZero
        //        strokeAndMove.duration = endedRecordingAt - startedRecordingAt
        
        //        print("-----> \(appearedAt)")
        return (toggleAnimation,inkAnimation,strokeEndAnimation,transformationAnimation)
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
