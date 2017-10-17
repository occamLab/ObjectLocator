//
//  JobInfo.swift
//  ObjectLocator
//
//  Created by Paul Ruvolo on 10/17/17.
//  Copyright © 2017 Apple. All rights reserved.
//

import Foundation
import ARKit

public struct JobInfo {
    var arFrames: [String: ARFrame]
    var sceneImage : UIImage        // Used for dimension checking... TODO: Just store bounds
    var objectToFind: String
}
