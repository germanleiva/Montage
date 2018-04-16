//
//  VideoPlayerView.swift
//  VideoClipper
//
//  Created by German Leiva on 31/08/15.
//  Copyright © 2015 Germán Leiva. All rights reserved.
//

import UIKit
import AVFoundation

class VideoPlayerView: UIView {

    /*
    // Only override drawRect: if you perform custom drawing.
    // An empty implementation adversely affects performance during animation.
    override func drawRect(rect: CGRect) {
        // Drawing code
    }
    */
    var syncLayer:AVSynchronizedLayer? {
        get {
            return layer.sublayers?.first as? AVSynchronizedLayer
        }
        set(newSyncLayer) {
            layer.sublayers = nil
            if let newSyncLayer = newSyncLayer {
                layer.addSublayer(newSyncLayer)
            }
        }
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
//        layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat.pi / 2))
    }
	
	override class var layerClass : AnyClass {
		return AVPlayerLayer.self
	}
	
	var player: AVPlayer {
		get {
			let playerLayer = layer as! AVPlayerLayer
            playerLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
			return playerLayer.player!
		}
		set(newValue) {
			let playerLayer = layer as! AVPlayerLayer
			playerLayer.player = newValue
		}
	}

}
