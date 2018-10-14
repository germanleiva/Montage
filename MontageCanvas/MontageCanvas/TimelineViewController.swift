//
//  TimelineViewController.swift
//  Montage
//
//  Created by Germán Leiva on 30/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import CoreData

protocol TimelineDelegate: AnyObject {
    func timeline(didUpdateVideo video:Video)
    func timeline(didSelectNewVideo video:Video)
    func timelineDidPressViewporting()
}

class TimelineViewController: UIViewController, NSFetchedResultsControllerDelegate, UITableViewDataSource, UITableViewDelegate {
    var videoTrack:VideoTrack! {
        didSet {
            if isViewLoaded {
                _fetchedResultsController = nil
                tableView.reloadData()
            }
        }
    }
    
    weak var delegate:TimelineDelegate?
    
    var canvasView:CanvasView!
    
    let managedObjectContext = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
    
    var userReorderingCells = false
    
    @IBOutlet weak var reuseButton:UIBarButtonItem!
    @IBOutlet weak var viewportButton:UIBarButtonItem!
    
    @IBOutlet weak var tableView:UITableView! {
        didSet {
            tableView.delegate = self
            tableView.dataSource = self
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        if videoTrack.isPrototype {
            reuseButton.isEnabled = true
            viewportButton.isEnabled = true
        }
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressDetected))
        tableView.addGestureRecognizer(longPressGesture)
    }
    
    lazy var paletteView:Palette = {
        let paletteView = Palette()
        paletteView.delegate = self
        paletteView.setup()
        self.paletteView = paletteView
        return paletteView
    }()
    
    @objc func longPressDetected(recognizer:UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            let touchLocation = recognizer.location(in:tableView)
            let paletteController = UIViewController()
            
            paletteController.view.translatesAutoresizingMaskIntoConstraints = false
            paletteController.modalPresentationStyle = UIModalPresentationStyle.popover
            let paletteHeight = paletteView.paletteHeight()
            
            paletteController.preferredContentSize = CGSize(width:Palette.initialWidth,height:paletteHeight)
            paletteController.view.frame = CGRect(x:0,y:0,width:Palette.initialWidth,height:paletteHeight)
            paletteView.frame = CGRect(x: 0, y: 0, width: paletteController.view.frame.width, height: paletteController.view.frame.height)
            paletteController.view.addSubview(paletteView)
            //        paletteView.frame = CGRect(x: 0, y: paletteController.view.frame.height - paletteHeight, width: paletteController.view.frame.width, height: paletteHeight)
            
            if let selectedIndexPath = tableView.indexPathForSelectedRow {
                paletteController.popoverPresentationController?.sourceView = tableView.cellForRow(at: selectedIndexPath)
            }
            paletteController.popoverPresentationController?.sourceRect = CGRect(origin: touchLocation, size: CGSize.zero)
            
            present(paletteController, animated: true)

        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        if segue.identifier == "VIDEO_CATALOG_NAVIGATION_SEGUE" {
            
            guard let videoCatalogNavigationController = segue.destination as? UINavigationController,
                let videoCatalogController = videoCatalogNavigationController.topViewController as? VideoCatalogController else {
                return
            }
            
            videoCatalogController.myVideoTrack = videoTrack
            videoCatalogController.delegate = self
            
//            present(videoCatalogNavigationController, animated: true, completion: nil)
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
        let tier = fetchedResultsController.object(at: indexPath)
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "TIER_CELL", for: indexPath) as! TierTableCell
        configureCell(cell, withTier: tier)
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
        
        let source = fetchedResultsController.object(at: sourceIndexPath)
        
        //TODO:        videoTrack.move(line:source,to:destinationIndexPath.row)
        
        do {
            try managedObjectContext.save()
        } catch {
            alert(error,title:"DB Error",message:"Could not save the reorder of lines")
        }
        
        //This is necesary because when we move a parent line we are also moving a bunch of alternatives with it
        tableView.reloadData()
        
        userReorderingCells = false
        
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
            
            let tierToDelete = fetchedResultsController.object(at: indexPath)
            
            context.delete(tierToDelete)
            
            canvasView.delegate?.canvasTierRemoved(canvasView, tier: tierToDelete)

            //TODO: we need to ensure that this update is trigger if an element is deleted anywhere
//            board?.rebuildSortIndexes()
            
//            do {
//                try context.save()
//            } catch {
//                alert(error,title:"DB Error",message:"Could not delete the board")
//            }
        }
    }
    
    // MARK: - Table View Delegate
    
    
    func configureCell(_ cell: TierTableCell, withTier tier: Tier) {
//        cell.textLabel!.text = tier.createdAt!.description
        
        
        if let layer = tier.sketch?.buildShapeLayer(for: tier) {
            
            if let sublayers = cell.sketchView.layer.sublayers {
                for eachSublayer in sublayers {
                    eachSublayer.removeFromSuperlayer()
                }
            }

            layer.setAffineTransform(tier.currentTransformation.concatenating(CGAffineTransform(scaleX: 1.0/9.0, y: 1.0/5.0)))
            
            cell.sketchView.layer.addSublayer(layer)

        }
        
        if let indexPath = fetchedResultsController.indexPath(forObject: tier) {
            if tier.isSelected {
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: UITableViewScrollPosition.none)
            } else {
                tableView.deselectRow(at: indexPath, animated: false)
            }
        }
        
        cell.sketchNameLabel.text = "Sketch \(tier.videoTrack!.tiers!.index(of: tier)+1)"
    }
    
    func clearTableSelection() {
        guard let selectedIndexPath = tableView.indexPathForSelectedRow else {
            return
        }
        tableView.deselectRow(at: selectedIndexPath, animated: true)
    }
    
    func scrollTo(tier: Tier, animated:Bool) {
        if let tierIndexPath = fetchedResultsController.indexPath(forObject: tier) {
            tableView.scrollToRow(at: tierIndexPath, at: .top, animated: animated)
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let tier = fetchedResultsController.object(at: indexPath)
        tier.isSelected = true
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        let tier = fetchedResultsController.object(at: indexPath)
        tier.isSelected = false
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
    
    var fetchedResultsController: NSFetchedResultsController<Tier> {
        if _fetchedResultsController != nil {
            return _fetchedResultsController!
        }
        
        let fetchRequest: NSFetchRequest<Tier> = Tier.fetchRequest()
        
        // Set the batch size to a suitable number.
        fetchRequest.fetchBatchSize = 20
        
        fetchRequest.predicate = NSPredicate(format: "self.videoTrack = %@ AND self.hasDrawnPath = true", self.videoTrack)
        
        // Edit the sort key as appropriate.
        let sortDescriptor = NSSortDescriptor(key: "zIndex", ascending: true)
        
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        // Edit the section name key path and cache name if appropriate.
        // nil for section name key path means "no sections".
        let aFetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: managedObjectContext, sectionNameKeyPath: nil, cacheName: "Master")
        aFetchedResultsController.delegate = self
        _fetchedResultsController = aFetchedResultsController
        
        do {
            try _fetchedResultsController!.performFetch()
        } catch {
            alert(error, title: "DB Error" , message: "Could not retrieve the elements from the DB")
        }
        
        return _fetchedResultsController!
    }
    var _fetchedResultsController: NSFetchedResultsController<Tier>? = nil
    
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
            print("\(className) >> it was a move")
        case .update:
            print("\(className) >> it was an update")
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        //We need to stop listening for changes while the user is interacting
        if (userReorderingCells) {
            return
        }
        
        switch type {
        case .insert:
            print("\(className) >> it was an insert \(newIndexPath!.row)")
            tableView.insertRows(at: [newIndexPath!], with: .fade)
        case .delete:
            tableView.deleteRows(at: [indexPath!], with: .fade)
        case .update:
            print("\(className) >> it was an update \(indexPath!.row) \(newIndexPath!.row)")
            if let updatedCell = tableView.cellForRow(at: indexPath!) {
                configureCell(updatedCell as! TierTableCell, withTier: anObject as! Tier)
            } else {
                print("\(className) It should not call didChange for this row \(indexPath!.row), because there is no associated UITableViewCell - BIG PROBLEM")
            }
        case .move:
            print("\(className) >> it was a move \(indexPath!.row) \(newIndexPath!.row)")
            configureCell(tableView.cellForRow(at: indexPath!) as! TierTableCell, withTier: anObject as! Tier)
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
    
    // MARK: - Actions
    
    @IBAction func mergeButtonPressed(_ sender:AnyObject?) {
        print("Not yet implemented")
//        var tiersToMerge = videoTrack.selectedTiers
//        if tiersToMerge.count >= 2 {
//            let baseTier = tiersToMerge.removeFirst()
//
//            for mergedTier in tiersToMerge {
//                baseTier
//            }
//        }
    }
    
    @IBAction func viewportButtonPressed(_ sender:AnyObject?) {
        if let viewportButton = sender as? UIBarButtonItem {
            viewportButton.tintColor = viewportButton.tintColor == UIColor.red ? view.tintColor : UIColor.red
        }
        delegate?.timelineDidPressViewporting()
    }
    
    @IBAction func outButtonPressed(_ sender:AnyObject?) {
//        Globals.outIsPressedDown = true
        for selectedTier in canvasView.selectedSketches {
            selectedTier.disappearAtTimes = [canvasView.delegate!.currentTime]
            canvasView.delegate?.canvasTierModified(canvasView, tier: selectedTier, type: .disappear)
        }
    }
    
    @IBAction func inButtonPressed(_ sender:AnyObject?) {
//        Globals.inIsPressedDown = true
        for selectedTier in canvasView.selectedSketches {
            selectedTier.shouldAppearAt(time: canvasView.delegate!.currentTime)
            canvasView.delegate?.canvasTierModified(canvasView, tier: selectedTier, type: .appear)
        }
    }
    
    @IBAction func strokeStartSliderChanged(_ sender:UISlider) {
        print("strokeStartSliderChanged")
        let percentage = sender.value
        for selectedTier in canvasView.selectedSketches {
            selectedTier.strokeStartChanged(percentage, timestamp: canvasView.normalizeTime(Date().timeIntervalSince1970))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            selectedTier.shapeLayer.strokeStart = CGFloat(percentage)
            CATransaction.commit()
        }
    }
    
    @IBAction func strokeStartSliderReleased(_ sender:UISlider) {
        print("strokeStartSliderReleased")
        for selected in canvasView.selectedSketches {
            canvasView.delegate?.canvasTierModified(canvasView, tier: selected, type:.strokeStart)
        }
        sender.value = 0
    }
    
    @IBAction func strokeEndSliderChanged(_ sender:UISlider) {
        print("strokeEndSliderChanged")
        let percentage = sender.value
        for selectedTier in canvasView.selectedSketches {
            selectedTier.strokeEndChanged(percentage, timestamp: canvasView.normalizeTime(Date().timeIntervalSince1970))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            selectedTier.shapeLayer.strokeEnd = CGFloat(percentage)
            CATransaction.commit()
        }
    }
    
    @IBAction func strokeEndSliderReleased(_ sender:UISlider) {
        print("strokeEndSliderReleased")
        for selected in canvasView.selectedSketches {
            canvasView.delegate?.canvasTierModified(canvasView, tier: selected, type: .strokeEnd)
        }
        sender.value = 1
    }
}

extension TimelineViewController: VideoCatalogDelegate {
    func videoCatalog(didSelectPrototypeTrack prototypeTrackToCopyFrom: VideoTrack, for video: Video) {
        delegate?.timeline(didUpdateVideo:video)
    }
    func videoCatalog(didSelectNewVideo video: Video) {
        delegate?.timeline(didSelectNewVideo: video)
    }
}

extension TimelineViewController:PaletteDelegate {
    func didChangeBrushAlpha(_ alpha: CGFloat) {
        
    }
    func didChangeBrushColor(_ color: UIColor) {
        //        currentlyDrawnSketch.sketch?.strokeColor = color
        guard let tiers = fetchedResultsController.fetchedObjects else {
            return
        }
        for aTier in tiers {
            if aTier.isSelected {
                aTier.strokeColor = color
                aTier.sketch?.strokeColor = color
                aTier.shapeLayer.strokeColor = color.cgColor
            }
        }
    }
    
    func didChangeBrushWidth(_ width: CGFloat) {
        //        currentlyDrawnSketch.sketch?.lineWidth = Float(width)
        guard let tiers = fetchedResultsController.fetchedObjects else {
            return
        }
        for aTier in tiers {
            if aTier.isSelected {
                aTier.lineWidth = Float(width)
                aTier.sketch?.lineWidth = Float(width)
                aTier.shapeLayer.lineWidth = width
            }
        }
    }
}
