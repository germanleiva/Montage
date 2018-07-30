//
//  VideoCell.swift
//  VideoBoard
//
//  Created by Germán Leiva on 09/06/2017.
//  Copyright © 2017 ExSitu. All rights reserved.
//

import UIKit

class VideoCell: UICollectionViewCell {
    @IBOutlet weak var imageView:UIImageView!
    @IBOutlet weak var activityIndicator:UIActivityIndicatorView!
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        activityIndicator.startAnimating()
    }
    
}
