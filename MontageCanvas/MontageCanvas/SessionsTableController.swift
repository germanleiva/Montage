//
//  SessionsViewController.swift
//  Montage
//
//  Created by Germán Leiva on 05/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import CoreData

let CELL_BOARD_IDENTIFIER = "CELL_BOARD_IDENTIFIER"
let SEGUE_SESSIONS_TO_BOARD = "SEGUE_SESSIONS_TO_BOARD"

class SessionsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, NSFetchedResultsControllerDelegate {
    var managedObjectContext: NSManagedObjectContext? = nil
    @IBOutlet weak var tableView:UITableView!
    
//    lazy var storyLineViewController:StoryLineViewController = {
//        let controllers = splitViewController!.viewControllers
//        return (controllers[controllers.count-1] as! UINavigationController).topViewController as! StoryLineViewController
//    }()
    
    @IBAction func insertNewBoard(_ sender: Any) {
        let context = self.fetchedResultsController.managedObjectContext
        let newBoard = Board(context: context)
        
        // If appropriate, configure the new managed object.
        newBoard.updatedAt = Date()
        newBoard.name = "Session \(fetchedResultsController.fetchedObjects!.count + 1)"
        
        let firstLine = Line(context: context)
        firstLine.createdAt = Date()
        newBoard.addToLines(firstLine)
        
        // Save the context.
        do {
            try context.save()
            let newBoardIndexPath = fetchedResultsController.indexPath(forObject: newBoard)
            tableView.selectRow(at: newBoardIndexPath, animated: true, scrollPosition: UITableViewScrollPosition.none)
            performSegue(withIdentifier: SEGUE_SESSIONS_TO_BOARD, sender: nil)
        } catch {
            alert(error,title:"DB Error",message:"Could not insert new board")
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Uncomment the following line to preserve selection between presentations
        //         self.clearsSelectionOnViewWillAppear = false
        
        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
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
        let cell = tableView.dequeueReusableCell(withIdentifier: CELL_BOARD_IDENTIFIER, for: indexPath)
        let board = fetchedResultsController.object(at: indexPath)
        configureCell(cell, withBoard: board)
        return cell
    }
    
    // MARK: Table View Delegate
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let context = fetchedResultsController.managedObjectContext
            context.delete(fetchedResultsController.object(at: indexPath))
            do {
                try context.save()
                //TODO: self.storyLineViewController.storyLine = nil
            } catch let error as NSError{
                alert(error,title:"DB Error",message: "Could not delete line")
            }
        }
    }
    
    func configureCell(_ cell: UITableViewCell, withBoard board: Board) {
        cell.textLabel!.text = board.name
    }
    
    // MARK: - Fetched results controller
    
    var fetchedResultsController: NSFetchedResultsController<Board> {
        if _fetchedResultsController != nil {
            return _fetchedResultsController!
        }
        
        let fetchRequest: NSFetchRequest<Board> = Board.fetchRequest()
        
        // Set the batch size to a suitable number.
        fetchRequest.fetchBatchSize = 20
        
        // Edit the sort key as appropriate.
        let sortDescriptor = NSSortDescriptor(key: "updatedAt", ascending: false)
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        
        // Edit the section name key path and cache name if appropriate.
        // nil for section name key path means "no sections".
        let aFetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: self.managedObjectContext!, sectionNameKeyPath: nil, cacheName: "Master")
        aFetchedResultsController.delegate = self
        _fetchedResultsController = aFetchedResultsController
        
        do {
            try _fetchedResultsController!.performFetch()
        } catch {
            alert(error,title: "DB Error",message: "Could not retrieve the lines from the DB")
        }
        
        return _fetchedResultsController!
    }
    var _fetchedResultsController: NSFetchedResultsController<Board>? = nil
    
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        switch type {
        case .insert:
            tableView.insertSections(IndexSet(integer: sectionIndex), with: .fade)
        case .delete:
            tableView.deleteSections(IndexSet(integer: sectionIndex), with: .fade)
        default:
            return
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        // this is used to manage the Tableview in Masterview
        switch type {
        case .insert:
            //insert a new row of storyLine in the tableview
            tableView.insertRows(at: [newIndexPath!], with: .fade)
        case .delete:
            //swipe a storyLine to the left to delete
            tableView.deleteRows(at: [indexPath!], with: .fade)
        case .update:
            configureCell(tableView.cellForRow(at: indexPath!)!, withBoard: anObject as! Board)
        case .move:
            configureCell(tableView.cellForRow(at: indexPath!)!, withBoard: anObject as! Board)
            tableView.moveRow(at: indexPath!, to: newIndexPath!)
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
    
    /*
     // Override to support conditional editing of the table view.
     override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
     // Return false if you do not want the specified item to be editable.
     return true
     }
     */
    
    /*
     // Override to support editing the table view.
     override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
     if editingStyle == .delete {
     // Delete the row from the data source
     tableView.deleteRows(at: [indexPath], with: .fade)
     } else if editingStyle == .insert {
     // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
     }
     }
     */
    
    /*
     // Override to support rearranging the table view.
     override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {
     
     }
     */
    
    /*
     // Override to support conditional rearranging of the table view.
     override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
     // Return false if you do not want the item to be re-orderable.
     return true
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
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        if segue.identifier! == SEGUE_SESSIONS_TO_BOARD {
            if let indexPath = tableView.indexPathForSelectedRow {
                let selectedBoard = fetchedResultsController.object(at: indexPath)
                print(selectedBoard.objectID)
                let controller = segue.destination as! MasterBoardController
                controller.managedObjectContext = managedObjectContext
                controller.board = selectedBoard
                controller.navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
                controller.navigationItem.leftItemsSupplementBackButton = true
            }
        }
    }
}
