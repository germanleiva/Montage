//
//  Board+CoreDataClass.swift
//  Montage
//
//  Created by Germán Leiva on 05/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//
//

import Foundation
import CoreData

@objc(Board)
public class Board: NSManagedObject {
    
    //This method ensures that the order of the elements in the lines set corresponds with the property sortIndex in each element
    func move(line lineToMove:Line,to destinationIndex:Int) {
        //We create a copy of the lines in the board to manipulate their order
        let newLines = lines!.mutableCopy() as! NSMutableOrderedSet
        
        //We remove the element that we just dropped from the set
        newLines.remove(lineToMove)
        
        //We add the dropped element in the dropped indexPath.row in the tableView
        newLines.insert(lineToMove, at: destinationIndex) //This pushes all the object from that that index to the end
        
        //We need to also move the alternatives
        if lineToMove.isParent {
            let alternatives = lineToMove.alternatives!.array
            newLines.removeObjects(in: alternatives)
            let newIndex = newLines.index(of: lineToMove)
            for alternative in alternatives.reversed() {
                newLines.insert(alternative, at: newIndex + 1)
            }
        }
        
        //Each line knows its sortIndex, let's update of all of them
        rebuildSortIndexes(newLines)
        
        //We set the new orderedSet as the lines of the board
        lines = newLines
    }
    
    func rebuildSortIndexes() {
        rebuildSortIndexes(lines!)
    }
    
    func rebuildSortIndexes(_ newLines:NSOrderedSet) {
        for (index, object) in newLines.enumerated() {
            if let line = object as? Line {
                line.sortIndex = Int32(index)
            }
        }
    }
}
