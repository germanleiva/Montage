//
//  TierCollectionViewCell.swift
//  Montage
//
//  Created by Germán Leiva on 29/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit

class TierCollectionViewCell: UICollectionViewCell {
    @IBOutlet weak var titleLabel:UILabel!
    
    override init(frame: CGRect) {
        super.init(frame:frame)
        initialize()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        initialize()
    }
    
    func initialize() {
        layer.cornerRadius = 10
        layer.borderWidth = 1.0
        layer.borderColor = UIColor(red: 0, green: 0, blue: 0.7, alpha: 1).cgColor
    }
    
}
