//
//  ImageView.swift
//  CoreImageHelpers
//
//  Created by Simon Gladman on 09/01/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//
import Metal
import MetalKit

/// `MetalImageView` extends an `MTKView` and exposes an `image` property of type `CIImage` to
/// simplify Metal based rendering of Core Image filters.
class MetalImageView: MTKView {
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    lazy var commandQueue: MTLCommandQueue = {
        [unowned self] in

        return self.device!.makeCommandQueue()!
    }()

    lazy var ciContext: CIContext = {
        [unowned self] in

        return CIContext(mtlDevice: self.device!)
    }()

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect,
                   device: device ?? MTLCreateSystemDefaultDevice())

        if super.device == nil
        {
            fatalError("Device doesn't support Metal")
        }

        framebufferOnly = false
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        device = MTLCreateSystemDefaultDevice()
        framebufferOnly = false
    }

    /// The image to display
    var image: CIImage? {
        didSet {
            renderImage()
        }
    }

    func renderImage() {
        guard let image = image, let targetTexture = currentDrawable?.texture else {
            return
        }

        let commandBuffer = commandQueue.makeCommandBuffer()

        let bounds = CGRect(origin: CGPoint.zero, size: drawableSize)

        let originX = image.extent.origin.x
        let originY = image.extent.origin.y

        let scaleX = drawableSize.width / image.extent.width
        let scaleY = drawableSize.height / image.extent.height
        let scale = min(scaleX, scaleY)

        let scaledImage = image
            .transformed(by: CGAffineTransform(translationX: -originX, y: -originY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        ciContext.render(scaledImage,
                         to: targetTexture,
                         commandBuffer: commandBuffer,
                         bounds: bounds,
                         colorSpace: colorSpace)

        commandBuffer?.present(currentDrawable!)

        commandBuffer?.commit()
    }
}

//class MetalImageView: MTKView {
//
//    var image: CIImage? {
//        didSet {
//            self.draw()
//        }
//    }
//
//    var originalImageExtent: CGRect = CGRect.zero {
//        didSet {
//
//        }
//    }
//
//    var scale: CGFloat {
//
//        return max(self.frame.width / originalImageExtent.width, self.frame.height / originalImageExtent.height)
//    }
//
//    func update() {
//
//        guard let img = image, destRect.size.width <= img.extent.size.width && destRect.size.height <= img.extent.size.height else {
//            return
//        }
//
//        self.draw()
//    }
//
//    let context: CIContext
//    let commandQueue: MTLCommandQueue
//
//    convenience init(frame: CGRect) {
//        let device = MTLCreateSystemDefaultDevice()
//        self.init(frame: frame, device: device)
//    }
//
//    override init(frame frameRect: CGRect, device: MTLDevice?) {
//        guard let device = device else {
//            fatalError("Can't use Metal")
//        }
//        commandQueue = device.makeCommandQueue(maxCommandBufferCount: 5)!
//        context = CIContext(mtlDevice: device, options: [kCIContextUseSoftwareRenderer:false])
//        super.init(frame: frameRect, device: device)
//
//        self.framebufferOnly = false
//        self.enableSetNeedsDisplay = false
//        self.isPaused = true
//        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
//    }
//
//    required init(coder aDecoder: NSCoder) {
//        guard let device = MTLCreateSystemDefaultDevice() else {
//            fatalError("Can't use Metal")
//        }
//        commandQueue = device.makeCommandQueue(maxCommandBufferCount: 5)!
//        context = CIContext(mtlDevice: device, options: [kCIContextUseSoftwareRenderer:false])
//        super.init(coder: aDecoder)
//        self.device = device
//
//        self.framebufferOnly = false
//        self.enableSetNeedsDisplay = false
//        self.isPaused = true
//        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
////        fatalError("init(coder:) has not been implemented")
//    }
//
//    override func draw(_ rect: CGRect) {
//
////        JEDump(rect, "Draw Use Metal")
//
//
//        guard let image = self.image else {
//            return
//        }
//
//        let dRect = destRect
//
//        let drawImage: CIImage
//
//        if dRect == image.extent {
//            drawImage = image
//        } else {
//            let scale = max(dRect.height / image.extent.height, dRect.width / image.extent.width)
//            drawImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
//        }
//
//        let commandBuffer = commandQueue.makeCommandBufferWithUnretainedReferences()
//        guard let texture = self.currentDrawable?.texture else {
//            return
//        }
//
//        let colorSpace = drawImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
//
//        context.render(drawImage, to: texture, commandBuffer: commandBuffer, bounds: dRect, colorSpace: colorSpace)
//
//        commandBuffer?.present(self.currentDrawable!)
//        commandBuffer?.commit()
//    }
//
//    private var destRect: CGRect {
//            return bounds
////        let scale: CGFloat
////        if UIScreen.mainScreen().scale == 3 {
////            // BUG?
////            scale = 2.0 * (2.0 / UIScreen.mainScreen().scale) * 2
////        } else {
////            scale = UIScreen.mainScreen().scale
////        }
////        let destRect = CGRectApplyAffineTransform(self.bounds, CGAffineTransformMakeScale(scale, scale))
////
////        return destRect
//    }
//}
