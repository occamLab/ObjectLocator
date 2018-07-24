/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Configures the scene.
*/

import Foundation
import ARKit

// MARK: - AR scene view extensions

extension ARSCNView {
	
    /// Setup the ARSCNView by tweaking some camera settings
	func setup() {
		antialiasingMode = .multisampling4X
		automaticallyUpdatesLighting = false
		
		preferredFramesPerSecond = 60
		contentScaleFactor = 1.3
		
		if let camera = pointOfView?.camera {
			camera.wantsHDR = true
			camera.wantsExposureAdaptation = true
			camera.exposureOffset = -1
			camera.minimumExposure = -1
			camera.maximumExposure = 3
		}
	}
}
