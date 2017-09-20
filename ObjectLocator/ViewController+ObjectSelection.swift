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
    
    
    func pixelBufferToUIImage(pixelBuffer: CVPixelBuffer) -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        let uiImage = UIImage(cgImage: cgImage!)
        return uiImage
    }
    
    // MARK: - VirtualObjectSelectionViewControllerDelegate

    func virtualObjectSelectionViewController(_: VirtualObjectSelectionViewController, didSelectObjectAt index: Int, objectToFind: String!) {
        guard (session.currentFrame?.camera.transform) != nil else {
            return
        }

        { [frameCopy = self.session.currentFrame, sceneImage = self.sceneView.snapshot()] in
            let imageData:Data? = UIImageJPEGRepresentation(sceneImage, 0.8)!
            let parameters: NSDictionary = [
                "object_to_find": objectToFind,
                "creation_timestamp": ServerValue.timestamp(),
                "requesting_user": self.auth!.currentUser!.uid
            ]
            // dispatch to the backend for labeling
            let jobUUID = UUID().uuidString
            let imageRef = self.storageRef?.child(jobUUID + ".jpg")
            let metaData = StorageMetadata()
            metaData.contentType = "image/jpg"
            imageRef?.putData(imageData!, metadata: metaData) { (metadata, error) in
                guard metadata != nil else {
                    // Uh-oh, an error occurred!
                    return
                }
                let dbPath = "labeling_jobs/" + jobUUID
                self.db?.reference(withPath: dbPath).setValue(parameters)
                self.jobs[jobUUID] = JobInfo(arFrame: frameCopy!, sceneImage: sceneImage)
            }
        }()
    }
    
    func virtualObjectSelectionViewController(_: VirtualObjectSelectionViewController, didDeselectObjectAt index: Int) {
        virtualObjectManager.removeVirtualObject(at: index)
    }
    
}
