//
//  UserInputPath+CoreDataClass.swift
//  
//
//  Created by Germán Leiva on 03/08/2018.
//
//

import Foundation
import CoreData

@objc(UserInputPath)
public class UserInputPath: UserInput {
    override func clone() -> UserInput {
        let new = UserInputPath(context: managedObjectContext!)
        new.value = value
        new.action = action
        new.timestamp = timestamp
        return new
    }
}
