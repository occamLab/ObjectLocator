/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the Object Locator app.
*/

import ARKit
import Foundation
import SceneKit
import UIKit
import Photos
import Firebase
import FirebaseAuth
import FirebaseUI
import Speech
import VectorMath


/// The main ViewController class handles the following major responsibilities.
/// * Interactions with Firebase
/// * AR tracking
/// * Capturing snapshots
/// * Handling responses from crowd volunteers
class ViewController: UIViewController, ARSCNViewDelegate, FUIAuthDelegate, AVSpeechSynthesizerDelegate {
    // MARK: - Outlets to the various views that comprise the app's UI
    
    /// The switch that toggles between 2D and 3D feedback mode.  When the toggle is on, that corresponds to 3D feedback mode.
    @IBOutlet weak var feedbackMode: UISwitch!
    /// The main view that captures the AR scene and controls world tracking
    @IBOutlet var sceneView: ARSCNView!
    /// The panel that contains the messages displayed to the user
    @IBOutlet weak var messagePanel: UIView!
    /// Messages displayed to the user (e.g., related to AR session status)
    @IBOutlet weak var messageLabel: UILabel!
    /// A button that activates the interface where the user can initiate a job to find a new object
    @IBOutlet weak var addObjectButton: UIButton!
    /// A button that restarts the AR session and deletes all localized objects
    @IBOutlet weak var restartExperienceButton: UIButton!
    /// Communicates that a virtual object is in the process of being placed into the environment
    var spinner: UIActivityIndicatorView?

    // MARK: - ARKit Config Properties

    /// The ARSession that handles tracking and 3D structure estimation
    let session = ARSession()

    /// The standard ARSession configuration.  The configuration uses 6DOF tracking as
    /// well as horizontal and vertical (when available) plane detection
    let standardConfiguration: ARWorldTrackingConfiguration = {
        let configuration = ARWorldTrackingConfiguration()
        if #available(iOS 11.3, *) {
            configuration.planeDetection = [.horizontal, .vertical]
        } else {
            // Fallback on earlier versions
            configuration.planeDetection = [.horizontal]
        }
        return configuration
    }()
    
    /// A timer to coordinate restarting the ARSession if tracking has been bad for more than 10 seconds.
    var sessionRestartTimer: Timer?
    
    /// Resets (or starts) the tracking session
    func resetTracking() {
        // get rid of any jobs we're waiting on
        jobs.removeAll()
        session.run(standardConfiguration, options: [.resetTracking, .removeExistingAnchors])
        
        // reset timer
        if sessionRestartTimer != nil {
            sessionRestartTimer!.invalidate()
            sessionRestartTimer = nil
        }
        
        textManager.scheduleMessage("FIND A SURFACE TO PLACE AN OBJECT",
                                    inSeconds: 7.5,
                                    messageType: .planeEstimation)
    }
    
    // MARK: - Properties and methods for handling both haptic and speech feedback
    
    /// Communicates a message to the user via speech.  If VoiceOver is active, then VoiceOver is used
    /// to communicate the announcement, otherwise we use the AVSpeechEngine
    ///
    /// - Parameter announcement: the text to read to the user
    func announce(announcement: String) {
        if isReadingAnnouncement || synth.isSpeaking {
            return
        }
        if UIAccessibilityIsVoiceOverRunning() {
            // use the VoiceOver API instead of text to speech
            isReadingAnnouncement = true
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, announcement)
        } else {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(AVAudioSessionCategoryPlayback)
                try audioSession.setActive(false, with: .notifyOthersOnDeactivation)
                let utterance = AVSpeechUtterance(string: announcement)
                utterance.rate = 0.6
                // TODO: This seemed like a bug (not to set the isReadingAnnouncement flag), need to test.
                isReadingAnnouncement = true
                synth.speak(utterance)
            } catch {
                print("Unexpeced error announcing something using AVSpeechEngine!")
            }
        }
    }
    
    /// Keeps track of the last time the name of a particular object was announced
    var lastObjectAnnouncementTimes = [VirtualObject: Date]()

    /// When VoiceOver is not active, we use AVSpeechSynthesizer for speech feedback
    let synth = AVSpeechSynthesizer()
    /// The audioEngine is used in conjunction with the synth to enable speech feedback outside of VoiceOver
    private let audioEngine = AVAudioEngine()

    /// A Boolean flag that tracks whether or not something is currently being read to the user.  If something is
    /// being read, we avoid interrupting the announcement (TODO: we might want to interrupt for certain things
    /// (e.g., when you first find an object).
    var isReadingAnnouncement = false

    /// A timer that checks at a rate of 100 Hz whether a haptic feedback should be generated
    var hapticTimer: Timer!
    /// the last time haptic feedback was generated for the user
    var lastGeneratedHapticFeedback: Date!
    
    /// Checks if we should announce the name of an object and/or provide haptic feedback to the user.
    @objc func getHapticFeedback() {
        guard let frame = sceneView.session.currentFrame else {
            return
        }
        var objectsInRange = [VirtualObject]()
        var objectDistanceStrings = [String]()
        var shouldGiveFeedback: Bool = false

        let curLocation = getRealCoordinates(currentFrame: frame)

        for virtualObject in virtualObjectManager.virtualObjects {
            let referencePosition = virtualObject.cubeNode.convertPosition(SCNVector3(x: curLocation.location.x, y: curLocation.location.y, z: curLocation.location.z), from:sceneView.scene.rootNode)
            let distanceToObject = sqrt(referencePosition.x*referencePosition.x +
                referencePosition.y*referencePosition.y +
                referencePosition.z*referencePosition.z)
            let distanceToObjectFloorPlane = sqrt(referencePosition.x*referencePosition.x + referencePosition.z*referencePosition.z)
            let virtualObjectWorldPosition = virtualObject.cubeNode.convertPosition(SCNVector3(x: 0.0, y: 0.0, z: 0.0), to:sceneView.scene.rootNode)
            // vector from camera to virtual object
            let cameraToObject = Vector3.init(virtualObjectWorldPosition.x - curLocation.location.x,
                                              virtualObjectWorldPosition.y - curLocation.location.y,
                                              virtualObjectWorldPosition.z - curLocation.location.z).normalized()
            let cameraToObjectFloorPlane = Vector3.init(cameraToObject.x,
                                                        0.0,
                                                        cameraToObject.z).normalized()
            let negZAxis = curLocation.transformMatrix*Vector3.init(0.0, 0.0, -1.0)
            let negZAxisFloorPlane = Vector3.init(negZAxis.x, 0.0, negZAxis.z).normalized()
            let angleDiff = acos(negZAxis.dot(cameraToObject))
            let angleDiffFloorPlane = acos(negZAxisFloorPlane.dot(cameraToObjectFloorPlane))
            
            if (feedbackMode.isOn && abs(angleDiff) < 0.2) || (!feedbackMode.isOn && abs(angleDiffFloorPlane) < 0.2) {
                shouldGiveFeedback = true
                var distanceToAnnounce: Float?
                if !feedbackMode.isOn {
                    distanceToAnnounce = distanceToObjectFloorPlane
                } else {
                    distanceToAnnounce = Float(distanceToObject)
                }
                let distanceString = String(format: "%.1f feet", (distanceToAnnounce!*100.0/2.54/12.0))
                objectsInRange.append(virtualObject)
                objectDistanceStrings.append(distanceString)
            }
        }
        if(shouldGiveFeedback) {
            let timeInterval = lastGeneratedHapticFeedback.timeIntervalSinceNow
            if(-timeInterval > 0.4) {
                feedbackGenerator.impactOccurred()
                lastGeneratedHapticFeedback = Date()
            }
        }
        var objectsToAnnounce = ""
        for (idx, object) in objectsInRange.enumerated() {
            let voiceInterval = lastObjectAnnouncementTimes[object]?.timeIntervalSinceNow
            if voiceInterval == nil || -voiceInterval! > 1.0 {
                // TODO: add support for only announcing this when either a switch is toggled or when a button is pressed
                objectsToAnnounce += object.objectToFind + " " + objectDistanceStrings[idx] + "\n"
                lastObjectAnnouncementTimes[object] = Date()
            }
        }
        if !objectsToAnnounce.isEmpty {
            announce(announcement: objectsToAnnounce)
        }
    }

    /// Allows haptic feedback to be communicated to the user
    let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    
    // MARK: - Speech Synthesizer Delegate
    
    /// Called when an utterance is finished.  We implement this function so that we can keep track of
    /// whether or not an announcement is currently being read to the user.
    ///
    /// - Parameters:
    ///   - synthesizer: the synthesizer that finished the utterance
    ///   - utterance: the utterance itself
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        isReadingAnnouncement = false
    }
    
    /// Called when an utterance is canceled.  We implement this function so that we can keep track of
    /// whether or not an announcement is currently being read to the user.
    ///
    /// - Parameters:
    ///   - synthesizer: the synthesizer that finished the utterance
    ///   - utterance: the utterance itself
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        isReadingAnnouncement = false
    }

    // MARK: - Virtual Object Manipulation Properties

    /// The virtual object manager which controls which objects have been placed into the AR session
    var virtualObjectManager: VirtualObjectManager!
    /// A Boolean indicating whether an object is currently being loaded and placed in the scene
    /// This variable also automatically disables the restart experience and add object button
    /// when the flag gets set to true.
    var isLoadingObject: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.addObjectButton.isEnabled = !self.isLoadingObject
                self.restartExperienceButton.isEnabled = !self.isLoadingObject
            }
        }
    }
    
    // MARK: - Other Properties
    /// The text manager that handles showing various informational messages to the user
    var textManager: TextManager!
    /// A flag that controls whether the restart experience button is enabled (it can be disabled, for example, when the session is restarting
    var restartExperienceButtonIsEnabled = true
    
    // MARK: - Firebase handles
    
    /// A handle the Firebase realtime database
    var db: Database?
    /// A handle the Firebase storage service
    var storageRef : StorageReference?
    /// The database observers that have been created.  We maintain a list of these so that we can clear them if the user logs out
    var observers = [DatabaseReference?]()

    /// A handle the Firebase authentication service
    lazy var auth = Auth.auth()
    
    /// The authentication UI (currently handled by [FirebaseUI](https://github.com/firebase/FirebaseUI-iOS))
    var authUI: FUIAuth?
    
    /// Displays the [FirebaseUI](https://github.com/firebase/FirebaseUI-iOS) for authentication
    func login() {
        authUI?.delegate = self
        authUI?.providers = [FUIPhoneAuth(authUI:authUI!)]
        let authViewController = authUI?.authViewController()
        self.present(authViewController!, animated: true, completion: nil)
    }
    
    /// A callback function to get the results from the FirebaseUI authentication interface
    ///
    /// - Parameters:
    ///   - authUI: the auth UI that the user signed in with.
    ///   - user: the Firebase user object
    ///   - error: an error message
    func authUI(_ authUI: FUIAuth, didSignInWith user: User?, error: Error?) {
        if error != nil {
            // Problem signing in, try again
            login()
        }
    }
    
    
    /// Handles the user clicking the `logout` button
    ///
    /// - Parameter sender: the sender of this notification
    @IBAction func handleLogout(_ sender: Any) {
        // kill all observers and remove any old jobs
        _ = observers.map { $0?.removeAllObservers() }
        observers = [DatabaseReference?]()
        jobs.removeAll()
        try! Auth.auth().signOut()
    }
    
    /// Listens to the Firebase authentication service to detect if the user's authentication state changes.  We use this to detect when the user signs in and when the sign out.
    func registerAuthListener() {
        Auth.auth().addStateDidChangeListener { auth, user in
            if user != nil {
                // User is signed in.
                // reset observers
                _ = self.observers.map { $0?.removeAllObservers() }
                self.observers.removeAll()
                self.setupObservers()
            } else {
                // No user is signed in
                self.login()
            }
        }
    }

    /// Setup the Firebase realtime database observers to pickup any new responses from the crowd volunteers
    func setupObservers() {
        guard let user = auth.currentUser else {
            return
        }
        let responsePathRef = Database.database().reference(withPath: "responses/" + user.uid)
        responsePathRef.observe(.childChanged) { (snapshot) -> Void in
            self.handleResponse(snapshot: snapshot)
        }
        responsePathRef.observe(.childAdded) { (snapshot) -> Void in
            self.handleResponse(snapshot: snapshot)
        }
        observers.append(responsePathRef)
    }
    
    // MARK: - Properties and methods that control mappping to and from Firebase and AR
    /// The jobs in process
    var jobs = [String: JobInfo]()
    
    /// Post a new job with the specified name
    ///
    /// - Parameter objectToFind: the name of the object to find
    func postNewJob(objectToFind: String) {
        guard let currentCameraTransform = session.currentFrame?.camera.transform, let user = auth.currentUser else {
            return
        }
        let sceneImage = self.sceneView.snapshot()
        let imageData:Data? = UIImageJPEGRepresentation(sceneImage, 0.8)!
        let parameters: NSDictionary = [
            "object_to_find": objectToFind,
            "creation_timestamp": ServerValue.timestamp(),
            "requesting_user": user.uid,
            "job_status": "waitingForFirstResponse"
        ]
        // dispatch to the backend for labeling
        let jobUUID = UUID().uuidString
        self.currentJobUUID = jobUUID       // keep track so we can add additional snapshots
        let imageRef = self.storageRef?.child(jobUUID + ".jpg")
        let metaData = StorageMetadata()
        metaData.contentType = "image/jpg"
        // upload the image to Firebase storage and setup auto snapshotting
        imageRef?.putData(imageData!, metadata: metaData) { (metadata, error) in
            guard metadata != nil else {
                // Uh-oh, an error occurred!
                return
            }
            let dbPath = "labeling_jobs/" + jobUUID
            self.db?.reference(withPath: dbPath).setValue(parameters)
            self.jobs[jobUUID] = JobInfo(cameraTransforms: [jobUUID: currentCameraTransform], sceneImage: sceneImage, objectToFind: objectToFind)
            self.snapshotTimer?.invalidate()
            self.snapshotTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: (#selector(self.takeSnapshot)), userInfo: nil, repeats: true)
        }
    }

    /// The image sequence number that allows any clients to order the images captured chronologically
    /// NOTE: this property is global for *all jobs* (i.e. it doesn't reset when a new job is added)
    var imageSequenceNumber = 0
    /// The UUID of the most recently created job.  This UUID is used to route newly captured snapshots to the
    /// appropriate place.  This means that new snapshots are only added to this most recent job.
    /// TODO: revisit whether images should be routed to older jobs.
    var currentJobUUID: String?
    
    /// Take a snapshot of the scene and add it to most recently created job.
    ///
    /// - Parameter doAnnouncement: true if the system should announce that it has taken a snapshot
    @objc func takeSnapshot(doAnnouncement: Bool = false) {
        // make sure we have a valid frame and a valid job without a placement
        guard let currentTransform = session.currentFrame?.camera.transform, let jobUUID = currentJobUUID, var job = jobs[jobUUID] else {
            return
        }
        
        let sceneImage = self.sceneView.snapshot()
        let imageData:Data = UIImageJPEGRepresentation(sceneImage, 0.8)!
        let additionalImageID = UUID().uuidString
        let imageRef = self.storageRef?.child(additionalImageID + ".jpg")
        let metaData = StorageMetadata()
        if doAnnouncement {
            announce(announcement: "Snapshot")
        }
        metaData.contentType = "image/jpg"
        // store the camera transforms so we know how to map any responses we receive
        job.cameraTransforms[additionalImageID] = currentTransform
        
        // need to use an async queue here so we don't freeze the whole UI
        imageRef?.putData(imageData, metadata: metaData) { (metadata, error) in
            // done uploading, somone else can go now.
            guard metadata != nil else {
                // Uh-oh, an error occurred!
                return
            }
            let dbPath = "labeling_jobs/" + self.currentJobUUID! + "/additional_images/" + additionalImageID
            self.db?.reference(withPath: dbPath).setValue(["imageSequenceNumber": self.imageSequenceNumber])
            self.imageSequenceNumber += 1
        }
    }

    /// The timer that allows for auto snapshotting of the environment when a job is active
    var snapshotTimer: Timer?
    /// The function that handles any new localizations generated by the crowd volunteers.  This function performs
    /// the following steps.
    /// * Parse the data from Firebase to determine which image was labeled, who did the localization, and extract the pixel location of the localization
    /// * If this is the first response from a user, attempt to map the pixel location to 3D using the planes detected by the ARSession
    /// * If unable to localize the object using the method above, wait for a second response
    /// * Once two responses are generated by the same user, use triangulation to compute a 3D position.
    ///
    /// - Parameter snapshot: this will be a child of responses/{user.uid} corresponding to a particular job.  It will have all of the responses that have currently been generated for this particular job (not just the latest one).
    func handleResponse(snapshot: DataSnapshot) {
        guard var job = jobs[snapshot.key] else {
            return
        }
        
        // Throw a way any responses we've processed thus far and reparse them.
        // TODO: this is a kludge.  We probably just shouldn't be storing this info in the job id
        job.responses.removeAll()
        
        // These variables hold the pixel location and the imageUUID that we will try to map to 3D
        var objectPixelLocation: CGPoint?
        var labeledImageUUID: String?
        
        // TODO: take the area with high local density of responses
        for child in snapshot.children.allObjects as! [DataSnapshot] {
            let values = child.value as! [String: Any]
            objectPixelLocation = CGPoint(x: Double(self.sceneView.bounds.width)*(values["x"] as! Double)/Double(job.sceneImage.size.width), y: Double(self.sceneView.bounds.height)*(values["y"] as! Double)/Double(job.sceneImage.size.height))
            labeledImageUUID = values["imageUUID"] as? String
            if objectPixelLocation != nil && labeledImageUUID != nil {
                let firstUnderscore = child.key.index(of: "_") ?? child.key.endIndex
                let labelerID = child.key[..<firstUnderscore]
                job.responses.append(JobResponse(labelerID: String(labelerID), imageUUID: labeledImageUUID!, pixelLocation: objectPixelLocation!))
            }
        }
        // For now, we are just using the last localization response
        guard let pixelLocation = objectPixelLocation else {
            return
        }
        // Create a new virtual object with a label that corresponds to the object name
        let object = VirtualObject(objectToFind: job.objectToFind)
        var (worldPos, _, _) = self.virtualObjectManager.worldPositionFromScreenPosition(pixelLocation,
                                                                                         in: self.sceneView,
                                                                                         frame_transform: job.cameraTransforms[labeledImageUUID!],
                                                                                         objectPos: nil)
        if worldPos == nil {
            var labelerResponses = [String: [JobResponse]]()
            var twoResponsesFromSameUser : [JobResponse]? = nil
            for response in job.responses {
                if labelerResponses[response.labelerID] == nil {
                    labelerResponses[response.labelerID] = [response]
                } else {
                    labelerResponses[response.labelerID]!.append(response)
                    twoResponsesFromSameUser = labelerResponses[response.labelerID]
                    break
                }
            }
            guard let triangulationJobs = twoResponsesFromSameUser else {
                // wait for more responses
                job.status = JobStatus.waitingForAdditionalResponse
                let dbPath = "labeling_jobs/" + snapshot.key + "/job_status"
                self.db?.reference(withPath: dbPath).setValue("waitingForAdditionalReponse")
                return
            }
            // try to do stereo matching (just use the first two matches for now)
            (worldPos, _, _) = self.virtualObjectManager.worldPositionFromStereoScreenPosition(pixel_location_1: triangulationJobs[0].pixelLocation,
                                                                                               pixel_location_2: triangulationJobs[1].pixelLocation,
                                                                                               in: self.sceneView,
                                                                                               frame_transform_1: job.cameraTransforms[triangulationJobs[0].imageUUID],
                                                                                               frame_transform_2: job.cameraTransforms[triangulationJobs[1].imageUUID],
                                                                                               objectPos: nil)
        }
        if worldPos == nil {
            // give up
            job.status = JobStatus.failed
            jobs[snapshot.key] = nil
            // TOOD: we might want to consider updating the job_status to a new value in Firebase (e.g., failed)
            return
        }
        // kill the job... so we don't add it twice
        job.status = JobStatus.placed
        let dbPath = "labeling_jobs/" + snapshot.key + "/job_status"
        self.db?.reference(withPath: dbPath).setValue("objectPlaced")
        jobs[snapshot.key] = nil
        
        // Next, place the cube with the floating label of the job into the scene and announce that the object has been found to the user
        self.virtualObjectManager.loadVirtualObject(object, to: worldPos!, cameraTransform: job.cameraTransforms[snapshot.key]!)
        if object.parent == nil {
            self.serialQueue.async {
                self.sceneView.scene.rootNode.addChildNode(object)
                self.announce(announcement: "Found " + job.objectToFind)
            }
        }
    }
    
    // MARK: - Queues

    /// The serial queue handles computationally intensive rendering of various AR propreties
    static let serialQueue = DispatchQueue(label: "com.apple.arkitexample.serialSceneKitQueue")
	/// An alias of the static variable "serialQueue" to allow for more readable access inside class
	let serialQueue: DispatchQueue = ViewController.serialQueue
//    /// The queue for uploading images to Firebase storage
//    let uploadQueue = DispatchQueue(label: "edu.occamlab.objectlocatoruploadqueue", qos: DispatchQoS.userInitiated)


    // MARK: - View Controller Life Cycle
    
    /// Once the view is loaded properties, timers, and various handles are created.
    override func viewDidLoad() {
        super.viewDidLoad()
        auth = Auth.auth()
        authUI = FUIAuth.defaultAuthUI()
        registerAuthListener()
        db = Database.database()
        storageRef = Storage.storage().reference()
		setupUIControls()
        setupScene()
        lastGeneratedHapticFeedback = Date()
        hapticTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: (#selector(getHapticFeedback)), userInfo: nil, repeats: true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSNotification.Name.UIApplicationDidBecomeActive,
            object: nil)
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIAccessibilityVoiceOverStatusDidChange, object: nil, queue: nil) { (notification) -> Void in
            self.isReadingAnnouncement = false
        }
    }
    
    /// Currently all this does is reset the property that tracks whether an announcement is being read.
    ///
    /// - Parameter notification: the notification that caused the app to become active
    @objc func applicationDidBecomeActive(_ notification: NSNotification) {
        // make sure we reset this state when app is resumed
        isReadingAnnouncement = false
    }


    /// Called when the view appears on the screen.  Above what is done by the super class, this function does the following.
    /// * Display an error message if the user's device doesn't support 6DOF tracking (e.g., for phones older than the iPhone 6S)
    /// * Restart the tracking session
    /// * Add a listener for the end of any VoiceOver announcements so we can note this.
    ///
    /// - Parameter animated: whether or not to animate
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
        // Prevent the screen from being dimmed after a while.
		UIApplication.shared.isIdleTimerDisabled = true
		
		if ARWorldTrackingConfiguration.isSupported {
			// Start the ARSession.
			resetTracking()
        } else {
			// This device does not support 6DOF world tracking.
			let sessionErrorMsg = "This app requires world tracking. World tracking is only available on iOS devices with A9 processor or newer. " +
			"Please quit the application."
			displayErrorMessage(title: "Unsupported platform", message: sessionErrorMsg, allowRestart: false)
		}
        synth.delegate = self
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIAccessibilityAnnouncementDidFinish, object: nil, queue: nil) { (notification) -> Void in
            self.isReadingAnnouncement = false
        }
	}
	
    /// Above and beyond what the super class does, this function will pause the ARSession
    ///
    /// - Parameter animated: whether to animate the disappearance
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		session.pause()
	}
    
    // MARK: - Setup
    
    /// Setup the ARSCNView by creating the object manager and setting various ARSCNView properties.
	func setupScene() {
		virtualObjectManager = VirtualObjectManager()
        virtualObjectManager.delegate = self
		
		// set up scene view
		sceneView.setup()
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
		sceneView.delegate = self
		sceneView.session = session
		sceneView.showsStatistics = false
    }
    
    /// Setup the text manager UI control
    func setupUIControls() {
        textManager = TextManager(viewController: self)
        
        // Set appearance of message output panel
        messagePanel.layer.cornerRadius = 3.0
        messagePanel.clipsToBounds = true
        messagePanel.isHidden = true
        messageLabel.text = ""
    }
	
    // MARK: - ARSCNViewDelegate
	
    /// Responds to renderer updates to do fancy things like dynamic lighting (currently we aren't doing anything like this)
    ///
    /// - Parameters:
    ///   - renderer: the renderer
    ///   - time: the udpate time
	func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
	}
	
    /// Listen for new anchors that have been added to the ARSCNView.
    /// Currently, all we care about is whether the new node corresponds to a plane.  We use the detected
    /// planes to try to map 2D pixel locations to 3D locations.
    ///
    /// - Parameters:
    ///   - renderer: the renderer
    ///   - node: the node added to the scene
    ///   - anchor: any anchor (if applicable)
	func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
		if let planeAnchor = anchor as? ARPlaneAnchor {
			serialQueue.async {
				self.addPlane(node: node, anchor: planeAnchor)
				self.virtualObjectManager.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor, planeAnchorNode: node)
			}
		}
	}

    /// Listen for anchors that have been updated in the ARSCNView.
    /// Currently, all we care about is whether the updated node corresponds to a plane.  We use the detected
    /// planes to try to map 2D pixel locations to 3D locations.
    ///
    /// - Parameters:
    ///   - renderer: the renderer
    ///   - node: the node updated in the scene
    ///   - anchor: any anchor (if applicable)
	func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
		if let planeAnchor = anchor as? ARPlaneAnchor {
			serialQueue.async {
				self.updatePlane(anchor: planeAnchor)
				self.virtualObjectManager.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor, planeAnchorNode: node)
			}
		}
	}
	
    /// Listen for anchors that have been removed from the ARSCNView.
    /// Currently, all we care about is whether the removed node corresponds to a plane.  We use the detected
    /// planes to try to map 2D pixel locations to 3D locations.
    ///
    /// - Parameters:
    ///   - renderer: the renderer
    ///   - node: the node removed from the scene
    ///   - anchor: any anchor (if applicable)
	func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
		if let planeAnchor = anchor as? ARPlaneAnchor {
			serialQueue.async {
				self.removePlane(anchor: planeAnchor)
			}
		}
	}
    
    /// Listen for any state changes to the ARSession.
    /// This is useful for doing things like restarting a session after bad tracking and communicating warning messages to the user.
    ///
    /// - Parameters:
    ///   - session: the session object itself
    ///   - camera: the camera object
	func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        textManager.showTrackingQualityInfo(for: camera.trackingState, autoHide: true)

        switch camera.trackingState {
        case .notAvailable:
            textManager.escalateFeedback(for: camera.trackingState, inSeconds: 5.0)
        case .limited:
            // After 10 seconds of limited quality, restart the session
            sessionRestartTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false, block: { _ in
                self.textManager.showMessage("Tracking is bad, restarting session.")
                self.restartExperience(self)
            })
        case .normal:
            textManager.cancelScheduledMessage(forType: .trackingStateEscalation)
            if sessionRestartTimer != nil {
                sessionRestartTimer!.invalidate()
                sessionRestartTimer = nil
            }
        }
	}
	
    /// Listen for any catastrophic failures of the ARSession.  These are communicated to the user via an alert, and the session is restarted.
    ///
    /// - Parameters:
    ///   - session: the session object itself
    ///   - camera: the camera object
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard let arError = error as? ARError else { return }

        let nsError = error as NSError
		var sessionErrorMsg = "\(nsError.localizedDescription) \(nsError.localizedFailureReason ?? "")"
		if let recoveryOptions = nsError.localizedRecoveryOptions {
			for option in recoveryOptions {
				sessionErrorMsg.append("\(option).")
			}
		}

        let isRecoverable = (arError.code == .worldTrackingFailed)
		if isRecoverable {
			sessionErrorMsg += "\nYou can try resetting the session or quit the application."
		} else {
			sessionErrorMsg += "\nThis is an unrecoverable error that requires to quit the application."
		}
		
		displayErrorMessage(title: "We're sorry!", message: sessionErrorMsg, allowRestart: isRecoverable)
	}
	
    /// Called when the session was interrupted.  Currently we just set blue the image.
    ///
    /// - Parameter session: the session object
	func sessionWasInterrupted(_ session: ARSession) {
		textManager.blurBackground()
		textManager.showAlert(title: "Session Interrupted", message: "The session will be reset after the interruption has ended.")
	}
		
    /// Called when the session interruption has finished.  Currently we restart the ARSession at this point (since tracking state is likely not useful at this point).
    /// TODO: With ARKit2, we could probably recover from this
    ///
    /// - Parameter session: the session object
	func sessionInterruptionEnded(_ session: ARSession) {
		textManager.unblurBackground()
		session.run(standardConfiguration, options: [.resetTracking, .removeExistingAnchors])
		restartExperience(self)
		textManager.showMessage("RESETTING SESSION")
	}
    
    /// Gets the x, y, z, yaw and transformation matrix corresponding to the current pose of the camera
    ///
    /// - Parameter sceneView: the scene view (used for looking up the camera transform)
    /// - Returns: the camera's position as a CurrentCoordinateInfo object
    private func getRealCoordinates(currentFrame: ARFrame) -> CurrentCoordinateInfo {
        let x = SCNMatrix4(currentFrame.camera.transform).m41
        let y = SCNMatrix4(currentFrame.camera.transform).m42
        let z = SCNMatrix4(currentFrame.camera.transform).m43
        
        let yaw = currentFrame.camera.eulerAngles.y
        let scn = SCNMatrix4(currentFrame.camera.transform)
        let transMatrix = Matrix3([scn.m11, scn.m12, scn.m13,
                                   scn.m21, scn.m22, scn.m23,
                                   scn.m31, scn.m32, scn.m33])
        
        return CurrentCoordinateInfo(LocationInfo(x: x, y: y, z: z, yaw: yaw), transMatrix: transMatrix)
    }

    // MARK: - Planes
	
    /// a dictionary that maps from ARPlaneAnchors to Plane objects (Plane objects integrate a SCNNode with the plane anchor)
	var planes = [ARPlaneAnchor: Plane]()
    
    /// Adds a new plane to the virtual object manager
    ///
    /// - Parameters:
    ///   - node: the scene node corresponding to the plane
    ///   - anchor: the plane anchor itself
    func addPlane(node: SCNNode, anchor: ARPlaneAnchor) {
		let plane = Plane(anchor)
        virtualObjectManager.addPlane(plane: plane)
		planes[anchor] = plane
		node.addChildNode(plane)
		
		textManager.cancelScheduledMessage(forType: .planeEstimation)
		textManager.showMessage("SURFACE DETECTED")
		if virtualObjectManager.virtualObjects.isEmpty {
			textManager.scheduleMessage("TAP + TO PLACE AN OBJECT", inSeconds: 7.5, messageType: .contentPlacement)
		}
	}

    /// Update a plane in the virtual object manager
    ///
    /// - Parameters:
    ///   - anchor: the plane anchor itself
    func updatePlane(anchor: ARPlaneAnchor) {
        if let plane = planes[anchor] {
			plane.update(anchor)
		}
	}

    /// Remove a plane in the virtual object manager
    ///
    /// - Parameters:
    ///   - anchor: the plane anchor itself
    func removePlane(anchor: ARPlaneAnchor) {
        virtualObjectManager.removePlane(anchor: anchor)
		if let plane = planes.removeValue(forKey: anchor) {
			plane.removeFromParentNode()
        }
    }

	// MARK: - Error handling

    /// Display an error message as an alert.  if allowedRestart is true, the user will
    /// have the option of restarting the experience.
    ///
    /// - Parameters:
    ///   - title: the title of the alert
    ///   - message: the message body for the alert
    ///   - allowRestart: true iff we should allow the user to restart the experience
	func displayErrorMessage(title: String, message: String, allowRestart: Bool = false) {
		// Blur the background.
		textManager.blurBackground()
		
		if allowRestart {
			// Present an alert informing about the error that has occurred.
			let restartAction = UIAlertAction(title: "Reset", style: .default) { _ in
				self.textManager.unblurBackground()
				self.restartExperience(self)
			}
			textManager.showAlert(title: title, message: message, actions: [restartAction])
		} else {
			textManager.showAlert(title: title, message: message, actions: [])
		}
	}
    
}

// MARK: - Extensions to UIViewController for adding and removing a spinner that shows that a long running operation is in progress
extension UIViewController {
    /// Display a spinner on top of the current view
    ///
    /// - Parameter onView: the view to display the spinner on
    /// - Returns: the created spinner view
    class func displaySpinner(onView : UIView) -> UIView {
        let spinnerView = UIView.init(frame: onView.bounds)
        spinnerView.backgroundColor = UIColor.init(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)
        let ai = UIActivityIndicatorView.init(activityIndicatorStyle: .whiteLarge)
        ai.startAnimating()
        ai.center = spinnerView.center
        
        DispatchQueue.main.async {
            spinnerView.addSubview(ai)
            onView.addSubview(spinnerView)
        }
        
        return spinnerView
    }
    
    /// Remove the spinner view from its super view
    ///
    /// - Parameter spinner: the spinner view to remove
    class func removeSpinner(spinner :UIView) {
        DispatchQueue.main.async {
            spinner.removeFromSuperview()
        }
    }   
}
