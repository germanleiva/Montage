//
//  UserInput+CoreDataClass.swift
//  
//
//  Created by Germán Leiva on 03/08/2018.
//
//

import Foundation
import CoreData

@objc(UserInput)
public class UserInput: NSManagedObject {
    func clone() -> UserInput {
        fatalError("should be implemented in the subclass")
    }
}
