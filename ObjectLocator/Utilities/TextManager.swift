/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Utility class for showing messages above the AR view.
*/

import Foundation
import ARKit

/// The message type (for informational messages to the user)
///
/// - trackingStateEscalation: tracking state has been bad for a while
/// - planeEstimation: a new plane has been found
/// - contentPlacement: new content has been placed
enum MessageType {
    /// tracking state has been bad for a while
	case trackingStateEscalation
    /// a new plane has been found
	case planeEstimation
    /// new content has been placed
	case contentPlacement
}

extension ARCamera.TrackingState {
    /// A mapping between the ARKit error code and a human presentable message
    var presentationString: String {
        switch self {
        case .notAvailable:
            return "TRACKING UNAVAILABLE"
        case .normal:
            return "TRACKING NORMAL"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return "TRACKING LIMITED\nToo much camera movement"
            case .insufficientFeatures:
                return "TRACKING LIMITED\nNot enough surface detail"
            case .initializing:
                return "Initializing AR Session"
            case .relocalizing:
                return "Relocalizing"
            }
        }
    }
}

/// A class that controls showing informational messages about the state of the ARSession to the user
class TextManager {
    
    // MARK: - Properties
    
    /// A handle to the view controller that embeds this text manager
    private var viewController: ViewController!
    
    /// Timer for hiding messages
    private var messageHideTimer: Timer?
    
    // MARK: - Timers for showing scheduled messages
    
    /// A timer for showing that a plane has been found
    private var planeEstimationMessageTimer: Timer?

    /// A timer to control when a content placed message is shown
    private var contentPlacementMessageTimer: Timer?
    
    /// Timer for tracking state escalation
    private var trackingStateFeedbackEscalationTimer: Timer?
    
    /// Blur effect parameter (TOOD: figure out what this does)
    let blurEffectViewTag = 100
    
    /// True if no more messages should be scheduled
    var schedulingMessagesBlocked = false

    /// The Alert controller (e.g., presented when the ARSession dies)
    var alertController: UIAlertController?
    
    // MARK: - Initialization
    
    /// Initialize a new text manager
    ///
    /// - Parameter viewController: the view controller that embeds this text manager
	init(viewController: ViewController) {
		self.viewController = viewController
	}
    
    // MARK: - Message Handling
	
    /// Show a message
    ///
    /// - Parameters:
    ///   - text: the text to display
    ///   - autoHide: true if we should autohide the message after displaying, false otherwise
	func showMessage(_ text: String, autoHide: Bool = true) {
		DispatchQueue.main.async {
            if UIAccessibilityIsVoiceOverRunning() {
                // send to VoiceOver
                self.viewController.announce(announcement: text)
            }
			// cancel any previous hide timer
			self.messageHideTimer?.invalidate()
			
			// set text
			self.viewController.messageLabel.text = text
			
			// make sure status is showing
			self.showHideMessage(hide: false, animated: true)
			
			if autoHide {
				// Compute an appropriate amount of time to display the on screen message.
				// According to https://en.wikipedia.org/wiki/Words_per_minute, adults read
				// about 200 words per minute and the average English word is 5 characters
				// long. So 1000 characters per minute / 60 = 15 characters per second.
				// We limit the duration to a range of 1-10 seconds.
				let charCount = text.count
				let displayDuration: TimeInterval = min(10, Double(charCount) / 15.0 + 1.0)
				self.messageHideTimer = Timer.scheduledTimer(withTimeInterval: displayDuration,
				                                        repeats: false,
				                                        block: { [weak self] ( _ ) in
															self?.showHideMessage(hide: true, animated: true)
				})
			}
		}
	}
    
    /// Schedule a message to appear some time interval in the future
    ///
    /// - Parameters:
    ///   - text: the message to display
    ///   - seconds: the time before displaying the message
    ///   - messageType: the type of message
	func scheduleMessage(_ text: String, inSeconds seconds: TimeInterval, messageType: MessageType) {
		// Do not schedule a new message if a feedback escalation alert is still on screen.
		guard !schedulingMessagesBlocked else {
			return
		}
		
		var timer: Timer?
		switch messageType {
		case .contentPlacement: timer = contentPlacementMessageTimer
		case .planeEstimation: timer = planeEstimationMessageTimer
		case .trackingStateEscalation: timer = trackingStateFeedbackEscalationTimer
		}
		
		if timer != nil {
			timer!.invalidate()
			timer = nil
		}
		timer = Timer.scheduledTimer(withTimeInterval: seconds,
		                             repeats: false,
		                             block: { [weak self] ( _ ) in
										self?.showMessage(text)
										timer?.invalidate()
										timer = nil
		})
		switch messageType {
		case .contentPlacement: contentPlacementMessageTimer = timer
		case .planeEstimation: planeEstimationMessageTimer = timer
		case .trackingStateEscalation: trackingStateFeedbackEscalationTimer = timer
		}
	}
    
    /// Cancel any messages that have yet to be presented to the user
    ///
    /// - Parameter messageType: the type of messages to cancel
    func cancelScheduledMessage(forType messageType: MessageType) {
        var timer: Timer?
        switch messageType {
        case .contentPlacement: timer = contentPlacementMessageTimer
        case .planeEstimation: timer = planeEstimationMessageTimer
        case .trackingStateEscalation: timer = trackingStateFeedbackEscalationTimer
        }
        
        if timer != nil {
            timer!.invalidate()
            timer = nil
        }
    }
    
    /// Cancel all pending messages (regardless of type)
    func cancelAllScheduledMessages() {
        cancelScheduledMessage(forType: .contentPlacement)
        cancelScheduledMessage(forType: .planeEstimation)
        cancelScheduledMessage(forType: .trackingStateEscalation)
    }
    
    // MARK: - ARKit
    
    /// Show the tracking quality state
    ///
    /// - Parameters:
    ///   - trackingState: the tracking state
    ///   - autoHide: whether to auto hide after presentation
	func showTrackingQualityInfo(for trackingState: ARCamera.TrackingState, autoHide: Bool) {
		showMessage(trackingState.presentationString, autoHide: autoHide)
	}

    /// Escalate the tracking feedback state (results in an alert dialog)
    ///
    /// - Parameters:
    ///   - trackingState: the tracking state
    ///   - autoHide: whether to auto hide after presentation
	func escalateFeedback(for trackingState: ARCamera.TrackingState, inSeconds seconds: TimeInterval) {
		if self.trackingStateFeedbackEscalationTimer != nil {
			self.trackingStateFeedbackEscalationTimer!.invalidate()
			self.trackingStateFeedbackEscalationTimer = nil
		}
		
		self.trackingStateFeedbackEscalationTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false, block: { _ in
			self.trackingStateFeedbackEscalationTimer?.invalidate()
			self.trackingStateFeedbackEscalationTimer = nil
			self.schedulingMessagesBlocked = true
			var title = ""
			var message = ""
			switch trackingState {
			case .notAvailable:
				title = "Tracking status: Not available."
				message = "Tracking status has been unavailable for an extended time. Try resetting the session."
			case .limited(let reason):
				title = "Tracking status: Limited."
				message = "Tracking status has been limited for an extended time. "
				switch reason {
				case .excessiveMotion:
                    message += "Try slowing down your movement, or reset the session."
				case .insufficientFeatures:
                    message += "Try pointing at a flat surface, or reset the session."
                case .initializing:
                    message += "Initializing AR Session"
                case .relocalizing:
                    message += "Relocalizing AR Session"
                }
			case .normal: break
			}
			
			let restartAction = UIAlertAction(title: "Reset", style: .destructive, handler: { _ in
				self.viewController.restartExperience(self)
				self.schedulingMessagesBlocked = false
			})
			let okAction = UIAlertAction(title: "OK", style: .default, handler: { _ in
				self.schedulingMessagesBlocked = false
			})
			self.showAlert(title: title, message: message, actions: [restartAction, okAction])
		})
    }
    
    // MARK: - Alert View
    
    /// Show an alert
    ///
    /// - Parameters:
    ///   - title: the title of the alert
    ///   - message: the description of the alert
    ///   - actions: the actions tht can be performed
	func showAlert(title: String, message: String, actions: [UIAlertAction]? = nil) {
		alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
		if let actions = actions {
			for action in actions {
				alertController!.addAction(action)
			}
		} else {
			alertController!.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
		}
		DispatchQueue.main.async {
			self.viewController.present(self.alertController!, animated: true, completion: nil)
		}
	}
	
    /// Dismiss an alert that has been presented
	func dismissPresentedAlert() {
		DispatchQueue.main.async {
			self.alertController?.dismiss(animated: true, completion: nil)
		}
	}
	
    // MARK: - Background Blur
	
    /// Blur the background (e.g., in response to a tracking error)
	func blurBackground() {
		let blurEffect = UIBlurEffect(style: UIBlurEffectStyle.light)
		let blurEffectView = UIVisualEffectView(effect: blurEffect)
		blurEffectView.frame = viewController.view.bounds
		blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		blurEffectView.tag = blurEffectViewTag
		viewController.view.addSubview(blurEffectView)
	}
	
    /// Unblur the background (e.g., in response to a tracking recovery)
	func unblurBackground() {
		for view in viewController.view.subviews {
			if let blurView = view as? UIVisualEffectView, blurView.tag == blurEffectViewTag {
				blurView.removeFromSuperview()
			}
		}
	}
	
	// MARK: - Panel Visibility
    
    /// Show a message and then potentially hide it and optentially animate it
    ///
    /// - Parameters:
    ///   - hide: whether to hide the message
    ///   - animated: whether to animate
	private func showHideMessage(hide: Bool, animated: Bool) {
		if !animated {
			viewController.messageLabel.isHidden = hide
			return
		}
		
		UIView.animate(withDuration: 0.2,
		               delay: 0,
		               options: [.allowUserInteraction, .beginFromCurrentState],
		               animations: {
						self.viewController.messageLabel.isHidden = hide
						self.updateMessagePanelVisibility()
		}, completion: nil)
	}
	
    /// Set whether the message panel is hidden based on whether the messageLabel is hidden
	private func updateMessagePanelVisibility() {
		// Show and hide the panel depending whether there is something to show.
		viewController.messagePanel.isHidden = viewController.messageLabel.isHidden
	}
    
}
