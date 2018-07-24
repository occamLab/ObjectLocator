/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Methods on the main view controller for handling virtual object loading and movement
*/

import UIKit
import SceneKit
import ARKit
import Firebase

extension ViewController: NewJobViewControllerDelegate, VirtualObjectManagerDelegate {

    // MARK: - NewJobViewControllerDelegate

    /// Handles the information from the NewJobViewController that the user has requested a job to be posted.
    ///
    /// - Parameters:
    ///   - _: the job view controller itself
    ///   - objectName: the name of the object to find
    func newJobViewController(_: NewJobViewController, didRequestNewJob objectName: String) {
        postNewJob(objectToFind: objectName)
        announce(announcement: "Finding " + objectName)
    }
    
    // MARK: - VirtualObjectManager delegate callbacks
    
    /// Called when the virtual object manager is loading an object.  Since this could be a long running operation (although it isn't given we only use a cube for our object now), display a spinner
    ///
    /// - Parameters:
    ///   - manager: the virtual object manager
    ///   - object: the virtual object that will load
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
    
    /// Called by the virtual object manager to signal that the object is done loading.  This allows the ViewController to remove the progress spinner
    ///
    /// - Parameters:
    ///   - manager: the virtual object manager
    ///   - object: the virtual object that has just loaded
    func virtualObjectManager(_ manager: VirtualObjectManager, didLoad object: VirtualObject) {
        DispatchQueue.main.async {
            self.isLoadingObject = false
            
            // Remove progress indicator
            self.spinner?.removeFromSuperview()
            self.addObjectButton.setImage(#imageLiteral(resourceName: "add"), for: [])
            self.addObjectButton.setImage(#imageLiteral(resourceName: "addPressed"), for: [.highlighted])
        }
    }
}
