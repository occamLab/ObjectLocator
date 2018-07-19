/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Popover view controller for choosing virtual objects to place in the AR scene.
*/

import UIKit


// MARK: - NewJobViewControllerDelegate

protocol NewJobViewControllerDelegate: class {
    func newJobViewController(_: NewJobViewController, didRequestNewJob objectName: String)
}

class NewJobViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var objectToFind: UITextField!
    weak var delegate: NewJobViewControllerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.delegate = presentingViewController as? NewJobViewControllerDelegate
        objectToFind.becomeFirstResponder()
        objectToFind.delegate = self
        preferredContentSize = CGSize(width:300, height:100)

    }


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
