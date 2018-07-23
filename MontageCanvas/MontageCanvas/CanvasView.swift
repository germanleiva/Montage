//
//  CanvasView.swift
//  Montage
//
//  Created by Germán Leiva on 08/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import AVFoundation
import CoreData

protocol CanvasViewDelegate:AnyObject {
    func canvasLongPressed(_ canvas:CanvasView,touchLocation:CGPoint)
//    func canvasTouchBegan(_ canvas:CanvasView)
    func canvasTierAdded(_ canvas:CanvasView,tier:Tier)
    func canvasTierModified(_ canvas:CanvasView,tier:Tier, type:TierModification)
    func canvasTierRemoved(_ canvas:CanvasView,tier:Tier)

    func playerItemOffset() -> TimeInterval
//    func normalizeTime1970(time:TimeInterval) -> TimeInterval?
    var currentTime:TimeInterval { get }
    
    var shouldRecordInking:Bool { get }
}

class CanvasView: UIView, UIGestureRecognizerDelegate {
    let secondsBeforeConsiderNewSketh:TimeInterval = 0.7
    var fastDrawingTimer:Timer?
    var stylusTouchBeganLocation:CGPoint?
    weak var associatedSyncLayer:AVSynchronizedLayer?
    
    weak var delegate:CanvasViewDelegate?
    
    var selectedStrokeColor = Globals.initialStrokeColor
    var selectedFillColor = Globals.initialFillColor
    var selectedLineWidth = Globals.initialLineWidth
    
    let coreDataContext = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
    var videoTrack:VideoTrack!
    
    var selectedSketches:[Tier] {
        return (videoTrack.tiers!.array as! [Tier]).filter {$0.isSelected}
    }
    var lastTouchTimestamp:TimeInterval?
    
    var currentlyDrawnSketch:Tier?
    var canvasLayer = CALayer()
    
    lazy var rotationRecognizer:UIRotationGestureRecognizer = {
        let rotationRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(CanvasView.rotateDetected))
        rotationRecognizer.delegate = self
        return rotationRecognizer
    }()
    
    lazy var pinchRecognizer:UIPinchGestureRecognizer = {
        let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(CanvasView.pinchDetected))
        pinchRecognizer.delegate = self
        return pinchRecognizer
    }()
    
    lazy var panRecognizer:UIPanGestureRecognizer = {
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(CanvasView.panDetected))
        panRecognizer.delegate = self
//        panRecognizer.maximumNumberOfTouches = 1
//        panRecognizer.minimumNumberOfTouches = 1
        panRecognizer.allowedTouchTypes = [NSNumber(value:UITouchType.direct.rawValue)]
        return panRecognizer
    }()
    
//    lazy var swipeRecognizer:UISwipeGestureRecognizer = {
//        let swipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(CanvasView.swipeDetected))
//        swipeRecognizer.delegate = self
//        swipeRecognizer.numberOfTouchesRequired = 2
//        swipeRecognizer.allowedTouchTypes = [NSNumber(value:UITouchType.direct.rawValue)]
//        return swipeRecognizer
//    }()
    
    lazy var longPressRecognizer:UILongPressGestureRecognizer = {
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(CanvasView.longPressDetected))
        longPressRecognizer.delegate = self
        longPressRecognizer.allowedTouchTypes = [NSNumber(value:UITouchType.direct.rawValue)]
        return longPressRecognizer
    }()
    
    /*
     // Only override draw() if you perform custom drawing.
     // An empty implementation adversely affects performance during animation.
     //    override func draw(_ rect: CGRect) {
     //        // Drawing code
     //        guard let context = UIGraphicsGetCurrentContext() else {
     //            return
     //        }
     //        for path in objects {
     //            context.addPath(path)
     //            context.setStrokeColor(UIColor.white.cgColor)
     //            context.strokePath()
     //        }
     //    }
     */
    deinit {
        currentlyDrawnSketch = nil
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialize()
    }
    
    func initialize() {
        backgroundColor = UIColor.clear
        
        layer.borderWidth = 1
        layer.borderColor = UIColor.gray.cgColor
        
        layer.addSublayer(canvasLayer)

        addGestureRecognizer(rotationRecognizer)
        addGestureRecognizer(pinchRecognizer)
        addGestureRecognizer(panRecognizer)
//        addGestureRecognizer(swipeRecognizer)
        addGestureRecognizer(longPressRecognizer)
    }
    
    lazy var paletteView:Palette = {
        let paletteView = Palette()
        paletteView.delegate = self
        paletteView.setup()
        //        self.view.addSubview(paletteView)
        self.paletteView = paletteView
        //        let paletteHeight = paletteView.paletteHeight()
        //        paletteView.frame = CGRect(x: 0, y: self.view.frame.height - paletteHeight, width: self.view.frame.width, height: paletteHeight)
        return paletteView
    }()
    
    func createSketchLayer() -> Tier {
        let newTier = Tier(context: coreDataContext)
        newTier.createdAt = Date()
        
        videoTrack.addToTiers(newTier)
        newTier.zIndex = Int32(videoTrack.tiers?.count ?? 0) //Int32(videoTrack.tiers!.index(of: newTier))
        
        return newTier
    }
    
    func addNewSketchLayer() {
        currentlyDrawnSketch = createSketchLayer()
        currentlyDrawnSketch?.strokeColor = selectedStrokeColor
        currentlyDrawnSketch?.fillColor = selectedFillColor
        currentlyDrawnSketch?.lineWidth = selectedLineWidth
        canvasLayer.addSublayer(currentlyDrawnSketch!.shapeLayer)
    }
    
    func removeAllSketches() {
        currentlyDrawnSketch = nil
        canvasLayer.sublayers = nil
    }
    
//    override class var layerClass: AnyClass {
//        get {
//            return AVCaptureVideoPreviewLayer.self
//        }
//    }
    
//    var videoLayer:AVCaptureVideoPreviewLayer {
//        return self.layer as! AVCaptureVideoPreviewLayer
//    }
    
//    var session:AVCaptureSession? {
//        get {
//            return videoLayer.session
//        }
//        set(aSession) {
//            videoLayer.session = aSession
//            videoLayer.videoGravity = AVLayerVideoGravity.resizeAspect
//
//            videoLayer.connection?.videoOrientation = AVCaptureVideoOrientation.landscapeRight
//        }
//    }
    
//    func captureDevicePointForPoint(point:CGPoint) -> CGPoint {
//        return videoLayer.captureDevicePointConverted(fromLayerPoint: point)
//    }
    
    func normalizeTime(_ aTime: TimeInterval? = nil) -> TimeInterval? {
//        return delegate?.normalizeTime1970(time: aTime == nil ? Date().timeIntervalSince1970 : aTime!)
        return delegate?.currentTime
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
//        delegate?.canvasTouchBegan(self)
        fastDrawingTimer?.invalidate()
        
        for touch in touches {
            let touchLocation = touch.location(in: self)
            
            if touch.type == .stylus {
                stylusTouchBeganLocation = touchLocation

                if Globals.outIsPressedDown {
                    return
                }
                
                let lastTouchEndedTimestamp = lastTouchTimestamp ?? touch.timestamp1970
                
                //If we are the first sketch we create the layer
                if currentlyDrawnSketch == nil || currentlyDrawnSketch!.isReallyDeleted {
                    addNewSketchLayer()
                } else {
                    //If not, we create a new sketch if:
                    // - we started this drawing more than 700ms since the last one, or
                    // - we are drawing really far away from an abstract drawing box
                    let currentSketch = currentlyDrawnSketch!
                    let tolerance = -self.frame.width * 0.30
                    let drawingBox = currentSketch.mutableShapeLayerPath.boundingBoxOfPath.insetBy(dx: tolerance, dy: tolerance)
                    
                    if !currentSketch.hasNoPoints && (touch.timestamp1970 - lastTouchEndedTimestamp > secondsBeforeConsiderNewSketh || !drawingBox.contains(touchLocation)) {
                        if let previouslyDrawnTier = currentlyDrawnSketch {
                            delegate?.canvasTierAdded(self,tier: previouslyDrawnTier)
                        }
                        addNewSketchLayer()
                    }
                }

                currentlyDrawnSketch?.addFirstPoint(touchLocation,timestamp: normalizeTime(touch.timestamp1970), shouldRecord: delegate?.shouldRecordInking ?? false)
                
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let touchLocation = touch.location(in: self)

            if touch.type == .stylus {
                if let startingLocation = stylusTouchBeganLocation, Globals.outIsPressedDown {
                    let invisibleXSliderValue = abs(startingLocation.x - touchLocation.x)
                    if invisibleXSliderValue > 0 {
                        for selectedTier in selectedSketches {
                            let percentage = CGFloat(1) - invisibleXSliderValue / selectedTier.shapeLayer.path!.boundingBoxOfPath.width
                            selectedTier.strokeEndChanged(percentage, timestamp: normalizeTime(touch.timestamp1970))
                            
                            selectedTier.shapeLayer.strokeEnd = percentage
                        }
                    }
                } else {
                    currentlyDrawnSketch?.addPoint(touchLocation, timestamp: normalizeTime(touch.timestamp1970), shouldRecord: delegate?.shouldRecordInking ?? false)
                }
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
//            let touchLocation = touch.location(in:self)

            if touch.type == .stylus {
                //There is at least one path in the Tier
                currentlyDrawnSketch?.hasDrawnPath = true
                
                lastTouchTimestamp = touch.timestamp1970
                
                if let lastTierDrawn = currentlyDrawnSketch {
                    fastDrawingTimer = Timer(fire: Date().addingTimeInterval(secondsBeforeConsiderNewSketh), interval: 0, repeats: false, block: { [unowned self] (aTimer) in
                        if let currentTier = self.currentlyDrawnSketch, lastTierDrawn == currentTier {
                            self.delegate?.canvasTierAdded(self, tier: lastTierDrawn)
                            self.currentlyDrawnSketch = nil
                        }
                        aTimer.invalidate()
                    })
                    RunLoop.main.add(fastDrawingTimer!, forMode: RunLoopMode.defaultRunLoopMode)
                }
                
                for selected in selectedSketches {
                    if Globals.outIsPressedDown {
                        self.delegate?.canvasTierModified(self, tier: selected, type:.strokeEnd)
                    }
                }
            }
        }
    }
    
    @objc func rotateDetected(recognizer:UIRotationGestureRecognizer) {
        switch recognizer.state {
        case .possible:
            print("rotateDetected possible")
            break
            
        case .began:
            print("rotateDetected began")
            break
            
        case .changed:
            print("rotateDetected changed")
            let rotationAngle = recognizer.rotation
            recognizer.rotation = 0

            for aSelectedSketch in selectedSketches {
                aSelectedSketch.rotationDelta(rotationAngle, timestamp: normalizeTime())
            }
            break
            
        case .ended:
            print("rotateDetected ended")
            
            for selectedSketch in selectedSketches {
                self.delegate?.canvasTierModified(self, tier: selectedSketch, type:.rotated)
            }
            break
            
        case .cancelled:
            print("rotateDetected cancelled")
            break
            
        case .failed:
            print("rotateDetected failed")
            break
        }
    }
    @objc func pinchDetected(recognizer:UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .possible:
            print("pinchDetected possible")
            break
            
        case .began:
            print("pinchDetected began")
            break
            
        case .changed:
            print("pinchDetected changed")
            
            let scale = recognizer.scale
            recognizer.scale = 1

            for aSelectedSketch in selectedSketches {
                aSelectedSketch.scalingDelta(CGPoint(x: scale,y: scale),timestamp: normalizeTime())
            }
            break
            
        case .ended:
            print("pinchDetected ended")
            for selectedSketch in selectedSketches {
                self.delegate?.canvasTierModified(self, tier: selectedSketch, type: .scaled)
            }
            break
            
        case .cancelled:
            print("pinchDetected cancelled")
            break
            
        case .failed:
            print("pinchDetected failed")
            break
        }
    }
    
    @objc func panDetected(recognizer:UIPanGestureRecognizer) {
        switch recognizer.state {
        case .possible:
            print("panDetected possible")
            break
            
        case .began:
            print("panDetected began")
            let touchLocation = recognizer.location(in: self)
            
            for tier in (videoTrack.tiers!.array as! [Tier]).reversed() {
                let p = canvasLayer.convert(touchLocation, to: tier.shapeLayer)
                if tier.shapeLayer.path!.boundingBoxOfPath.contains(p) {
                    if selectedSketches.count <= 1 {
                        videoTrack.deselectAllTiers()
                    }
                    tier.isSelected = true
                    return
                }
            }
            
            break
            
        case .changed:
            print("panDetected changed")
            let delta = recognizer.translation(in: self)
            recognizer.setTranslation(CGPoint.zero, in: self)
            
            for aSelectedSketch in selectedSketches {
                aSelectedSketch.translationDelta(delta,timestamp: normalizeTime())
            }
            break
            
        case .ended:
            print("panDetected ended")
            for selectedSketch in selectedSketches {
                self.delegate?.canvasTierModified(self, tier: selectedSketch, type: .moved)
            }
            break
            
        case .cancelled:
            print("panDetected cancelled")
            break
            
        case .failed:
            print("panDetected failed")
            break
        }
    }
    
//    @objc func swipeDetected(recognizer:UISwipeGestureRecognizer) {
//        switch recognizer.state {
//
//        case .ended:
//            print("swipeDetected ended")
//
//            let touchLocation = recognizer.location(in: self)
//
//            for sketchLayerToDelete in (videoTrack.tiers!.filter { ($0 as! Tier).shapeLayer.path!.contains(touchLocation) }) {
//                let sketchLayerToDelete = sketchLayerToDelete as! Tier
//                let shapeLayer = sketchLayerToDelete.shapeLayer
//                shapeLayer.removeFromSuperlayer()
//                videoTrack.removeFromTiers(sketchLayerToDelete)
//
//                //TODO: save in DB
//            }
//            break
//        default:
//            print("swipeDetected ignoring recognizer state")
//        }
//    }
    
    @objc func longPressDetected(recognizer:UILongPressGestureRecognizer) {
        switch recognizer.state {
            
        case .began:
            print("longPressDetected began")
            
            delegate?.canvasLongPressed(self,touchLocation: recognizer.location(in:self))
            break
        default:
            print("longPressDetected ignoring recognizer state")
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return otherGestureRecognizer != longPressRecognizer
    }

}

extension CanvasView:PaletteDelegate {
    func didChangeBrushAlpha(_ alpha: CGFloat) {

    }
    func didChangeBrushColor(_ color: UIColor) {
//        currentlyDrawnSketch.sketch?.strokeColor = color
        selectedStrokeColor = color
    }
    
    func didChangeBrushWidth(_ width: CGFloat) {
//        currentlyDrawnSketch.sketch?.lineWidth = Float(width)
        selectedLineWidth = Float(width)
    }
}
