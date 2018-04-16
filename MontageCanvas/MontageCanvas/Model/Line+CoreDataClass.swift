//
//  Line+CoreDataClass.swift
//  Montage
//
//  Created by Germán Leiva on 05/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//
//

import Foundation
import CoreData

@objc(Line)
public class Line: NSManagedObject {
    var isAlternative:Bool {
        return self.parent != nil
    }
    var isParent:Bool {
        return self.parent == nil
    }
}
