/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Methods on the main view controller for handling virtual object loading and movement
*/

import UIKit
import SceneKit
import ARKit
import Firebase

extension ViewController: VirtualObjectSelectionViewControllerDelegate, VirtualObjectManagerDelegate {
    // MARK: - VirtualObjectManager delegate callbacks
    
    func virtualObjectManager(_ manager: VirtualObjectManager, willLoad object: VirtualObject) {
        DispatchQueue.main.async {
            // Show progress indicator
            self.spinner = UIActivityIndicatorView()
            self.spinner!.center = self.addObjectButton.center
            self.spinner!.bounds.size = CGSize(width: self.addObjectButton.bounds.width - 5, height: self.addObjectButton.bounds.height - 5)
            self.addObjectButton.setImage(#imageLiteral(resourceName: "buttonring"), for: [])
            self.sceneView.addSubview(self.spinner!)
            self.spinner!.startAnimating()
            
            self.isLoadingObject = true
        }
    }
    
    func virtualObjectManager(_ manager: VirtualObjectManager, didLoad object: VirtualObject) {
        DispatchQueue.main.async {
            self.isLoadingObject = false
            
            // Remove progress indicator
            self.spinner?.removeFromSuperview()
            self.addObjectButton.setImage(#imageLiteral(resourceName: "add"), for: [])
            self.addObjectButton.setImage(#imageLiteral(resourceName: "addPressed"), for: [.highlighted])
        }
    }
    
    func virtualObjectManager(_ manager: VirtualObjectManager, couldNotPlace object: VirtualObject) {
        textManager.showMessage("CANNOT PLACE OBJECT\nTry moving left or right.")
    }
    
    // MARK: - VirtualObjectSelectionViewControllerDelegate
    
    func pixelBufferToUIImage(pixelBuffer: CVPixelBuffer) -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        let uiImage = UIImage(cgImage: cgImage!)
        return uiImage
    }
    
    func virtualObjectSelectionViewController(_: VirtualObjectSelectionViewController, didSelectObjectAt index: Int) {
        guard let cameraTransform = session.currentFrame?.camera.transform else {
            return
        }
        
        // create a closure to ensure we copy the frame before doing anything with it
        let myClosure = { [frameCopy = self.session.currentFrame, sceneImage = self.sceneView.snapshot()] in
            let definition = VirtualObjectManager.availableObjects[index]
            let object = VirtualObject(definition: definition)
            let imageData:Data? = UIImageJPEGRepresentation(sceneImage, 0.8)!
            let strBase64 = imageData!.base64EncodedString(options: .lineLength64Characters)
            let parameters: NSDictionary = [
                "object_to_find": "Hard coded for now",
                "image": strBase64
            ]
            // dispatch to the backend for labeling
            let jobUUID = UUID().uuidString
            let dbPath = "labeling_jobs/" + jobUUID
            self.ref?.child(dbPath).setValue(parameters)
            let responsePath = "responses/" + jobUUID
            
            // listen for any responses
            self.ref?.child(responsePath).observe(.childAdded, with: { (snapshot) -> Void in
                print("got a label", snapshot)
                let values = snapshot.value as! NSDictionary
                let objectPixelLocation = CGPoint(x:Double(self.sceneView.bounds.width)*(values["x"] as! Double)/Double(sceneImage.size.width), y:Double(self.sceneView.bounds.height)*(values["y"] as! Double)/Double(sceneImage.size.height))
                let (worldPos, _, _) = self.virtualObjectManager.worldPositionFromScreenPosition(objectPixelLocation,
                                                                                                 in:        self.sceneView,
                                                                                                 in_img: frameCopy,
                                                                                                 objectPos: nil)
                if worldPos == nil {
                    // TODO: should print debug info
                    return
                }
                self.virtualObjectManager.loadVirtualObject(object, to: worldPos!, cameraTransform: cameraTransform)
                if object.parent == nil {
                    self.serialQueue.async {
                        self.sceneView.scene.rootNode.addChildNode(object)
                    }
                }
            })
        }
        myClosure()
    }
    
    func virtualObjectSelectionViewController(_: VirtualObjectSelectionViewController, didDeselectObjectAt index: Int) {
        virtualObjectManager.removeVirtualObject(at: index)
    }
    
}
