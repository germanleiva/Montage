//
//  DetailLineController.swift
//  Montage
//
//  Created by Germán Leiva on 05/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit
import CoreData
import AVFoundation
import AVKit
import MBProgressHUD

class DetailLineController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, NSFetchedResultsControllerDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    let coreDataContext = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext

    var line: Line? {
        didSet {
            reloadFetchResultsController()
        }
    }
    var recordingVideo:Video?

    var longPressGesture: UILongPressGestureRecognizer!
    
    @objc func handleLongGesture(gesture: UILongPressGestureRecognizer) {
        switch(gesture.state) {
            
        case .began:
            guard let selectedIndexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView)) else {
                break
            }
            
            ignoreDataSourceUpdates = true
            collectionView.beginInteractiveMovementForItem(at: selectedIndexPath)
        case .changed:
            collectionView.updateInteractiveMovementTargetPosition(gesture.location(in: gesture.view!))
        case .ended:
            collectionView.endInteractiveMovement()
            
            //TODO is there a better way?
            //This timer tries to set ignoreDataSourceUpdates = false after the animation finish
            let deadlineTime = DispatchTime.now() + .seconds(1)
            DispatchQueue.main.asyncAfter(deadline: deadlineTime) { [unowned self] in
                self.ignoreDataSourceUpdates = false
            }
        default:
            collectionView.cancelInteractiveMovement()
            ignoreDataSourceUpdates = false
        }
    }
    
    @IBOutlet weak var collectionView:UICollectionView!
    
    @IBOutlet weak var playButton:UIBarButtonItem!
    @IBOutlet weak var compositionButton: UIBarButtonItem!
    @IBOutlet weak var recordButton: UIBarButtonItem!
    
    deinit {

    }
    
    func configureView() {
        // Update the user interface for the detail item.
        if let detail = line {
            title = "Montage"
            compositionButton.isEnabled = true
            recordButton.isEnabled = true
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        configureView()
        
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(self.handleLongGesture(gesture:)))
        collectionView.addGestureRecognizer(longPressGesture)
    }
     
    override func viewWillAppear(_ animated: Bool) {
        //TODO instead of reloading the whole collection view, we need to reload only the added cell (notification or delegate from the CameraController)
        collectionView.reloadData()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let video:Video
        switch segue.identifier {
        case "SEGUE_NEW_COMPOSITION":
            video = Video(context: coreDataContext)
            line?.addToElements(video)
            video.sequenceNumber = Int32(line?.elements?.index(of: video) ?? 0)
            
        case "SEGUE_EXISTING_COMPOSITION":
            guard let selectedIndexPath = collectionView.indexPathsForSelectedItems?.first else {
                return
            }
            video = fetchedResultController.object(at: selectedIndexPath)
        default:
            print("Ignored segue \(segue.identifier!.description)")
            return
        }
        
        let controller = segue.destination as! CameraController
        controller.videoModel = video
    }
    
    // MARK: Collection View Delegate
    
    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let origin = fetchedResultController.object(at: sourceIndexPath)
        let destination = fetchedResultController.object(at: destinationIndexPath)
        
        if let mutableElements = line?.mutableOrderedSetValue(forKey: "elements") {
            mutableElements.exchangeObject(at: Int(origin.sequenceNumber), withObjectAt: Int(destination.sequenceNumber))
            
            let temporalSequenceNumber = destination.sequenceNumber
            destination.sequenceNumber = origin.sequenceNumber
            origin.sequenceNumber = temporalSequenceNumber
            
            if let elements = line?.elements?.array as? [Video] {
                for (index,each) in elements.enumerated() {
                    assert(each.sequenceNumber == index)
                }
            }
        }
        
    }

    // MARK: Collection View Data Source
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        if line == nil {
            return 0
        }
        return fetchedResultController.sections?.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let sectionInfo = fetchedResultController.sections![section]
        return sectionInfo.numberOfObjects
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VIDEO_CELL", for: indexPath) as! VideoCell
        
        let video = fetchedResultController.object(at: indexPath)
        
        video.loadThumbnailImage { (anImage) in
            if anImage != nil {
                cell.imageView.image = anImage
                cell.activityIndicator.stopAnimating()
            }
        }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let video = fetchedResultController.object(at: indexPath)

//        guard let videoURL = video.file else {
//            return
//        }
//
//        let player = AVPlayer(url: videoURL)
//        let playerViewController = AVPlayerViewController()
//        playerViewController.player = player
//        present(playerViewController, animated: true) {
//            playerViewController.player!.play()
//        }
        performSegue(withIdentifier: "SEGUE_EXISTING_COMPOSITION", sender: nil)
    }
    
    lazy var imagePickerController: UIImagePickerController = {
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = UIImagePickerControllerSourceType.camera
        imagePickerController.mediaTypes = ["public.movie"]//UIImagePickerController.availableMediaTypes(for: UIImagePickerControllerSourceType.camera)!
        imagePickerController.videoExportPreset = AVAssetExportPresetHighestQuality
        //        imagePickerController.videoQuality = UIImagePickerControllerQualityType.typeIFrame960x540
        imagePickerController.videoQuality = UIImagePickerControllerQualityType.typeIFrame1280x720
        imagePickerController.cameraCaptureMode = .video
        imagePickerController.allowsEditing = true
        imagePickerController.delegate = self
        return imagePickerController
    }()
    
    // MARK: ImagePickerControllerDelegate
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        //Use the video that was just captured
        // info example
        //        - key : "UIImagePickerControllerMediaType"
        //        - value : public.movie
        //
        //        - key : "UIImagePickerControllerMediaURL"
        //        - value : file:///private/var/mobile/Containers/Data/Application/C8D59BEC-1C01-49FC-9DED-E642F04248BE/tmp/51879983279__A07D8DD8-7945-49B3-B2DE-0945ACB4393F.MOV
        let tempVideoURL = info[UIImagePickerControllerMediaURL] as! URL
        
        recordingVideo!.saveVideoFile(tempVideoURL) {
            self.collectionView.reloadData()
        }
        recordingVideo = nil
        picker.dismiss(animated: true) {
        }
    }
    
    func deleteRecordingVideo() {
        if let recordedVideo = self.recordingVideo {
            //when recording is cancelled, we need to delete recordingVideo from the DB
            line?.removeFromElements(recordedVideo)
            coreDataContext.delete(recordedVideo)
            do {
                try coreDataContext.save()
                self.recordingVideo = nil
            } catch {
                alert(error, title: "DB Error", message: "Could not delete cancelled recording video")
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        deleteRecordingVideo()
        picker.dismiss(animated: true) {
        }
    }

    
    // MARK: Actions
    
    @IBAction func recordTapped(_ sender:AnyObject?) {
        if line == nil{
            //preventing the app from crashing while no storyLine is created
            print("you need a storyLine")
            return
        }
    
        guard UIImagePickerController.isSourceTypeAvailable(UIImagePickerControllerSourceType.camera) else {
            alert(nil, title: "Impossible to record", message: "This device does not have an available camera")
            return
        }
        
        let newVideo = line?.addNewVideo(context: coreDataContext)
        
        do {
            try coreDataContext.save()
            recordingVideo = newVideo
        } catch let error as NSError {
            print("Could not save new video: \(error.localizedDescription)")
        }
        
        present(imagePickerController, animated: true) {
            //Something
        }
    }
    
    @IBAction func playLineTapped(_ sender:AnyObject?) {
        guard let currentLineVideos = line?.videos else {
            return
        }
        
        guard let window = UIApplication.shared.keyWindow else {
            return
        }
        
        let progressBar = MBProgressHUD.showAdded(to: window, animated: true)
        progressBar.show(animated: true)
        UIApplication.shared.beginIgnoringInteractionEvents()
        
        Line.createComposition(currentLineVideos) { (error, composition, videoComposition) in
            UIApplication.shared.endIgnoringInteractionEvents()
            progressBar.hide(animated: true)

            guard error == nil, let composition = composition, let videoComposition = videoComposition else {
                self.alert(error, title: "Create Composition Failed", message: "")
                return
            }
            
            let item = AVPlayerItem(asset: composition.copy() as! AVAsset)
            item.videoComposition = videoComposition
            let player = AVPlayer(playerItem: item)
            
            //            item.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions(rawValue: 0), context: nil)
            
            let playerVC = AVPlayerViewController()
            playerVC.player = player
            
            self.present(playerVC, animated: true, completion: { () -> Void in
                playerVC.player?.play()
            })
        }
        
    }
    
    // MARK: Fetched Results Controller
    var ignoreDataSourceUpdates = false

    func reloadFetchResultsController() {
        _fetchedResultsController = nil
    }
    var _fetchedResultsController: NSFetchedResultsController<Video>? = nil
    
    var fetchedResultController: NSFetchedResultsController<Video> {
        if _fetchedResultsController != nil {
            return _fetchedResultsController!
        }
        
        let fetchRequest: NSFetchRequest<Video> = Video.fetchRequest()
        
        fetchRequest.predicate = NSPredicate(format: "self.line == %@",self.line!)
        
        // sort by item text
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sequenceNumber", ascending: true)]
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
}

//extension DetailLineController:UICollectionViewDropDelegate {
//    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
//        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
//    }
//    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
//        guard let destinationIndexPath = coordinator.destinationIndexPath else {
//            return
//        }
//        for item in coordinator.items {
//            if let sourceIndexPath = item.sourceIndexPath {
//                collectionView.performBatchUpdates({
//                    collectionView.deleteItems(at: [sourceIndexPath])
//                    collectionView.insertItems(at: [destinationIndexPath])
//                }, completion: nil)
//            }
//        }
//    }
//}
