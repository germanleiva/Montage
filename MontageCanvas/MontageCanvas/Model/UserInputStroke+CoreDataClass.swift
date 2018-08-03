//
//  UserInputStroke+CoreDataClass.swift
//  
//
//  Created by Germán Leiva on 03/08/2018.
//
//

import Foundation
import CoreData

@objc(UserInputStroke)
public class UserInputStroke: UserInput {
    override func clone() -> UserInput {
        let new = UserInputStroke(context: managedObjectContext!)
        new.value = value
        new.timestamp = timestamp
        return new
    }
}
