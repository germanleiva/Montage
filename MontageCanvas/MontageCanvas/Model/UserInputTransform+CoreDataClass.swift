//
//  UserInputTransform+CoreDataClass.swift
//  
//
//  Created by Germán Leiva on 03/08/2018.
//
//

import Foundation
import CoreData

@objc(UserInputTransform)
public class UserInputTransform: UserInput {
    override func clone() -> UserInput {
        let new = UserInputTransform(context: managedObjectContext!)
        new.value = value
        new.timestamp = timestamp
        return new
    }
}
