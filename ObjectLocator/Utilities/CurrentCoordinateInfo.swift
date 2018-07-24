//
//  CurrentCoordinateInfo.swift
//  ObjectLocator
//
//  Created by Paul Ruvolo on 10/17/17.
//  Copyright © 2017 Apple. All rights reserved.
//

import Foundation
import VectorMath

/// A struct that holds the current coordinate info (e.g., to represent the pose of the camera)
public struct CurrentCoordinateInfo {
    /// the location
    public var location: LocationInfo
    /// the transformation
    public var transformMatrix: Matrix3 = Matrix3.identity
    
    /// Initialize a new CurrentCoordinateInfo struct
    ///
    /// - Parameters:
    ///   - location: the location of the coordinate info
    ///   - transMatrix: the transformation matrix to the coordinate info
    public init(_ location: LocationInfo, transMatrix: Matrix3) {
        self.location = location
        self.transformMatrix = transMatrix
    }
    
    /// Initialize a new CurrentCoordinateInfo struct
    ///
    /// - Parameters:
    ///   - location: the location of the coordinate info
    public init(_ location: LocationInfo) {
        self.location = location
    }
}
