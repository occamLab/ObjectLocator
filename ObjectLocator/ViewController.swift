/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import ARKit
import Foundation
import SceneKit
import UIKit
import Photos
import Firebase
import FirebaseAuth
import FirebaseAuthUI
import FirebasePhoneAuthUI
import Speech

class ViewController: UIViewController, ARSCNViewDelegate, FUIAuthDelegate, SFSpeechRecognizerDelegate, AVSpeechSynthesizerDelegate {

    func authUI(_ authUI: FUIAuth, didSignInWith user: User?, error: Error?) {
        if error != nil {
            //Problem signing in
            login()
        } else {
            // successfully logged in
        }
    }
    
    // MARK: - ARKit Config Properties
    
    @IBOutlet weak var feedbackMode: UISwitch!
    var screenCenter: CGPoint?
    var trackingFallbackTimer: Timer?
    let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    let session = ARSession()
    let fallbackConfiguration = AROrientationTrackingConfiguration()
    
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
    
    let useSpeechRecognizer = true
    // used when VoiceOver is not active
    let synth = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    var isReadingAnnouncement = false
    var shouldResumeVoiceRecognition = false
    // this is to workaround a bug where VoiceOver will fail when turned on during speech recognition
    var startedVoiceOverDuringSpeechRecognition = false
    // MARK: - Virtual Object Manipulation Properties
    var currentJobUUID: String?
    var dragOnInfinitePlanesEnabled = false
    var virtualObjectManager: VirtualObjectManager!
    
    var hapticTimer: Timer!
    var snapshotTimer: Timer?

    var isLoadingObject: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.addObjectButton.isEnabled = !self.isLoadingObject
                self.restartExperienceButton.isEnabled = !self.isLoadingObject
            }
        }
    }
    
    // MARK: - Other Properties
    var textManager: TextManager!
    var restartExperienceButtonIsEnabled = true
    @IBOutlet weak var snapshotButton: UIButton!
    
    // MARK: - FireBase handles
    lazy var auth = Auth.auth()
    var authUI: FUIAuth?
    var db: Database?
    var speechRecognitionAuthorized = false
    var storageRef : StorageReference?
    var observers = [DatabaseReference?]()
    var jobs = [String: JobInfo]()
    var imageSequenceNumber = 0        // this is global for a session (not for a job)
    let uploadQueue = DispatchQueue(label: "edu.occamlab.objectlocatoruploadqueue", qos: DispatchQoS.userInitiated)
    let newTaskQueue = DispatchQueue(label: "edu.occamlab.newtaskqueue", qos: DispatchQoS.userInitiated)
    let uploadSemaphore = DispatchSemaphore(value: 1)
    let newTaskSemaphore = DispatchSemaphore(value: 1)

    // MARK: - UI Elements
    
    var spinner: UIActivityIndicatorView?

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var messagePanel: UIView!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var addObjectButton: UIButton!
    @IBOutlet weak var restartExperienceButton: UIButton!
    
    // MARK: - Queues
    
    static let serialQueue = DispatchQueue(label: "com.apple.arkitexample.serialSceneKitQueue")
	// Create instance variable for more readable access inside class
	let serialQueue: DispatchQueue = ViewController.serialQueue
	
    func handleResponse(snapshot: DataSnapshot) {
        guard var job = jobs[snapshot.key] else {
            return
        }
        
        // TODO: this is a kludge.  We probably just shouldn't be storing this info in the job id
        job.responses.removeAll()

        var objectPixelLocation: CGPoint?
        var labeledImageUUID: String?

        // TODO take the area with high local density of responses
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
        guard let pixelLocation = objectPixelLocation else {
            return
        }
        let objectToFind = job.objectToFind
        let object = VirtualObject(objectToFind: objectToFind)
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
                print(labelerResponses)
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
            // TOOD: check whether or not we need to update the job_status to a new value in Firebase
            return
        }
        // kill the job... so we don't add it twice
        job.status = JobStatus.placed
        let dbPath = "labeling_jobs/" + snapshot.key + "/job_status"
        self.db?.reference(withPath: dbPath).setValue("objectPlaced")

        jobs[snapshot.key] = nil
        self.virtualObjectManager.loadVirtualObject(object, to: worldPos!, cameraTransform: job.cameraTransforms[snapshot.key]!)
        if object.parent == nil {
            self.serialQueue.async {
                self.sceneView.scene.rootNode.addChildNode(object)
                self.announce(announcement: "Found " + objectToFind)
            }
        }
    }
    
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
    
    // MARK: - View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        auth = Auth.auth()
        authUI = FUIAuth.defaultAuthUI()
        registerAuthListener()
        db = Database.database()
        storageRef = Storage.storage().reference()
		setupUIControls()
        setupScene()
        feedbackTimer = Date()
        hapticTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: (#selector(getHapticFeedback)), userInfo: nil, repeats: true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSNotification.Name.UIApplicationDidBecomeActive,
            object: nil)
    }
    
    @objc func applicationDidBecomeActive(_ notification: NSNotification) {
        // make sure we reset this state when app is resumed
        isReadingAnnouncement = false
        cleanupVoiceRecognition()
    }

    public func startRecording() throws {
        if recognitionTask != nil {
            // can't run this twice in a row... TODO: consider disabling button
            return
        }
        if isReadingAnnouncement {
            // wait until announcement is finished
            shouldResumeVoiceRecognition = true
            return
        }
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(AVAudioSessionCategoryRecord)
        try audioSession.setMode(AVAudioSessionModeMeasurement)
        try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        let inputNode = audioEngine.inputNode
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to created a SFSpeechAudioBufferRecognitionRequest object") }
        
        // Configure request so that results are returned before audio recording is finished
        recognitionRequest.shouldReportPartialResults = true
        var segmentsProcessed = 0
        var pendingRequest = [String]()
        var jobPostingTask: DispatchWorkItem?

        // A recognition task represents a speech recognition session.
        // We keep a reference to the task so that it can be cancelled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false

            if let result = result {
                isFinal = result.isFinal
                if !isFinal {
                    for (idx, segment) in result.bestTranscription.segments[segmentsProcessed...].enumerated() {
                        if segment.substring.caseInsensitiveCompare("snap") == ComparisonResult.orderedSame && segment.confidence > 0 {
                            segmentsProcessed = idx + segmentsProcessed + 1
                            if self.snapshotButton.isEnabled {
                                self.handleSnapshot(self.snapshotButton)
                            }
                        }

                        if segment.substring.caseInsensitiveCompare("stop") == ComparisonResult.orderedSame && segment.confidence > 0 {
                            // bail and make sure we don't restart voice recognition accidentally
                            self.shouldResumeVoiceRecognition = false
                            isFinal = true
                        }

                        if segment.substring.caseInsensitiveCompare("find") == ComparisonResult.orderedSame {
                            var firstUnconfident = result.bestTranscription.segments[(idx + segmentsProcessed + 1)...].index(where: {$0.confidence == 0})
                            var allowableWords: [String]
                            if firstUnconfident == nil {
                                allowableWords = result.bestTranscription.segments[(idx + segmentsProcessed + 1)...].map({$0.substring})
                                firstUnconfident = result.bestTranscription.segments.count - 1
                            } else {
                                allowableWords = result.bestTranscription.segments[(idx + segmentsProcessed + 1)...(firstUnconfident!)].map({$0.substring})
                            }
                            self.newTaskQueue.async {
                                if allowableWords.count > pendingRequest.count {
                                    // if the task was already pending, get rid of it
                                    if jobPostingTask != nil {
                                        jobPostingTask!.cancel()
                                    }
                                    pendingRequest = allowableWords
                                    print("dispatching new job")
                                    jobPostingTask = DispatchWorkItem {
                                        let jobText = allowableWords.joined(separator:" ")
                                        pendingRequest = []
                                        segmentsProcessed = firstUnconfident!
                                        self.postNewJob(objectToFind: jobText)
                                        self.announce(announcement: "Finding " + jobText)
                                    }
                                    // wait to see if more words come in
                                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1.0, execute: jobPostingTask!)
                                }
                            }
                        }
                    }
                }
            }
            if error != nil || isFinal {
                // If we aren't planning on resuming voice recognition, then we got here due to an error, timeout, or stop request
                if !self.shouldResumeVoiceRecognition {
                    self.snapshotTimer?.invalidate()
                    self.announce(announcement: "Voice recognition stopped.", overrideRestartVoiceOver: true, overrideStartVoiceOverValue: false)
                }
            }
        }
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    // MARK: SFSpeechRecognizerDelegate
    
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            speechRecognitionAuthorized = true
        } else {
            speechRecognitionAuthorized = false
        }
    }
    
    @objc func takeSnapshot(doAnnouncement: Bool = false) {
        // make sure we have a valid frame and a valid job without a placement
        guard let currentTransform = session.currentFrame?.camera.transform, currentJobUUID != nil, jobs[currentJobUUID!] != nil else {
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
    self.jobs[self.currentJobUUID!]?.cameraTransforms[additionalImageID] = currentTransform

        // need to use an async queue here so we don't freeze the whole UI
        uploadQueue.async {
            imageRef?.putData(imageData, metadata: metaData) { (metadata, error) in
                // done uploading, somone else can go now.
                guard metadata != nil else {
                    // Uh-oh, an error occurred!
                    return
                }
                let dbPath = "labeling_jobs/" + self.currentJobUUID! + "/additional_images/" + additionalImageID
                self.db?.reference(withPath: dbPath).setValue(["imageSequenceNumber": self.imageSequenceNumber])
                self.imageSequenceNumber += 1
                // store the new AR frame so we can reference it later
            }
          }
    }
    
    @IBAction func handleSnapshot(_ sender: UIButton) {
        sender.isEnabled = false
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false, block: { _ in
            sender.isEnabled = true
        });
        takeSnapshot(doAnnouncement: true)
    }
    
    @IBAction func handleLogout(_ sender: Any) {
        // kill all observers and remove any old jobs
        _ = observers.map { $0?.removeAllObservers() }
        observers = [DatabaseReference?]()
        jobs.removeAll()
        try! Auth.auth().signOut()
    }
    
    func registerAuthListener() {
        Auth.auth().addStateDidChangeListener { auth, user in
            if user != nil {
                // User is signed in.
                print("USER LOGGED IN")
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
    
    func announce(announcement: String, overrideRestartVoiceOver: Bool = false, overrideStartVoiceOverValue: Bool = false) {
        print("isReadingAnnouncement", isReadingAnnouncement, "synth.isSpeaking", synth.isSpeaking, "UIAccessibilityIsVoiceOverRunning()", UIAccessibilityIsVoiceOverRunning())

        if isReadingAnnouncement || synth.isSpeaking {
            return
        }
        print("Announcing", announcement)
        if UIAccessibilityIsVoiceOverRunning() {
            // make sure no one else starts an announcement
            isReadingAnnouncement = true
        }
        if overrideRestartVoiceOver {
            shouldResumeVoiceRecognition = overrideStartVoiceOverValue
        } else {
            shouldResumeVoiceRecognition = recognitionTask != nil
        }
        if recognitionTask != nil {
            cleanupVoiceRecognition()
        }
        if UIAccessibilityIsVoiceOverRunning() {
            // use the VoiceOver API instead of text to speech
            if startedVoiceOverDuringSpeechRecognition {
                // Due to a bug that doesn't let VoiceOver properly setup when in record mode, we have to just give up here and avoid announcing anything.  Things will start working once the user activates an accessibility element
                isReadingAnnouncement = false
            } else {
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, announcement)
            }
        } else {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(AVAudioSessionCategoryPlayback)
                try audioSession.setActive(false, with: .notifyOthersOnDeactivation)
                let utterance = AVSpeechUtterance(string: announcement)
                utterance.rate = 0.6
                synth.speak(utterance)
            } catch {
                print("UNEXPECTED ERROR!")
            }
        }
    }
    
    func login() {
        authUI?.delegate = self
        authUI?.providers = [FUIPhoneAuth(authUI:authUI!)]
        let authViewController = authUI?.authViewController()
        self.present(authViewController!, animated: true, completion: nil)
    }

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
        if useSpeechRecognizer {
            speechRecognizer.delegate = self
            
            SFSpeechRecognizer.requestAuthorization { authStatus in
                /*
                 The callback may not be called on the main thread. Add an
                 operation to the main queue to update the record button's state.
                 */
                OperationQueue.main.addOperation {
                    switch authStatus {
                    case .authorized:
                        self.speechRecognitionAuthorized = true
                        
                    case .denied:
                        self.speechRecognitionAuthorized = false
                        
                    case .restricted:
                        self.speechRecognitionAuthorized = false
                        
                    case .notDetermined:
                        self.speechRecognitionAuthorized = false
                    }
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIAccessibilityAnnouncementDidFinish, object: nil, queue: nil) { (notification) -> Void in
            self.isReadingAnnouncement = false
            if self.shouldResumeVoiceRecognition {
                self.shouldResumeVoiceRecognition = false
                try! self.startRecording()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIAccessibilityVoiceOverStatusDidChange, object: nil, queue: nil) { (notification) -> Void in
            if self.recognitionTask != nil && UIAccessibilityIsVoiceOverRunning() {
                print("SETTING FLAG")
                self.startedVoiceOverDuringSpeechRecognition = true
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIAccessibilityElementFocused, object: nil, queue: nil) { (notification) -> Void in
            // if an element is focused during playback mode, then we have sucessfully
            // worked around a bug that prevents VoiceOver from properly starting up
            // if it is activated during a voice recognition.
            if AVAudioSession.sharedInstance().category == AVAudioSessionCategoryPlayback && AVAudioSession.sharedInstance().mode == AVAudioSessionModeDefault {
                self.startedVoiceOverDuringSpeechRecognition = false
            }
        }
        
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		session.pause()
	}
	
    // MARK: - Speech Synthesizer Delegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        if shouldResumeVoiceRecognition {
            try! startRecording()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        if shouldResumeVoiceRecognition {
            try! startRecording()
        }
    }
    
    // MARK: - Setup
    
	func setupScene() {
		virtualObjectManager = VirtualObjectManager()
        virtualObjectManager.delegate = self
		
		// set up scene view
		sceneView.setup()
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
		sceneView.delegate = self
		sceneView.session = session
		sceneView.showsStatistics = false
		
		sceneView.scene.enableEnvironmentMapWithIntensity(25, queue: serialQueue)

		DispatchQueue.main.async {
			self.screenCenter = self.sceneView.bounds.mid
		}
	}
    
    func setupUIControls() {
        textManager = TextManager(viewController: self)
        
        // Set appearance of message output panel
        messagePanel.layer.cornerRadius = 3.0
        messagePanel.clipsToBounds = true
        messagePanel.isHidden = true
        messageLabel.text = ""
    }
	
    // MARK: - ARSCNViewDelegate
	
	func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
		// If light estimation is enabled, update the intensity of the model's lights and the environment map
		if let lightEstimate = self.session.currentFrame?.lightEstimate {
			self.sceneView.scene.enableEnvironmentMapWithIntensity(lightEstimate.ambientIntensity / 40, queue: serialQueue)
		} else {
			self.sceneView.scene.enableEnvironmentMapWithIntensity(40, queue: serialQueue)
		}
	}
	
	func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
		if let planeAnchor = anchor as? ARPlaneAnchor {
			serialQueue.async {
				self.addPlane(node: node, anchor: planeAnchor)
				self.virtualObjectManager.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor, planeAnchorNode: node)
			}
		}
	}
	
	func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
		if let planeAnchor = anchor as? ARPlaneAnchor {
			serialQueue.async {
				self.updatePlane(anchor: planeAnchor)
				self.virtualObjectManager.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor, planeAnchorNode: node)
			}
		}
	}
	
	func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
		if let planeAnchor = anchor as? ARPlaneAnchor {
			serialQueue.async {
				self.removePlane(anchor: planeAnchor)
			}
		}
	}
    
	func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        textManager.showTrackingQualityInfo(for: camera.trackingState, autoHide: true)

        switch camera.trackingState {
        case .notAvailable:
            textManager.escalateFeedback(for: camera.trackingState, inSeconds: 5.0)
        case .limited:
            // After 10 seconds of limited quality, fall back to 3DOF mode.
            trackingFallbackTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false, block: { _ in
                self.session.run(self.fallbackConfiguration)
                self.textManager.showMessage("Falling back to 3DOF tracking.")
                self.trackingFallbackTimer?.invalidate()
                self.trackingFallbackTimer = nil
            })
        case .normal:
            textManager.cancelScheduledMessage(forType: .trackingStateEscalation)
            if trackingFallbackTimer != nil {
                trackingFallbackTimer!.invalidate()
                trackingFallbackTimer = nil
            }
        }
	}
	
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
	
	func sessionWasInterrupted(_ session: ARSession) {
		textManager.blurBackground()
		textManager.showAlert(title: "Session Interrupted", message: "The session will be reset after the interruption has ended.")
	}
		
	func sessionInterruptionEnded(_ session: ARSession) {
		textManager.unblurBackground()
		session.run(standardConfiguration, options: [.resetTracking, .removeExistingAnchors])
		restartExperience(self)
		textManager.showMessage("RESETTING SESSION")
	}
    
    func cleanupVoiceRecognition() {
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        try! AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
        try! AVAudioSession.sharedInstance().setMode(AVAudioSessionModeDefault)

        recognitionRequest = nil
        recognitionTask = nil
    }
    
    var feedbackTimer: Date!
    var voiceTimer = [VirtualObject: Date]()
    @objc func getHapticFeedback() {
        guard sceneView.session.currentFrame != nil && sceneView.session.currentFrame?.camera.transform != nil else {
            return
        }
        var objectsInRange = [VirtualObject]()
        var objectDistanceStrings = [String]()

        var shouldGiveFeedback: Bool = false
        let curLocation = getRealCoordinates(sceneView: sceneView)
        for virtualObject in virtualObjectManager.virtualObjects {
            let referencePosition = virtualObject.cubeNode.convertPosition(SCNVector3(x: curLocation.location.x, y: curLocation.location.y, z: curLocation.location.z), from:sceneView.scene.rootNode)
            let distanceToObject = sqrt(referencePosition.x*referencePosition.x +
                                        referencePosition.y*referencePosition.y +
                                        referencePosition.z*referencePosition.z)
            let distanceToObjectFloorPlane = sqrt(referencePosition.x*referencePosition.x + referencePosition.z*referencePosition.z)
            let virtualObjectWorldPosition = virtualObject.cubeNode.convertPosition(SCNVector3(x: 0.0, y: 0.0, z: 0.0), to:sceneView.scene.rootNode)
            // vector from camera to virtual object
            let cameraToObject = Vector3(x:virtualObjectWorldPosition.x - curLocation.location.x,
                                         y:virtualObjectWorldPosition.y - curLocation.location.y,
                                         z:virtualObjectWorldPosition.z - curLocation.location.z).normalized()
            let cameraToObjectFloorPlane = Vector3(x:cameraToObject.x,
                                                   y:0.0,
                                                   z:cameraToObject.z).normalized()
            let negZAxis = curLocation.transformMatrix*Vector3(x: 0.0, y:0.0, z: -1.0)
            let negZAxisFloorPlane = Vector3(x: negZAxis.x, y: 0.0, z: negZAxis.z).normalized()
            let angleDiff = acos(negZAxis.dot(cameraToObject))
            let angleDiffFloorPlane = acos(negZAxisFloorPlane.dot(cameraToObjectFloorPlane))

            if (feedbackMode.isOn && abs(angleDiff) < 0.2) || (!feedbackMode.isOn && abs(angleDiffFloorPlane) < 0.2) {
                shouldGiveFeedback = true
                var distanceToAnnounce: Float?
                if !feedbackMode.isOn {
                    distanceToAnnounce = distanceToObjectFloorPlane
                } else {
                    distanceToAnnounce = distanceToObject
                }
                let distanceString = String(format: "%.1f feet", (distanceToAnnounce!*100.0/2.54/12.0))
                objectsInRange.append(virtualObject)
                objectDistanceStrings.append(distanceString)
            }
        }
        if(shouldGiveFeedback) {
            let timeInterval = feedbackTimer.timeIntervalSinceNow
            if(-timeInterval > 0.4) {
                feedbackGenerator.impactOccurred()
                feedbackTimer = Date()
            }
        }
        var objectsToAnnounce = ""
        for (idx, object) in objectsInRange.enumerated() {
            let voiceInterval = voiceTimer[object]?.timeIntervalSinceNow
            if voiceInterval == nil || -voiceInterval! > 1.0 {
                // TODO: add support for only announcing this when either a switch is toggled or when a button is pressed
                objectsToAnnounce += object.objectToFind + " " + objectDistanceStrings[idx] + "\n"
                voiceTimer[object] = Date()
            }
        }
        if !objectsToAnnounce.isEmpty && recognitionTask == nil {
            announce(announcement: objectsToAnnounce)
        }
    }
    
    func getRealCoordinates(sceneView: ARSCNView) -> CurrentCoordinateInfo {
        let x = SCNMatrix4((sceneView.session.currentFrame?.camera.transform)!).m41
        let y = SCNMatrix4((sceneView.session.currentFrame?.camera.transform)!).m42
        let z = SCNMatrix4((sceneView.session.currentFrame?.camera.transform)!).m43
        
        let yaw = sceneView.session.currentFrame?.camera.eulerAngles.y
        let scn = SCNMatrix4((sceneView.session.currentFrame?.camera.transform)!)
        let transMatrix = Matrix3([scn.m11, scn.m12, scn.m13,
                                   scn.m21, scn.m22, scn.m23,
                                   scn.m31, scn.m32, scn.m33])
        
        return CurrentCoordinateInfo(LocationInfo(x: x, y: y, z: z, yaw: yaw!), transMatrix: transMatrix)
    }

    // MARK: - Planes
	
	var planes = [ARPlaneAnchor: Plane]()
    
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
		
    func updatePlane(anchor: ARPlaneAnchor) {
        if let plane = planes[anchor] {
			plane.update(anchor)
		}
	}

    func removePlane(anchor: ARPlaneAnchor) {
        virtualObjectManager.removePlane(anchor: anchor)
		if let plane = planes.removeValue(forKey: anchor) {
			plane.removeFromParentNode()
        }
    }
	
	func resetTracking() {
        // get rid of any jobs we're waiting on
        jobs.removeAll()
		session.run(standardConfiguration, options: [.resetTracking, .removeExistingAnchors])
		
		// reset timer
		if trackingFallbackTimer != nil {
			trackingFallbackTimer!.invalidate()
			trackingFallbackTimer = nil
		}
        
		textManager.scheduleMessage("FIND A SURFACE TO PLACE AN OBJECT",
		                            inSeconds: 7.5,
		                            messageType: .planeEstimation)
	}

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
        uploadQueue.async {
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
    }
    
	// MARK: - Error handling
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

extension UIViewController {
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
    
    class func removeSpinner(spinner :UIView) {
        DispatchQueue.main.async {
            spinner.removeFromSuperview()
        }
    }   
}
