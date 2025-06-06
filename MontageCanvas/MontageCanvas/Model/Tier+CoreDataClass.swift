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
    case transform(type:TierModification,affineTransform:CGAffineTransform)
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
//    var recordedPathInputs = [(TimeInterval,Transformation)]()
//    var recordedStrokeStartInputs = [(TimeInterval,Transformation)]()
//    var recordedStrokeEndInputs = [(TimeInterval,Transformation)]()
//    var recordedTransformInputs = [(TimeInterval,Transformation)]()
    var recordedPathInputs:[UserInputPath] {
        get {
            guard let pathInputs = savedPathInputs?.array as? [UserInputPath] else {
                return []
            }
            return pathInputs
        }
    }
    var recordedStrokeStartInputs:[UserInputStroke] {
        get {
            guard let strokeInputs = savedStrokeStartInputs?.array as? [UserInputStroke] else {
                return []
            }
            return strokeInputs
        }
    }
    var recordedStrokeEndInputs:[UserInputStroke] {
        get {
            guard let strokeInputs = savedStrokeEndInputs?.array as? [UserInputStroke] else {
                return []
            }
            return strokeInputs
        }
    }
    var recordedTranslateTransformInputs: [UserInputTransform] {
        get {
            guard let translateInputs = savedTranslateTransformInputs?.array as? [UserInputTransform] else {
                return []
            }
            return translateInputs
        }
    }
    var recordedRotateTransformInputs: [UserInputTransform] {
        get {
            guard let rotateInputs = savedRotateTransformInputs?.array as? [UserInputTransform] else {
                return []
            }
            return rotateInputs
        }
    }
    var recordedScaleTransformInputs: [UserInputTransform] {
        get {
            guard let scaleInputs = savedScaleTransformInputs?.array as? [UserInputTransform] else {
                return []
            }
            return scaleInputs
        }
    }
    
    var recordedTransformInputs: [UserInputTransform] {
        return recordedTranslateTransformInputs + recordedRotateTransformInputs + recordedScaleTransformInputs
    }
    
//    aSelectedSketch.recordedTransformInputs = aSelectedSketch.recordedTransformInputs.filter {
//    let (timestamp,_) = $0
//    return timestamp < currentTime
//    }
    func deleteTransformationInputs(withTimestampSmallerThan currentTime:TimeInterval) {
        let predicate = NSPredicate(format: "timestamp < %lf", currentTime)

        mutableOrderedSetValue(forKey: "savedTranslateTransformInputs").filter(using: predicate)
        mutableOrderedSetValue(forKey: "savedScaleTransformInputs").filter(using: predicate)
        mutableOrderedSetValue(forKey: "savedRotateTransformInputs").filter(using: predicate)
    }
    var hasTransformationInputs:Bool {
        guard let translations = savedTranslateTransformInputs, translations.count > 0 else {
            return true
        }
        guard let scales = savedScaleTransformInputs, scales.count > 0 else {
            return true
        }
        guard let rotations = savedRotateTransformInputs, rotations.count > 0 else {
            return true
        }
        return false
    }

    func clone() -> Tier {
        assert(Thread.isMainThread)

        let clonedTier = Tier(context: managedObjectContext!)

        clonedTier.sketch = sketch?.clone()

        clonedTier.zIndex = zIndex
        clonedTier.end = end
        clonedTier.lineWidth = lineWidth
        clonedTier.rotationValue = rotationValue
        clonedTier.start = start
        clonedTier.hasDrawnPath = hasDrawnPath
        clonedTier.selected = selected
//        clonedTier.createdAt = createdAt
        clonedTier.fillColor = fillColor
        if let appearAtTimes = innerAppearAtTimes {
            clonedTier.innerAppearAtTimes = [NSNumber](appearAtTimes)
        }
        if let disappearAtTimes = innerDisappearAtTimes {
            clonedTier.innerDisappearAtTimes = [NSNumber](disappearAtTimes)
        }
        clonedTier.scalingValue = scalingValue
        clonedTier.strokeColor = strokeColor
        clonedTier.translationValue = translationValue
        
        clonedTier.savedPathInputs = NSOrderedSet(array:recordedPathInputs.map { $0.clone() })
        clonedTier.savedStrokeStartInputs = NSOrderedSet(array:recordedStrokeStartInputs.map { $0.clone() })
        clonedTier.savedStrokeEndInputs = NSOrderedSet(array:recordedStrokeEndInputs.map { $0.clone() })
        clonedTier.savedTranslateTransformInputs = NSOrderedSet(array:recordedTranslateTransformInputs.map { $0.clone() })
        clonedTier.savedScaleTransformInputs = NSOrderedSet(array:recordedScaleTransformInputs.map { $0.clone() })
        clonedTier.savedRotateTransformInputs = NSOrderedSet(array:recordedRotateTransformInputs.map { $0.clone() })
        
        return clonedTier
    }
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
        
        assert(Thread.isMainThread)

        sketch = Sketch(context: managedObjectContext!)
        createdAt = Date()
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
    
    func shouldAppearAt(time newAppearedAt:TimeInterval) {
        if let firstTimeStamp = recordedPathInputs.first?.timestamp ?? appearAtTimes.first {
            let offset = newAppearedAt - firstTimeStamp
            
            for userInputOrderedSet in [savedPathInputs!, savedStrokeStartInputs!, savedStrokeEndInputs!, savedTranslateTransformInputs!, savedScaleTransformInputs!, savedRotateTransformInputs!] {
                for userInput in userInputOrderedSet.array as! [UserInput] {
                    userInput.timestamp += offset
                }
            }
        }
        
        appearAtTimes = [newAppearedAt]
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
//            recordedTransformInputs.append((timestamp,.transform(type:.moved,affineTransform: currentTransformation)))
            assert(Thread.isMainThread)

            let newUserInputTransform = UserInputTransform(context: managedObjectContext!)
            newUserInputTransform.timestamp = timestamp
            newUserInputTransform.value = AffineTransformWrapper(currentTransformation)
            addToSavedTranslateTransformInputs(newUserInputTransform)
        }
    }
    
    func rotationDelta(_ delta:CGFloat, timestamp:TimeInterval?) {
        let rotation = self.rotation ?? CGFloat(0)
        self.rotation = rotation + delta
        
        if let timestamp = timestamp {
//            recordedTransformInputs.append((timestamp,.transform(type:.rotated,affineTransform: currentTransformation)))
            let newUserInputTransform = UserInputTransform(context: managedObjectContext!)
            newUserInputTransform.timestamp = timestamp
            newUserInputTransform.value = AffineTransformWrapper(currentTransformation)
            addToSavedRotateTransformInputs(newUserInputTransform)
        }
    }
    
    func scalingDelta(_ delta:CGPoint, timestamp:TimeInterval?) {
        let scaling = self.scaling ?? CGPoint(x:1,y:1)
        self.scaling = CGPoint(x: scaling.x * delta.x,y: scaling.y * delta.y)
        
        if let timestamp = timestamp {
//            recordedTransformInputs.append((timestamp,.transform(type:.scaled,affineTransform: currentTransformation)))
            assert(Thread.isMainThread)

            let newUserInputTransform = UserInputTransform(context: managedObjectContext!)
            newUserInputTransform.timestamp = timestamp
            newUserInputTransform.value = AffineTransformWrapper(currentTransformation)
            addToSavedScaleTransformInputs(newUserInputTransform)
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
//            print("saving addFirstPoint with normalized timestamp \(timestamp)")
//            recordedPathInputs.append((timestamp, .move(point: touchLocation)))
            
            assert(Thread.isMainThread)
            
            let newUserInputPath = UserInputPath(context: managedObjectContext!)
            newUserInputPath.timestamp = timestamp
            newUserInputPath.value = PointWrapper(touchLocation)
            newUserInputPath.action = MutablePathAction.move.rawValue
            addToSavedPathInputs(newUserInputPath)
        }
    }
    
    func addPoint(_ touchLocation:CGPoint,timestamp:TimeInterval?, shouldRecord:Bool) {
        sketch?.addLine(to:touchLocation)
        
        mutableShapeLayerPath.addLine(to: touchLocation)
        shapeLayer.didChangeValue(for: \CAShapeLayer.path)
        
        if shouldRecord, let timestamp = timestamp {
//            print("saving addPoint with normalized timestamp \(timestamp)")
//            recordedPathInputs.append((timestamp, .addLine(point: touchLocation)))
            assert(Thread.isMainThread)

            let newUserInputPath = UserInputPath(context: managedObjectContext!)
            newUserInputPath.timestamp = timestamp
            newUserInputPath.value = PointWrapper(touchLocation)
            newUserInputPath.action = MutablePathAction.addLine.rawValue
            addToSavedPathInputs(newUserInputPath)
        }
    }
    
    func strokeEndChanged(_ percentage:Float, timestamp:TimeInterval?) {
        if let timestamp = timestamp {
//            recordedStrokeEndInputs.append((timestamp, .changeStrokeEnd(strokeEndPercentage: percentage)))
            assert(Thread.isMainThread)

            let newUserInputStroke = UserInputStroke(context: managedObjectContext!)
            newUserInputStroke.timestamp = timestamp
            newUserInputStroke.value = percentage
            addToSavedStrokeEndInputs(newUserInputStroke)
        }
    }
    
    func strokeStartChanged(_ percentage:Float, timestamp:TimeInterval?) {
        if let timestamp = timestamp {
//            recordedStrokeStartInputs.append((timestamp, .changeStrokeStart(strokeStartPercentage: percentage)))
            assert(Thread.isMainThread)

            let newUserInputStroke = UserInputStroke(context: managedObjectContext!)
            newUserInputStroke.timestamp = timestamp
            newUserInputStroke.value = percentage
            addToSavedStrokeStartInputs(newUserInputStroke)
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
        print("buildAnimations >> START")

        var inkAnimation:CAKeyframeAnimation?
        
        if let totalDistance = sketch?.pathLength, !recordedPathInputs.isEmpty {
            
            var accumDistance:CGFloat = 0
            var currentPoint:CGPoint?
            
            let animationDuration = totalRecordingTime
            
            var inkValues = [CGFloat(0)]
            var keyTimes = [NSNumber(value:0)]
            
            for userInputPath in recordedPathInputs {
                let point = userInputPath.value!.cgPoint
                
                switch userInputPath.action {
                case MutablePathAction.move.rawValue:
                    currentPoint = point
                    let percentage = userInputPath.timestamp / animationDuration
                    keyTimes.append(NSNumber(value:percentage))
                case MutablePathAction.addLine.rawValue:
                    inkValues.append(CGFloat(accumDistance/totalDistance))
                    if let lastPoint = currentPoint {
                        accumDistance += point.distance(lastPoint)
                    }
                    currentPoint = point
                    let percentage = userInputPath.timestamp / animationDuration
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
                
//                print("buildAnimations >> inkAnimation: \(newStrokeEndAnimation.debugDescription)")
            }
        }
        
        var strokeEndAnimation:CAKeyframeAnimation?
        
        if !recordedStrokeEndInputs.isEmpty {
            
            let animationDuration = totalRecordingTime
            
            var strokeEndValues = [Float(1)]
            var keyTimes = [NSNumber(value:0)]

            for userInputStroke in recordedStrokeEndInputs {
                let strokeEndPercentage = userInputStroke.value
                strokeEndValues.append(strokeEndPercentage)
                
                let percentage = userInputStroke.timestamp / animationDuration
                keyTimes.append(NSNumber(value:percentage))
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
                
//                print("buildAnimations >> strokeEndAnimation: \(newStrokeEndAnimation.debugDescription)")
            }
        }
        
        var strokeStartAnimation:CAKeyframeAnimation?
        
        if !recordedStrokeStartInputs.isEmpty {
            
            let animationDuration = totalRecordingTime
            
            var strokeStartValues = [Float(0)]
            var keyTimes = [NSNumber(value:0)]
            
            for userInputStroke in recordedStrokeStartInputs {
                let strokeStartPercentage = userInputStroke.value

                strokeStartValues.append(strokeStartPercentage)
                
                let percentage = userInputStroke.timestamp / animationDuration
                keyTimes.append(NSNumber(value:percentage))
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
                
//                print("buildAnimations >> strokeStartnimation: \(newStrokeStartAnimation.debugDescription)")
            }
        }
        
        var transformationAnimation:CAKeyframeAnimation?
        
        if !recordedTransformInputs.isEmpty {
            
            let animationDuration = totalRecordingTime
            
            var transformValues = [CATransform3DIdentity]
            var transformKeyTimes = [NSNumber(value:0)]
            
            for userInputTransform in recordedTransformInputs {
                let affineTransform = userInputTransform.value!.cgAffineTransform
                transformValues.append(CATransform3DMakeAffineTransform(affineTransform))
                let percentage = userInputTransform.timestamp / animationDuration
                transformKeyTimes.append(NSNumber(value:percentage))
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
                
//                print("buildAnimations >> transformationAnimation: \(transformationAnimation.debugDescription)")
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
        
//        print("buildAnimations >> toggleAnimation: \(toggleAnimation!.debugDescription)")
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
