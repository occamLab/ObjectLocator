/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Wrapper SceneKit node for virtual objects placed into the AR scene.
*/

import Foundation
import SceneKit
import ARKit

struct VirtualObjectDefinition: Codable, Equatable {
    let modelName: String
    let displayName: String
    let particleScaleInfo: [String: Float]
    
    lazy var thumbImage: UIImage = UIImage(named: self.modelName)!
    
    init(modelName: String, displayName: String, particleScaleInfo: [String: Float] = [:]) {
        self.modelName = modelName
        self.displayName = displayName
        self.particleScaleInfo = particleScaleInfo
    }
    
    static func ==(lhs: VirtualObjectDefinition, rhs: VirtualObjectDefinition) -> Bool {
        return lhs.modelName == rhs.modelName
            && lhs.displayName == rhs.displayName
            && lhs.particleScaleInfo == rhs.particleScaleInfo
    }
}

class VirtualObject: SCNNode {
    let objectToFind: String
    let cubeNode: SCNNode
    
    init(objectToFind: String) {
        self.objectToFind = objectToFind
        
        cubeNode = SCNNode(geometry: SCNBox(width: 0.05, height: 0.05, length: 0.05, chamferRadius: 0))
        cubeNode.position = SCNVector3(0, 0, 0.0)
        
        super.init()
        
        self.addChildNode(cubeNode)
        let objectText = SCNText(string: objectToFind, extrusionDepth: 1.0)
        objectText.font = UIFont (name: "Arial", size: 48)
        objectText.firstMaterial!.diffuse.contents = UIColor.green
        let textNode = SCNNode(geometry: objectText)
        textNode.position = SCNVector3(x: 0.0, y: 0.15, z: 0.0)
        textNode.scale = SCNVector3(x: 0.002, y: 0.002, z: 0.002)
        cubeNode.addChildNode(textNode)
        center(node: textNode)
    }
    
    func center(node: SCNNode) {
        let (min, max) = node.boundingBox
        
        let dx = min.x + 0.5 * (max.x - min.x)
        let dy = min.y + 0.5 * (max.y - min.y)
        let dz = min.z + 0.5 * (max.z - min.z)
        node.pivot = SCNMatrix4MakeTranslation(dx, dy, dz)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension VirtualObject {
	
	static func isNodePartOfVirtualObject(_ node: SCNNode) -> VirtualObject? {
		if let virtualObjectRoot = node as? VirtualObject {
			return virtualObjectRoot
		}
		
		if node.parent != nil {
			return isNodePartOfVirtualObject(node.parent!)
		}
		
		return nil
	}
    
}

// MARK: - Protocols for Virtual Objects

protocol ReactsToScale {
	func reactToScale()
}

extension SCNNode {
	
	func reactsToScale() -> ReactsToScale? {
		if let canReact = self as? ReactsToScale {
			return canReact
		}
		
		if parent != nil {
			return parent!.reactsToScale()
		}
		
		return nil
	}
}
