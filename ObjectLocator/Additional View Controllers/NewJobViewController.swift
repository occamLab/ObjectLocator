/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Popover view controller for choosing virtual objects to place in the AR scene.
*/

import UIKit


// MARK: - NewJobViewControllerDelegate

/// A protocol to enable the NewJobViewController to communicate that a job has been requested by the user
protocol NewJobViewControllerDelegate: class {
    /// Communicate that a job has been requested by the user
    ///
    /// - Parameters:
    ///   - _: the view controller that generated this call
    ///   - objectName: the name of the object that the user would like to find
    func newJobViewController(_: NewJobViewController, didRequestNewJob objectName: String)
}

/// A controller that handles the entry of a new job
class NewJobViewController: UIViewController, UITextFieldDelegate {

    /// an outlet to the text field where the name of the object is entered
    @IBOutlet weak var objectToFind: UITextField!
    /// An optional delegate to communicate any relevant events to
    weak var delegate: NewJobViewControllerDelegate?

    /// In addition to what happens in the super class, this performs the following.
    /// * Set the presenting view controller as a delegate
    /// * Put the focus on the text field
    /// * set the size to 300, 100
    override func viewDidLoad() {
        super.viewDidLoad()
        self.delegate = presentingViewController as? NewJobViewControllerDelegate
        objectToFind.becomeFirstResponder()
        objectToFind.delegate = self
        preferredContentSize = CGSize(width:300, height:100)

    }


    /// Determines if the text field should resign first responder (this is called in response to the user hitting the "enter" key)
    ///
    /// - Parameter textField: the text field
    /// - Returns: true if the UITextField should accept the user input and start a job or false if not
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        // Select the currently selected row
        if let objectText = textField.text, objectText != "" {
            delegate?.newJobViewController(self, didRequestNewJob: objectText)
            self.dismiss(animated: true, completion: nil)
            return false
        } else {
            // TODO: throw an error
            return true
        }
    }}
