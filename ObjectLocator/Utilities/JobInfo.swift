//
//  JobInfo.swift
//  ObjectLocator
//
//  Created by Paul Ruvolo on 10/17/17.
//  Copyright © 2017 Apple. All rights reserved.
//

import Foundation
import ARKit

enum JobStatus {
    case waitingForInitialResponse, waitingForPosition, waitingForAdditionalResponse, placed, failed
}

public struct JobInfo {
    var arFrames : [String: ARFrame]
    var sceneImage : UIImage        // Used for dimension checking... TODO: Just store bounds
    var objectToFind : String
    var status : JobStatus = JobStatus.waitingForInitialResponse
    var responses = [JobResponse]()
    
    init(arFrames: [String: ARFrame], sceneImage: UIImage, objectToFind: String) {
        self.arFrames = arFrames
        self.sceneImage = sceneImage
        self.objectToFind = objectToFind
    }
}

public struct JobResponse {
    var labelerID : String
    var imageUUID : String
    var pixelLocation : CGPoint
}

