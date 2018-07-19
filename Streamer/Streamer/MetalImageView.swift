//
//  ImageView.swift
//  CoreImageHelpers
//
//  Created by Simon Gladman on 09/01/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.

import Metal
import MetalKit

/// `MetalImageView` extends an `MTKView` and exposes an `image` property of type `CIImage` to
/// simplify Metal based rendering of Core Image filters.
public class MetalImageView: MTKView {
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
    
    required public init(coder: NSCoder) {
        super.init(coder: coder)
        device = MTLCreateSystemDefaultDevice()
        framebufferOnly = false
    }
    
    /// The image to display
    public var image: CIImage? {
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
