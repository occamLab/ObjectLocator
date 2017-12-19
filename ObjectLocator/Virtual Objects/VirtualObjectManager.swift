/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A type which controls the manipulation of virtual objects.
*/

import Foundation
import ARKit

class VirtualObjectManager {
	
	weak var delegate: VirtualObjectManagerDelegate?
	
	var virtualObjects = [VirtualObject]()
	var lastUsedObject: VirtualObject?
	var planes: [Plane] = []
    
	// MARK: - Resetting objects
	
    static let availableObjects: [VirtualObjectDefinition] = {
        guard let jsonURL = Bundle.main.url(forResource: "VirtualObjects", withExtension: "json")
            else { fatalError("missing expected VirtualObjects.json in bundle") }
        do {
            let jsonData = try Data(contentsOf: jsonURL)
            return try JSONDecoder().decode([VirtualObjectDefinition].self, from: jsonData)
        } catch {
            fatalError("can't load virtual objects JSON: \(error)")
        }
    }()

	func removeAllVirtualObjects() {
		for object in virtualObjects {
			unloadVirtualObject(object)
		}
		virtualObjects.removeAll()
	}
	
    func addPlane(plane: Plane) {
        // add the plane so we can do our own custom hit testing later
        planes.append(plane)
    }
    
    func removePlane(anchor: ARPlaneAnchor) {
        // remove the plane since it is no longer valid
        planes = planes.filter { $0.anchor != anchor }
    }
    
	private func unloadVirtualObject(_ object: VirtualObject) {
		ViewController.serialQueue.async {
			object.removeFromParentNode()
			if self.lastUsedObject == object {
				self.lastUsedObject = nil
				if self.virtualObjects.count > 1 {
					self.lastUsedObject = self.virtualObjects[0]
				}
			}
		}
	}
	
	// MARK: - Loading object
	
	func loadVirtualObject(_ object: VirtualObject, to position: float3, cameraTransform: matrix_float4x4) {
		self.virtualObjects.append(object)
		self.delegate?.virtualObjectManager(self, willLoad: object)
		
		// Load the content asynchronously.
		DispatchQueue.global().async {
			// Immediately place the object in 3D space.
			ViewController.serialQueue.async {
				self.setNewVirtualObjectPosition(object, to: position, cameraTransform: cameraTransform)
				self.lastUsedObject = object
                
				self.delegate?.virtualObjectManager(self, didLoad: object)
			}
		}
	}
	
	private func setNewVirtualObjectPosition(_ object: VirtualObject, to pos: float3, cameraTransform: matrix_float4x4) {
		let cameraWorldPos = cameraTransform.translation
		var cameraToPosition = pos - cameraWorldPos
		
		// Limit the distance of the object from the camera to a maximum of 10 meters.
        if simd_length(cameraToPosition) > 10 {
            cameraToPosition = simd_normalize(cameraToPosition)
            cameraToPosition *= 10
        }

		object.simdPosition = cameraWorldPos + cameraToPosition
	}
	
	private func updateVirtualObjectPosition(_ object: VirtualObject, to pos: float3, filterPosition: Bool, cameraTransform: matrix_float4x4) {
		let cameraWorldPos = cameraTransform.translation
		var cameraToPosition = pos - cameraWorldPos
		
		// Limit the distance of the object from the camera to a maximum of 10 meters.
        if simd_length(cameraToPosition) > 10 {
            cameraToPosition = simd_normalize(cameraToPosition)
            cameraToPosition *= 10
        }

        object.simdPosition = cameraWorldPos + cameraToPosition
	}
	
	func checkIfObjectShouldMoveOntoPlane(anchor: ARPlaneAnchor, planeAnchorNode: SCNNode) {
		for object in virtualObjects {
			// Get the object's position in the plane's coordinate system.
			let objectPos = planeAnchorNode.convertPosition(object.position, from: object.parent)
			
			if objectPos.y == 0 {
				return; // The object is already on the plane - nothing to do here.
			}
			
			// Add 10% tolerance to the corners of the plane.
			let tolerance: Float = 0.1
			
			let minX: Float = anchor.center.x - anchor.extent.x / 2 - anchor.extent.x * tolerance
			let maxX: Float = anchor.center.x + anchor.extent.x / 2 + anchor.extent.x * tolerance
			let minZ: Float = anchor.center.z - anchor.extent.z / 2 - anchor.extent.z * tolerance
			let maxZ: Float = anchor.center.z + anchor.extent.z / 2 + anchor.extent.z * tolerance
			
			if objectPos.x < minX || objectPos.x > maxX || objectPos.z < minZ || objectPos.z > maxZ {
				return
			}
			
			// Move the object onto the plane if it is near it (within 5 centimeters).
			let verticalAllowance: Float = 0.05
			let epsilon: Float = 0.001 // Do not bother updating if the different is less than a mm.
			let distanceToPlane = abs(objectPos.y)
			if distanceToPlane > epsilon && distanceToPlane < verticalAllowance {
				delegate?.virtualObjectManager(self, didMoveObjectOntoNearbyPlane: object)
				
				SCNTransaction.begin()
				SCNTransaction.animationDuration = CFTimeInterval(distanceToPlane * 500) // Move 2 mm per second.
				SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
				object.position.y = anchor.transform.columns.3.y
				SCNTransaction.commit()
			}
		}
	}
	
	func transform(for object: VirtualObject, cameraTransform: matrix_float4x4) -> (distance: Float, rotation: Int, scale: Float) {
		let cameraPos = cameraTransform.translation
		let vectorToCamera = cameraPos - object.simdPosition
		
		let distanceToUser = simd_length(vectorToCamera)
		
		var angleDegrees = Int((object.eulerAngles.y * 180) / .pi) % 360
		if angleDegrees < 0 {
			angleDegrees += 360
		}
		
		return (distanceToUser, angleDegrees, object.scale.x)
	}

	func worldPositionFromScreenPosition(_ position: CGPoint,
	                                     in sceneView: ARSCNView,
                                         in_img currFrame : ARFrame?,
	                                     objectPos: float3?,
                                         allowFeaureHit: Bool = false) -> (position: float3?, planeAnchor: ARPlaneAnchor?, hitAPlane: Bool) {
        // TODO:  In some cases an object sits high above a plane.  Such as a chair on the floor.  In this
        // case you want to first test for a feature point hit, and if the feature point is sufficiently
        // far from a plane hit, you should default to the feature point, else use the plane.
        if let frame = currFrame {
            // -------------------------------------------------------------------------------
            // 1. Always do a hit test against exisiting plane anchors first.
            //    (If any such anchors exist & only within their extents.)
            // In order to use the hit test from the point of view of the previous frame, we have to do it manually ourselves
            let ray = frame.hitTestRayFromScreenPos(view:sceneView, position)!
            var worldCoordinatesForPlaneHit: float3?
            var planeAnchorForPlaneHit: ARPlaneAnchor?
            var closestPlane:Float?

            for plane in planes {
                guard let sceneNode = sceneView.node(for: plane.anchor) else {
                    continue
                }
                let newOrigin = sceneNode.convertPosition(SCNVector3(ray.origin), from: sceneView.scene.rootNode)
                let newDirection = sceneNode.convertVector(SCNVector3(ray.direction), from: sceneView.scene.rootNode)
                // in the plane's local coordinate system, the normal always points in the positive y direction
                let distanceToPlane = -newOrigin.y / newDirection.y

                if distanceToPlane > 0 && (closestPlane == nil || distanceToPlane < closestPlane!) {
                    let collisionPointInPlaneCoordinateSystem = SCNVector3(x: newOrigin.x + distanceToPlane*newDirection.x,
                                                                           y: newOrigin.y + distanceToPlane*newDirection.y,
                                                                           z: newOrigin.z + distanceToPlane*newDirection.z)
                    if abs(collisionPointInPlaneCoordinateSystem.x - plane.anchor.center.x) <= plane.anchor.extent.x/2.0 &&
                        abs(collisionPointInPlaneCoordinateSystem.z - plane.anchor.center.z) <= plane.anchor.extent.z/2.0 {
                        closestPlane = distanceToPlane

                        worldCoordinatesForPlaneHit = float3(sceneView.scene.rootNode.convertPosition(collisionPointInPlaneCoordinateSystem, from: sceneNode))
                        planeAnchorForPlaneHit = plane.anchor
                    }
                }
            }
            if worldCoordinatesForPlaneHit != nil {
                print("Found the point on the plane", worldCoordinatesForPlaneHit!)
                return (worldCoordinatesForPlaneHit, planeAnchorForPlaneHit, true)
            }

            // -------------------------------------------------------------------------------
            // 2. Collect more information about the environment by hit testing against
            //    the feature point cloud.
            
            var featureHitTestPosition: float3?
            if allowFeaureHit {
                let highQualityfeatureHitTestResults = frame.hitTestWithFeatures(position,
                                                                                 view:sceneView,
                                                                                 coneOpeningAngleInDegrees: 18,
                                                                                 minDistance: 0.2,
                                                                                 maxDistance: 2.0)
                
                if !highQualityfeatureHitTestResults.isEmpty {
                    let result = highQualityfeatureHitTestResults[0]
                    featureHitTestPosition = result.position
                }
            }
            return (featureHitTestPosition, nil, false)
        }
        
		return (nil, nil, false)
	}
    
    func worldPositionFromStereoScreenPosition(pixel_location_1: CGPoint,
                                               pixel_location_2: CGPoint,
                                               in sceneView: ARSCNView,
                                               in_img_1 : ARFrame?,
                                               in_img_2 : ARFrame?,
                                               objectPos: float3?) -> (position: float3?, planeAnchor: ARPlaneAnchor?, hitAPlane: Bool) {
        // TODO:  In some cases an object sits high above a plane.  Such as a chair on the floor.  In this
        // case you want to first test for a feature point hit, and if the feature point is sufficiently
        // far from a plane hit, you should default to the feature point, else use the plane.
        guard let frame1 = in_img_1, let frame2 = in_img_2 else {
            return (nil, nil, false)
        }
        guard let ray1 = frame1.hitTestRayFromScreenPos(view: sceneView, pixel_location_1),
            let ray2 = frame2.hitTestRayFromScreenPos(view: sceneView, pixel_location_2) else {
            return (nil, nil, false)
        }

        // compute closest point between the two rays using the method described here: http://morroworks.com/Content/Docs/Rays%20closest%20point.pdf
        let A = ray1.origin
        let B = ray2.origin
        let a = ray1.direction
        let b = ray2.direction
        let c = B - A
        let D = A + a*(-simd_dot(a,b)*simd_dot(b,c)+simd_dot(a,c)*simd_dot(b,b))/(simd_dot(a,a)*simd_dot(b,b) - simd_dot(a,b)*simd_dot(a,b))
        let E = B + b*(simd_dot(a,b)*simd_dot(a,c)-simd_dot(b,c)*simd_dot(a,a))/(simd_dot(a,a)*simd_dot(b,b) - simd_dot(a,b)*simd_dot(a,b))
        let closestPoint = (D + E)/2
        print("A",A)
        print("B",B)
        print("a",a)
        print("b",b)
        print("c",c)
        print("D",D)
        print("E",E)
        print("closestPoint", closestPoint)
        
        // we probably want to do sanity checks on this
        return (closestPoint, nil, false)
    }
}

// MARK: - Delegate

protocol VirtualObjectManagerDelegate: class {
	func virtualObjectManager(_ manager: VirtualObjectManager, willLoad object: VirtualObject)
	func virtualObjectManager(_ manager: VirtualObjectManager, didLoad object: VirtualObject)
	func virtualObjectManager(_ manager: VirtualObjectManager, transformDidChangeFor object: VirtualObject)
	func virtualObjectManager(_ manager: VirtualObjectManager, didMoveObjectOntoNearbyPlane object: VirtualObject)
	func virtualObjectManager(_ manager: VirtualObjectManager, couldNotPlace object: VirtualObject)
}
// Optional protocol methods
extension VirtualObjectManagerDelegate {
    func virtualObjectManager(_ manager: VirtualObjectManager, transformDidChangeFor object: VirtualObject) {}
    func virtualObjectManager(_ manager: VirtualObjectManager, didMoveObjectOntoNearbyPlane object: VirtualObject) {}
}
