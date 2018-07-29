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

    var shouldReloadCollectionView = false
    var line: Line? {
        didSet {
            reloadFetchResultsController()
        }
    }
    var recordingVideo:Video?
    
    @IBOutlet weak var collectionView:UICollectionView!
    
    @IBOutlet weak var playButton:UIBarButtonItem!
    @IBOutlet weak var compositionButton: UIBarButtonItem!
    @IBOutlet weak var recordButton: UIBarButtonItem!
    
    deinit {
        for operation: BlockOperation in blockOperations {
            operation.cancel()
        }
        blockOperations.removeAll(keepingCapacity: false)
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
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "DELETE_RECORDING_VIDEO"), object: nil, queue: OperationQueue.main) { (notif) in
            self.deleteRecordingVideo()
        }
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
            recordingVideo = video
            
            do {
                try coreDataContext.save()
            } catch let error as NSError {
                
            }
            
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
        
        let newVideo = Video(context: coreDataContext)
        line?.addToElements(newVideo)
        newVideo.sequenceNumber = Int32(line?.elements?.index(of: newVideo) ?? 0)
        
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
        
        Line.createComposition(currentLineVideos) { (composition, videoComposition) in
            let item = AVPlayerItem(asset: composition.copy() as! AVAsset)
            item.videoComposition = videoComposition
            let player = AVPlayer(playerItem: item)
            
//            item.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions(rawValue: 0), context: nil)
            
            let playerVC = AVPlayerViewController()
            playerVC.player = player
            
            UIApplication.shared.endIgnoringInteractionEvents()
            progressBar.hide(animated: true)
            self.present(playerVC, animated: true, completion: { () -> Void in
                playerVC.player?.play()
            })
        }
        
    }
    
    // MARK: Fetched Results Controller
    func reloadFetchResultsController() {
        _fetchedResultsController = nil
    }
    var _fetchedResultsController: NSFetchedResultsController<Video>? = nil
    var blockOperations: [BlockOperation] = []
    
    var fetchedResultController: NSFetchedResultsController<Video> {
        if _fetchedResultsController != nil {
            return _fetchedResultsController!
        }
        
        let fetchRequest: NSFetchRequest<Video> = Video.fetchRequest()
        
        fetchRequest.predicate = NSPredicate(format: "self.line == %@",self.line!)
        
        // sort by item text
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sequenceNumber", ascending: true)]
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
            print("Insert Object: \(newIndexPath)")
            
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
            print("Update Object: \(indexPath)")
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
            print("Move Object: \(indexPath)")
            
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
            print("Delete Object: \(indexPath)")
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

}

