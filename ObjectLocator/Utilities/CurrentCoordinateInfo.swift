//
//  CurrentCoordinateInfo.swift
//  ObjectLocator
//
//  Created by Paul Ruvolo on 10/17/17.
//  Copyright © 2017 Apple. All rights reserved.
//

import Foundation

public struct CurrentCoordinateInfo {
    //  Struct to store location and transform information
    public var location: LocationInfo
    public var transformMatrix: Matrix3 = Matrix3.identity
    
    public init(_ location: LocationInfo, transMatrix: Matrix3) {
        self.location = location
        self.transformMatrix = transMatrix
    }
    
    public init(_ location: LocationInfo) {
        self.location = location
    }
}
