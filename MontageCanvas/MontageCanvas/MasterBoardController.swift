//
//  MasterBoardController.swift
//  Montage
//
//  Created by Germán Leiva on 05/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import CoreData

class MasterBoardController: UIViewController, NSFetchedResultsControllerDelegate, UITableViewDelegate, UITableViewDataSource {

    var detailViewController: DetailLineController? = nil
    var managedObjectContext: NSManagedObjectContext? = nil
    
    //TODO: We sould change the implementation to use gesture recognizers instead of didSelectRowAtIndexPath
    var selectedRow:IndexPath? = nil
    
    var board:Board? = nil {
        didSet {
            title = board?.name
        }
    }
    
    var userReorderingCells = false
    
    // MARK: Outlets
    
    @IBOutlet var tableView:UITableView!
    @IBOutlet var buttonAdd:UIBarButtonItem!
    @IBOutlet var buttonAlternate:UIBarButtonItem!
    
    // MARK: UIViewController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        //navigationItem.leftBarButtonItem = editButtonItem
        
        if let split = splitViewController {
            // The split viewControllers property:
            // When the split view interface is expanded, this property contains two view controllers;
            // when it is collapsed, this property contains only one view controller.
            // The first view controller in the array is always the primary (or master) view controller.
            // If a second view controller is present, that view controller is the secondary (or detail) view controller.
            let detailNavigationController = split.viewControllers.last as! UINavigationController
            detailViewController = detailNavigationController.topViewController as? DetailLineController
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
//        if splitViewController!.isCollapsed {
//            clearTableSelection()
//        }
        super.viewWillAppear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        self.tableView.setEditing(editing, animated: true)
    }
    
    // MARK: - Segues
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "SEGUE_SHOWDETAIL_SPLIT" {
            if let indexPath = tableView.indexPathForSelectedRow {
                let line = fetchedResultsController.object(at: indexPath)
                let controller = (segue.destination as! UINavigationController).topViewController as! DetailLineController
                controller.line = line
                controller.navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
                controller.navigationItem.leftItemsSupplementBackButton = true
            }
        }
    }
    
    // MARK: - Table View Data Source
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return fetchedResultsController.sections?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionInfo = fetchedResultsController.sections![section]
        return sectionInfo.numberOfObjects
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let line = fetchedResultsController.object(at: indexPath)
        
        let identifier = line.isAlternative ? "CELL_ALTERNATIVE_IDENTIFIER" : "CELL_LINE_IDENTIFIER"
        
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        configureCell(cell, withLine: line)
        return cell
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    
    //This method enables the showReorderControl in UITableViewCell
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        userReorderingCells = true
        
        if let board = board {
            let source = fetchedResultsController.object(at: sourceIndexPath)

            board.move(line:source,to:destinationIndexPath.row)
            
            do {
                try managedObjectContext?.save()
            } catch {
                alert(error,title:"DB Error",message:"Could not save the reorder of lines")
            }
        }
        
        //This is necesary because when we move a parent line we are also moving a bunch of alternatives with it
        tableView.reloadData()
        
        userReorderingCells = false

    }
    
    //This restrict the movement of a row
    func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        let line = fetchedResultsController.object(at: sourceIndexPath)
        
        if line.isAlternative {
            let parentIndex = Int(line.parent!.sortIndex)
            //I will retarget withing the parent line
            
            //Smaller than the parent index
            if (proposedDestinationIndexPath.row <= parentIndex) {
                return IndexPath(row: parentIndex + 1, section: proposedDestinationIndexPath.section)
            }
            //Bigger than the parent index + the alternatives count
            let maximumIndexForAlternative = parentIndex + line.parent!.alternatives!.count
            if (proposedDestinationIndexPath.row > maximumIndexForAlternative) {
                return IndexPath(row:maximumIndexForAlternative, section: proposedDestinationIndexPath.section)
            }
            return proposedDestinationIndexPath
        }
        
        //If the line is parent, it cannot land as an alternative
        let alternativesIndexes = (board!.lines!.array as! [Line]).filter({ $0.isAlternative }).map({Int($0.sortIndex)})
        
        if alternativesIndexes.contains(proposedDestinationIndexPath.row) {
            return sourceIndexPath
        }
        return proposedDestinationIndexPath
        
    }
    
    //TODO: do we need this?
//    func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
//        if sourceIndexPath.section != proposedDestinationIndexPath.section {
//            var row = 0
//            if sourceIndexPath.section < proposedDestinationIndexPath.section {
//                row = self.tableView(tableView, numberOfRowsInSection: sourceIndexPath.section) - 1
//            }
//            return IndexPath(row: row, section: sourceIndexPath.section)
//        }
//        return proposedDestinationIndexPath
//    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let context = fetchedResultsController.managedObjectContext
            
            let lineToDelete = fetchedResultsController.object(at: indexPath)
            
            //I need to delete all the alternatives also
            for each in lineToDelete.alternatives!.array as! [Line] {
                context.delete(each)
            }
            context.delete(lineToDelete)
            
            //TODO: we need to ensure that this update is trigger if an element is deleted anywhere
            board?.rebuildSortIndexes()
            
            do {
                try context.save()
            } catch {
                alert(error,title:"DB Error",message:"Could not delete the board")
            }
        }
    }
    
    // MARK: - Table View Delegate
    
    func configureCell(_ cell: UITableViewCell, withLine line: Line) {
//        cell.textLabel!.text = line.createdAt!.description
        
        let name:String
        
        if line.isAlternative {
            name = "Alternative \(line.parent!.alternatives!.index(of: line) + 1)"
        } else {
            let storyLines = (line.board!.lines!.array as! [Line]).filter {!$0.isAlternative}
            name = "Story \(storyLines.index(of: line)! + 1)"
        }

        cell.textLabel!.text = name
    }
    
    func clearTableSelection() {
        guard let selectedIndexPath = tableView.indexPathForSelectedRow else {
            return
        }
        tableView.deselectRow(at: selectedIndexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        var rowAlreadySelected = false
        
        //We should always update the selected row, unless it is already selected
        if selectedRow == nil || selectedRow! != indexPath {
            selectedRow = indexPath
        } else {
            rowAlreadySelected = true
        }
        
        //If the split is collapsed we should only execute the segue if the row was already selected
        //If the split is expanded we should always execute the segue
        
        let splitExpanded = !splitViewController!.isCollapsed
        
        if splitExpanded || rowAlreadySelected {
            performSegue(withIdentifier: "SEGUE_SHOWDETAIL_SPLIT", sender: nil)
        }
    }
    
    // The willBegin/didEnd methods are called whenever the 'editing' property is automatically changed by the table (allowing insert/delete/move). This is done by a swipe activating a single row

    // willBeginEditingRowAt is called when the user swipes over a cell
    func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        print("willBeginEditingRowAt \(indexPath)")
    }
    //willBeginEditingRowAt is called when the user stopped swipping over a cell
    func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        print("didEndEditingRowAt \(indexPath!)")
    }
    
    // MARK: - Fetched results controller
    
    var fetchedResultsController: NSFetchedResultsController<Line> {
        if _fetchedResultsController != nil {
            return _fetchedResultsController!
        }
        
        let fetchRequest: NSFetchRequest<Line> = Line.fetchRequest()
        
        // Set the batch size to a suitable number.
        fetchRequest.fetchBatchSize = 20
        
//        fetchRequest.predicate = NSPredicate(format: "self.board = %@ AND self.hide = false", self.board!)
        fetchRequest.predicate = NSPredicate(format: "self.board = %@", self.board!)
        
        // Edit the sort key as appropriate.
        let sortDescriptor = NSSortDescriptor(key: "sortIndex", ascending: true)
        
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        // Edit the section name key path and cache name if appropriate.
        // nil for section name key path means "no sections".
        let aFetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: self.managedObjectContext!, sectionNameKeyPath: nil, cacheName: nil)
        aFetchedResultsController.delegate = self
        _fetchedResultsController = aFetchedResultsController
        
        do {
            try _fetchedResultsController!.performFetch()
        } catch {
            alert(error, title: "DB Error" , message: "Could not retrieve the elements from the DB")
        }
        
        return _fetchedResultsController!
    }
    var _fetchedResultsController: NSFetchedResultsController<Line>? = nil
    
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if (userReorderingCells) {
            return
        }
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        switch type {
        case .insert:
            tableView.insertSections(IndexSet(integer: sectionIndex), with: .fade)
        case .delete:
            tableView.deleteSections(IndexSet(integer: sectionIndex), with: .fade)
        case .move:
            print("it was a move")
        case .update:
            print("it was an update")
        default:
            return
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        //We need to stop listening for changes while the user is interacting
        if (userReorderingCells) {
            return
        }
        
        switch type {
        case .insert:
            tableView.insertRows(at: [newIndexPath!], with: .fade)
        case .delete:
            tableView.deleteRows(at: [indexPath!], with: .fade)
        case .update:
            print("it was an update \(indexPath!.row) \(newIndexPath!.row)")
            if let updatedCell = tableView.cellForRow(at: indexPath!) {
                configureCell(updatedCell, withLine: anObject as! Line)
            } else {
                print("It should not call didChange for this row, because there is no associated UITableViewCell - BIG PROBLEM")
            }
        case .move:
            print("it was a move \(indexPath!.row) \(newIndexPath!.row)")
            configureCell(tableView.cellForRow(at: indexPath!)!, withLine: anObject as! Line)
            tableView.moveRow(at: indexPath!, to: newIndexPath!)
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        //We need to stop listening for changes while the user is interacting
        if (userReorderingCells) {
            return
        }
        tableView.endUpdates()
    }
    
    /*
     // Implementing the above methods to update the table view in response to individual changes may have performance implications if a large number of changes are made simultaneously. If this proves to be an issue, you can instead just implement controllerDidChangeContent: which notifies the delegate that all section and object changes have been processed.
     
     func controllerDidChangeContent(controller: NSFetchedResultsController) {
     // In the simplest, most efficient, case, reload the table view.
     tableView.reloadData()
     }
     */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */
    
    // MARK: - Actions
    @IBAction func toggleEdit(_ sender: UIBarButtonItem) {
        self.setEditing(!self.isEditing, animated: true)
        
        if self.isEditing {
            sender.title = "Done"
            buttonAdd.isEnabled = false
            buttonAlternate.isEnabled = false
        } else {
            sender.title = "Edit"
            buttonAdd.isEnabled = true
            buttonAlternate.isEnabled = true
        }
    }

    @IBAction func insertNewLine(_ sender: UIBarButtonItem) {
        let context = self.fetchedResultsController.managedObjectContext
        let newLine = Line(context: context)
        
        // If appropriate, configure the new managed object.
        newLine.createdAt = Date()
        newLine.sortIndex = Int32(board!.lines!.count)
        
        board?.addToLines(newLine)
        
        // Save the context.
        do {
            try context.save()
        } catch {
            alert(error,title: "DB Error",message: "Could not insert new line")
        }
    }
    
    @IBAction func insertNewAlternative(_ sender:UIBarButtonItem) {
        
        if let selectedIndexPath = tableView.indexPathsForSelectedRows?.first {
            var parentLine = self.fetchedResultsController.object(at: selectedIndexPath)
            
            //If you try to create an alternative over an alternative, you will create a sibling
            if parentLine.isAlternative {
                parentLine = parentLine.parent!
            }
            let parentIndexPath = self.fetchedResultsController.indexPath(forObject: parentLine)!
            
            let context = self.fetchedResultsController.managedObjectContext
            
            
            let newLine = Line(context:context)
            parentLine.addToAlternatives(newLine)
            
            newLine.createdAt = Date()
            board?.move(line: newLine, to: parentIndexPath.row + parentLine.alternatives!.count)
            
            // Save the context.
            do {
                try context.save()
            } catch {
                alert(error,title: "DB Error",message: "Could not insert new line")
            }
        }
        
        
        
    }
}
