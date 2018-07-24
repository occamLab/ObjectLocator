//
//  LocationInfo.swift
//  ObjectLocator
//
//  Created by Paul Ruvolo on 10/17/17.
//  Copyright © 2017 Apple. All rights reserved.
//

import Foundation

/// Struct to store position information and yaw
public struct LocationInfo {
    /// the x position
    public var x: Float
    /// the y position
    public var y: Float
    /// the z position
    public var z: Float
    /// the yaw (rotation about the axis of gravity)
    public var yaw: Float
    
    /// Initialize a LocationInfo
    ///
    /// - Parameters:
    ///   - x: x coordinate
    ///   - y: y coordinate
    ///   - z: z coordinate
    ///   - yaw: yaw (angle about the axis of gravity)
    public init(x: Float, y: Float, z: Float, yaw: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.yaw = yaw
    }
}
