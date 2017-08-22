/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Methods on the main view controller for handling virtual object loading and movement
*/

import UIKit
import SceneKit
import ARKit
import Alamofire

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
    
    func pollForCoordinates(frame: ARFrame?, image: UIImage, labelRequest: Int, object: VirtualObject, cameraTransform:matrix_float4x4) {
        // get the coordinates from the labelers
        let parameters: Parameters = [
            "label_request" : labelRequest
        ]
        print("getting coordinates for jobId", parameters)
        Alamofire.request("https://damp-chamber-71992.herokuapp.com/get_coordinates", method: .post, parameters: parameters, encoding: JSONEncoding.default).responseJSON { response in
            if let data = response.result.value as? [String:Any],
                let xCoord = data["x"] as? Double,
                let yCoord = data["y"] as? Double {
                if xCoord < 0 || yCoord < 0 {
                    // poll for the coordinates every 2 seconds
                    Timer.scheduledTimer(withTimeInterval: TimeInterval(2.0), repeats: false) { timer in
                        return self.pollForCoordinates(frame: frame, image: image, labelRequest: labelRequest, object: object, cameraTransform: cameraTransform)
                    }
                }
                
                let objectPixelLocation = CGPoint(x:Double(self.sceneView.bounds.width)*xCoord/Double(image.size.width), y:Double(self.sceneView.bounds.height)*yCoord/Double(image.size.height))

                let (worldPos, _, _) = self.virtualObjectManager.worldPositionFromScreenPosition(objectPixelLocation,
                                                                                                 in:        self.sceneView,
                                                                                                 in_img: frame,
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
            }
        }
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
            let parameters: Parameters = [
                "object_to_find" : "Hard coded for now",
                "image": strBase64
            ]
            // dispatch to the backend for labeling
            Alamofire.request("https://damp-chamber-71992.herokuapp.com/add_labeling_job", method: .post, parameters: parameters, encoding: JSONEncoding.default).responseJSON { response in
                debugPrint(response)
                if let data = response.result.value as? [String: Any],
                    let jobId:Int = data["job_id"] as? Int {
                    print("Polling for coordinates!")
                    self.pollForCoordinates(frame: frameCopy, image: sceneImage, labelRequest: jobId, object: object, cameraTransform: cameraTransform)
                }
            }
        }
        myClosure()
    }
    
    func virtualObjectSelectionViewController(_: VirtualObjectSelectionViewController, didDeselectObjectAt index: Int) {
        virtualObjectManager.removeVirtualObject(at: index)
    }
    
}
