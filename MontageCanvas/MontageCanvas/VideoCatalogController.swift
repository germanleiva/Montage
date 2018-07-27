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

let CELL_VIDEO_CATALOG_IDENTIFIER = "CELL_VIDEO_CATALOG_IDENTIFIER"

class VideoCatalogController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, NSFetchedResultsControllerDelegate {
    var myVideoTrack:VideoTrack!
    
    let coreDataContext = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
    @IBOutlet weak var collectionView:UICollectionView!
    var shouldReloadCollectionView = false
    
    deinit {
        for operation: BlockOperation in blockOperations {
            operation.cancel()
        }
        blockOperations.removeAll(keepingCapacity: false)
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
        
        guard let videoURL = selectedVideoTrack.loadedFileURL else {
            return
        }
        
        let player = AVPlayer(url: videoURL)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        present(playerViewController, animated: true) {
            playerViewController.player!.play()
        }
        
        //TODO: assign the corresponding properties from selectedVideoTrack to myVideoTrack
    }
    
    // MARK: Fetched Results Controller
    var _fetchedResultsController: NSFetchedResultsController<VideoTrack>? = nil
    var blockOperations: [BlockOperation] = []
    
    var fetchedResultController: NSFetchedResultsController<VideoTrack> {
        if _fetchedResultsController != nil {
            return _fetchedResultsController!
        }
        
        let fetchRequest: NSFetchRequest<VideoTrack> = VideoTrack.fetchRequest()
        
        fetchRequest.predicate = NSPredicate(format: "self != %@",self.myVideoTrack)
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        let resultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: coreDataContext, sectionNameKeyPath: nil, cacheName: nil)
        
        resultsController.delegate = self;
        _fetchedResultsController = resultsController
        
        do {
            try _fetchedResultsController!.performFetch()
        } catch {
            alert(error, title: "DB Error", message: "Could not performFetch in NSFetchedResultsController")
        }
        return _fetchedResultsController!
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        
        if type == NSFetchedResultsChangeType.insert {
            print("Insert Object: \(newIndexPath?.description ?? "no index path")")
            
            if (collectionView?.numberOfSections)! > 0 {
                
                if collectionView?.numberOfItems( inSection: newIndexPath!.section ) == 0 {
                    self.shouldReloadCollectionView = true
                } else {
                    blockOperations.append(
                        BlockOperation(block: { [weak self] in
                            if let this = self {
                                DispatchQueue.main.async {
                                    this.collectionView!.insertItems(at: [newIndexPath!])
                                }
                            }
                        })
                    )
                }
                
            } else {
                self.shouldReloadCollectionView = true
            }
        }
        else if type == NSFetchedResultsChangeType.update {
            print("Update Object: \(newIndexPath?.description ?? "no index path")")
            blockOperations.append(
                BlockOperation(block: { [weak self] in
                    if let this = self {
                        DispatchQueue.main.async {
                            
                            this.collectionView!.reloadItems(at: [indexPath!])
                        }
                    }
                })
            )
        }
        else if type == NSFetchedResultsChangeType.move {
            print("Move Object: \(newIndexPath?.description ?? "no index path")")
            
            blockOperations.append(
                BlockOperation(block: { [weak self] in
                    if let this = self {
                        DispatchQueue.main.async {
                            this.collectionView!.moveItem(at: indexPath!, to: newIndexPath!)
                        }
                    }
                })
            )
        }
        else if type == NSFetchedResultsChangeType.delete {
            print("Delete Object: \(newIndexPath?.description ?? "no index path")")
            if collectionView?.numberOfItems( inSection: indexPath!.section ) == 1 {
                self.shouldReloadCollectionView = true
            } else {
                blockOperations.append(
                    BlockOperation(block: { [weak self] in
                        if let this = self {
                            DispatchQueue.main.async {
                                this.collectionView!.deleteItems(at: [indexPath!])
                            }
                        }
                    })
                )
            }
        }
    }
    
    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        if type == NSFetchedResultsChangeType.insert {
            print("Insert Section: \(sectionIndex)")
            blockOperations.append(
                BlockOperation(block: { [weak self] in
                    if let this = self {
                        DispatchQueue.main.async {
                            this.collectionView!.insertSections(NSIndexSet(index: sectionIndex) as IndexSet)
                        }
                    }
                })
            )
        }
        else if type == NSFetchedResultsChangeType.update {
            print("Update Section: \(sectionIndex)")
            blockOperations.append(
                BlockOperation(block: { [weak self] in
                    if let this = self {
                        DispatchQueue.main.async {
                            this.collectionView!.reloadSections(NSIndexSet(index: sectionIndex) as IndexSet)
                        }
                    }
                })
            )
        }
        else if type == NSFetchedResultsChangeType.delete {
            print("Delete Section: \(sectionIndex)")
            blockOperations.append(
                BlockOperation(block: { [weak self] in
                    if let this = self {
                        DispatchQueue.main.async {
                            this.collectionView!.deleteSections(NSIndexSet(index: sectionIndex) as IndexSet)
                        }
                    }
                })
            )
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        
        // Checks if we should reload the collection view to fix a bug @ http://openradar.appspot.com/12954582
        if (self.shouldReloadCollectionView) {
            DispatchQueue.main.async {
                self.collectionView.reloadData();
            }
        } else {
            DispatchQueue.main.async {
                self.collectionView!.performBatchUpdates({ () -> Void in
                    for operation: BlockOperation in self.blockOperations {
                        operation.start()
                    }
                }, completion: { (finished) -> Void in
                    self.blockOperations.removeAll(keepingCapacity: false)
                })
            }
        }
    }

    
    //MARK: - Actions
    @IBAction func cancelPressed(_ sender:UIBarButtonItem?) {
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func savePressed(_ sender:UIBarButtonItem?) {
        dismiss(animated: true, completion: nil)
    }

}
