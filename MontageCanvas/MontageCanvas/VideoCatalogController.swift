//
//  VideoCatalogController.swift
//  MontageCanvas
//
//  Created by Germán Leiva on 25/07/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import CoreData
import AVKit

protocol VideoCatalogDelegate: AnyObject {
    func videoCatalog(didSelectPrototypeTrack prototypeTrack:VideoTrack)
    func videoCatalog(didSelectNewVideo video:Video)
}

let CELL_VIDEO_CATALOG_IDENTIFIER = "CELL_VIDEO_CATALOG_IDENTIFIER"

class VideoCatalogController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, NSFetchedResultsControllerDelegate {
    var myVideoTrack:VideoTrack!
    
    weak var delegate:VideoCatalogDelegate?
    
    let coreDataContext = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
    @IBOutlet weak var collectionView:UICollectionView!
    var shouldReloadCollectionView = false
    
    deinit {

    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */
    
    // MARK: Collection View Data Source
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return fetchedResultController.sections?.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let sectionInfo = fetchedResultController.sections![section]
        return sectionInfo.numberOfObjects
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VIDEO_CELL", for: indexPath) as! VideoCell
        
        let videoTrack = fetchedResultController.object(at: indexPath)
        
        videoTrack.video.loadThumbnailImage { (anImage) in
            if anImage != nil {
                cell.imageView.image = anImage
                cell.activityIndicator.stopAnimating()
            }
        }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let selectedVideoTrack = fetchedResultController.object(at: indexPath)
//
//        let player = AVPlayer(url: videoURL)
//        let playerViewController = AVPlayerViewController()
//        playerViewController.player = player
//        present(playerViewController, animated: true) {
//            playerViewController.player!.play()
//        }
        
        //Assign the corresponding properties from selectedVideoTrack to myVideoTrack
        let alert = UIAlertController(title: "Override or duplicate?", message: "You can modify the existing video or create a new one", preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: "Override", style: UIAlertActionStyle.destructive, handler: { [unowned self] (overrideAction) in
            alert.dismiss(animated: true, completion: nil)
            
            self.delegate?.videoCatalog(didSelectPrototypeTrack: selectedVideoTrack)
            self.dismiss(animated: true, completion: nil)
        }))
        alert.addAction(UIAlertAction(title: "Copy videos", style: UIAlertActionStyle.default, handler: { [unowned self] (copyAction) in
            alert.dismiss(animated: true, completion: nil)
            
            let videoToCopy = self.myVideoTrack.video
            guard let currentLine = videoToCopy.line else {
                self.alert(nil, title: "DB", message: "Couldn't get the current line of the track's video")
                return
            }
            
            guard let context = self.myVideoTrack.managedObjectContext else {
                self.alert(nil, title: "DB", message: "Couldn't get managedObjectContext")
                return
            }
            
            let copiedVideo = currentLine.addNewVideo(context: context)
            
            if let previousPrototypeTrack = videoToCopy.prototypeTrack {
                guard copiedVideo.prototypeTrack!.copyEverythingFrom(previousPrototypeTrack) else {
                    self.alert(nil, title: "DB", message: "Couldn't copy attributes from the prototypeTrack")
                    return
                }
            }
            if let previousBackgroundTrack = videoToCopy.backgroundTrack {
                guard copiedVideo.backgroundTrack!.copyEverythingFrom(previousBackgroundTrack) else {
                    self.alert(nil, title: "DB", message: "Couldn't copy attributes from the backgroundTrack")
                    return
                }
            }
            
            self.delegate?.videoCatalog(didSelectNewVideo: copiedVideo)

        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: { (cancelAction) in
            alert.dismiss(animated: true, completion: nil)
        }))
        present(alert, animated: true, completion: nil)
        
    }
    
    // MARK: Fetched Results Controller
    var ignoreDataSourceUpdates = false

    var _fetchedResultsController: NSFetchedResultsController<VideoTrack>? = nil
    
    var fetchedResultController: NSFetchedResultsController<VideoTrack> {
        if _fetchedResultsController != nil {
            return _fetchedResultsController!
        }
        
        let fetchRequest: NSFetchRequest<VideoTrack> = VideoTrack.fetchRequest()
        
        fetchRequest.predicate = NSPredicate(format: "SELF != %@ AND isPrototype == TRUE AND hasVideoFile == TRUE",self.myVideoTrack.objectID)
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        let resultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: coreDataContext, sectionNameKeyPath: nil, cacheName: nil)
        
        resultsController.delegate = self
        _fetchedResultsController = resultsController
        
        do {
            try _fetchedResultsController!.performFetch()
        } catch {
            alert(error, title: "DB Error", message: "Could not performFetch in NSFetchedResultsController")
        }
        return _fetchedResultsController!
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        
        if ignoreDataSourceUpdates {
            return
        }
        switch (type) {
        case .insert:
            print("didChange anObject .insert (==nil)indexPath = \(indexPath?.description ?? "it was nil!") AND (+)newIndexPath = \(newIndexPath?.description ?? "it was nil!")")
            
            if indexPath == nil { // iOS 9 / Swift 2.0 BUG with running 8.4 (https://forums.developer.apple.com/thread/12184)
                if let newIndexPath = newIndexPath {
                    pendingUpdates.insertedRows.insert(newIndexPath)
                }
            }
        case .delete:
            print("didChange anObject .delete (-)indexPath = \(indexPath?.description ?? "it was nil!") AND newIndexPath = \(newIndexPath?.description ?? "it was nil!")")
            
            if let indexPath = indexPath {
                pendingUpdates.deletedRows.insert(indexPath)
            }
        case .update:
            print("didChange anObject .update *indexPath = \(indexPath?.description ?? "it was nil!") AND newIndexPath = \(newIndexPath?.description ?? "it was nil!")")
            
            if let indexPath = indexPath {
                pendingUpdates.updatedRows.insert(indexPath)
            }
        case .move:
            print("didChange anObject .move (-)indexPath = \(indexPath?.description ?? "it was nil!") AND (+)newIndexPath = \(newIndexPath?.description ?? "it was nil!")")
            
            if let newIndexPath = newIndexPath, let indexPath = indexPath {
                pendingUpdates.insertedRows.insert(newIndexPath)
                pendingUpdates.deletedRows.insert(indexPath)
            }
        }
    }
    
    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        if ignoreDataSourceUpdates {
            return
        }
        
        switch (type) {
        case .delete:
            print("didChange sectionInfo .delete atSectionIndex \(sectionIndex)")
            pendingUpdates.deletedSections.insert(sectionIndex)
        case .insert:
            print("didChange sectionInfo .insert atSectionIndex \(sectionIndex)")
            pendingUpdates.insertedSections.insert(sectionIndex)
        default:
            break
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if ignoreDataSourceUpdates {
            return
        }
        
        guard let currentCollectionView = collectionView else {
            return
        }
        
        let update = pendingUpdates
        
        currentCollectionView.performBatchUpdates({
            currentCollectionView.insertSections(update.insertedSections)
            currentCollectionView.deleteSections(update.deletedSections)
            currentCollectionView.reloadSections(update.updatedSections)
            currentCollectionView.insertItems(at: Array(update.insertedRows))
            currentCollectionView.deleteItems(at: Array(update.deletedRows))
            currentCollectionView.reloadItems(at: Array(update.updatedRows))
        }, completion: nil)
        
        pendingUpdates = PendingUpdates()
    }

    private struct PendingUpdates {
        var insertedSections = IndexSet()
        var updatedSections = IndexSet()
        var deletedSections = IndexSet()
        var insertedRows = Set<IndexPath>()
        var updatedRows = Set<IndexPath>()
        var deletedRows = Set<IndexPath>()
    }
    private var pendingUpdates = PendingUpdates()
    
    //MARK: - Actions
    @IBAction func cancelPressed(_ sender:UIBarButtonItem?) {
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func savePressed(_ sender:UIBarButtonItem?) {
        dismiss(animated: true, completion: nil)
    }

}
