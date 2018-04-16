//
//  TierTableCell.swift
//  Montage
//
//  Created by Germán Leiva on 30/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit

class TierTableCell: UITableViewCell {

    @IBOutlet weak var sketchView:UIView!
    @IBOutlet weak var sketchNameLabel:UILabel!
    var thumbnailLayer = CAShapeLayer()
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        layer.addSublayer(thumbnailLayer)
        
        sketchView.layer.borderColor = UIColor.lightGray.cgColor
        sketchView.layer.borderWidth = 1
        
        
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
