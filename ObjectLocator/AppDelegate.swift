/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Empty application delegate class.
*/

import UIKit
import Firebase
import FirebaseAuth
import FirebaseUI

/// The standard app delegate class to handle the app's lifecycle
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// An attribute to hold the UIWindow (this must be here for the app to work)
    var window: UIWindow?

	// Nothing to do here. See ViewController for primary app features.

    /// Application finished launching.  Upon launch, connect to Firebase.
    ///
    /// - Parameters:
    ///   - application: the application
    ///   - launchOptions: launch options
    /// - Returns: whether or not the launch is successful.
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?)
        -> Bool {
            print("Configuring Firebase!")
            FirebaseApp.configure()
            return true
    }
    
    
    /// Handle launching from a push notification or other external mechanism to open a given URL
    ///
    /// - Parameters:
    ///   - app: our application
    ///   - url: the URL description (contains the url of the thing to open)
    ///   - options: any launch options
    /// - Returns: whether or not we successfully handled the URL
    @available(iOS 9.0, *)
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any]) -> Bool {
        let sourceApplication = options[UIApplicationOpenURLOptionsKey.sourceApplication] as! String?
        return self.handleOpenUrl(url, sourceApplication: sourceApplication)
    }

    /// An older style for launching from an external mechanism with a given URL
    ///
    /// - Parameters:
    ///   - application: our application
    ///   - url: contains the url of the thing to open
    ///   - sourceApplication: the source application (the one that caused us to open)
    ///   - annotation: an annotation of the launch request
    /// - Returns: whether or not we successfully handled the URL
    @available(iOS 8.0, *)
    func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        return self.handleOpenUrl(url, sourceApplication: sourceApplication)
    }

    /// Handle open URL
    ///
    /// - Parameters:
    ///   - url: contains the url of the thing to open
    ///   - sourceApplication: the source application (the one that caused us to open)
    /// - Returns: whether or not we are able to open the URL
    func handleOpenUrl(_ url: URL, sourceApplication: String?) -> Bool {
        if FUIAuth.defaultAuthUI()?.handleOpen(url, sourceApplication: sourceApplication) ?? false {
            return true
        }
        // other URL handling goes here.
        return false
    }
}

