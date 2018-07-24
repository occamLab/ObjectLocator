/*
See LICENSE folder for this sample’s licensing information.

Abstract:
SceneKit node wrapper for plane geometry detected in AR.
*/

import Foundation
import ARKit

/// A subclass of SCNNode that stores the position an orientation of a plane (as tracked by an ARSession)
class Plane: SCNNode {
    
    // MARK: - Properties
    
    /// The anchor in the ARSession (this contains things like position and orientation of the plane)
	var anchor: ARPlaneAnchor
    
    // MARK: - Initialization
    
    /// Initialize a new plane given an ARPlaneAnchor
    ///
    /// - Parameter anchor: the plane anchor
	init(_ anchor: ARPlaneAnchor) {
		self.anchor = anchor
		super.init()
    }
	
    /// This hasn't been implemented.
    ///
    /// - Parameter aDecoder: the coder object
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
    
    // MARK: - ARKit
	
    /// Update the plane anchor (usually in response to some notification from ARSession)
    ///
    /// - Parameter anchor: the new plane parameters
	func update(_ anchor: ARPlaneAnchor) {
		self.anchor = anchor
	}
		
}

