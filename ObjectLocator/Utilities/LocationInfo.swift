//
//  LocationInfo.swift
//  ObjectLocator
//
//  Created by Paul Ruvolo on 10/17/17.
//  Copyright © 2017 Apple. All rights reserved.
//

import Foundation

public struct LocationInfo {
    //  Struct to store position information and yaw
    public var x: Float
    public var y: Float
    public var z: Float
    public var yaw: Float
    
    public init(x: Float, y: Float, z: Float, yaw: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.yaw = yaw
    }
}
