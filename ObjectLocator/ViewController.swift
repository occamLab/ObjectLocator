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

// TODO: move this to its own file
public struct CurrentCoordinateInfo {
    //  Struct to store location and transform information
    public var location: LocationInfo
    public var transformMatrix: Matrix3 = Matrix3.identity
    
    public init(_ location: LocationInfo, transMatrix: Matrix3) {
        self.location = location
        self.transformMatrix = transMatrix
    }
    
    public init(_ location: LocationInfo) {
        self.location = location
    }
}

public struct LocationInfo {
    //  Struct to store position information and yaw
    public var x: Float
    public var y: Float
    public var z: Float
    public var yaw: Float
    
    public init(x: Float, y: Float, z: Float, yaw: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.yaw = yaw
    }
}

class ViewController: UIViewController, ARSCNViewDelegate, FUIAuthDelegate {

    func authUI(_ authUI: FUIAuth, didSignInWith user: User?, error: Error?) {
        print("got a delegate auth callback")
        if error != nil {
            //Problem signing in
            login()
        }else {
            //User is in! Here is where we code after signing in
            
        }
    }
    
    // MARK: - ARKit Config Properties
    
    var screenCenter: CGPoint?
    var trackingFallbackTimer: Timer?
    let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    let session = ARSession()
    let fallbackConfiguration = ARSessionConfiguration()
    
    let standardConfiguration: ARWorldTrackingSessionConfiguration = {
        let configuration = ARWorldTrackingSessionConfiguration()
        configuration.planeDetection = .horizontal
        return configuration
    }()
    
    // MARK: - Virtual Object Manipulation Properties
    
    var dragOnInfinitePlanesEnabled = false
    var virtualObjectManager: VirtualObjectManager!
    
    var hapticTimer: Timer!
    
    var isLoadingObject: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.settingsButton.isEnabled = !self.isLoadingObject
                self.addObjectButton.isEnabled = !self.isLoadingObject
                self.restartExperienceButton.isEnabled = !self.isLoadingObject
            }
        }
    }
    
    // MARK: - Other Properties
    
    var textManager: TextManager!
    var restartExperienceButtonIsEnabled = true
    
    // MARK: - FireBase handles
    var auth: Auth?
    var authUI: FUIAuth?
    var ref: DatabaseReference?

    // MARK: - UI Elements
    
    var spinner: UIActivityIndicatorView?

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var messagePanel: UIView!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var addObjectButton: UIButton!
    @IBOutlet weak var restartExperienceButton: UIButton!
    
    // MARK: - Queues
    
    static let serialQueue = DispatchQueue(label: "com.apple.arkitexample.serialSceneKitQueue")
	// Create instance variable for more readable access inside class
	let serialQueue: DispatchQueue = ViewController.serialQueue
	
    // MARK: - View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        auth = Auth.auth()
        authUI = FUIAuth.defaultAuthUI()
        ref = Database.database().reference()
        // TODO: need to make a signout button with the code below
        //try! Auth.auth().signOut()
        checkLoggedIn()

        Setting.registerDefaults()
		setupUIControls()
        setupScene()
        feedbackTimer = Date()
        hapticTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: (#selector(getHapticFeedback)), userInfo: nil, repeats: true)
    }
    
    func checkLoggedIn() {
        Auth.auth().addStateDidChangeListener { auth, user in
            print("In the check logged in function")
            if user != nil {
                // User is signed in.
            } else {
                // No user is signed in.
                self.login()
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
		
		if ARWorldTrackingSessionConfiguration.isSupported {
			// Start the ARSession.
			resetTracking()
		} else {
			// This device does not support 6DOF world tracking.
			let sessionErrorMsg = "This app requires world tracking. World tracking is only available on iOS devices with A9 processor or newer. " +
			"Please quit the application."
			displayErrorMessage(title: "Unsupported platform", message: sessionErrorMsg, allowRestart: false)
		}
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		session.pause()
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

    
    var feedbackTimer: Date!
    @objc func getHapticFeedback() {
        guard sceneView.session.currentFrame != nil && sceneView.session.currentFrame?.camera.transform != nil else {
            return
        }
        var shouldGiveFeedback: Bool = false
        let curLocation = getRealCoordinates(sceneView: sceneView)
        for virtualObject in virtualObjectManager.virtualObjects {
            let referencePosition = virtualObject.referenceNode.convertPosition(SCNVector3(x: curLocation.location.x, y: curLocation.location.y, z: curLocation.location.z), from:sceneView.scene.rootNode)
            let distanceToObject = sqrt(referencePosition.x*referencePosition.x +
                                        referencePosition.y*referencePosition.y +
                                        referencePosition.z*referencePosition.z)
            let virtualObjectWorldPosition = virtualObject.referenceNode.convertPosition(SCNVector3(x: 0.0, y: 0.0, z: 0.0), to:sceneView.scene.rootNode)
            // vector from camera to virtual object
            let cameraToObject = Vector3(x:virtualObjectWorldPosition.x - curLocation.location.x,
                                         y:virtualObjectWorldPosition.y - curLocation.location.y,
                                         z:virtualObjectWorldPosition.z - curLocation.location.z).normalized()

            let negZAxis = curLocation.transformMatrix*Vector3(x: 0.0, y:0.0, z: -1.0)
            let angleDiff = acos(negZAxis.dot(cameraToObject))
            if abs(angleDiff) < 0.2 {
                shouldGiveFeedback = true
            }
        }
        // need to fix this let directionToNextKeypoint = getDirectionToNextKeypoint(currentLocation: curLocation)
        if(shouldGiveFeedback) {
            let timeInterval = feedbackTimer.timeIntervalSinceNow
            if(-timeInterval > 0.4) {
                feedbackGenerator.impactOccurred()
                feedbackTimer = Date()
            }
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
	
    // MARK: - Gesture Recognizers
	
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		virtualObjectManager.reactToTouchesBegan(touches, with: event, in: self.sceneView)
	}
	
	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
		virtualObjectManager.reactToTouchesMoved(touches, with: event)
	}
	
	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		if virtualObjectManager.virtualObjects.isEmpty {
			chooseObject(addObjectButton)
			return
		}
		virtualObjectManager.reactToTouchesEnded(touches, with: event)
	}
	
	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		virtualObjectManager.reactToTouchesCancelled(touches, with: event)
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
