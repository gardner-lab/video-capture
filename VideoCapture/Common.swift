//
//  Common.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 7/2/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Foundation

func DLog(message: String, function: String = __FUNCTION__ ) {
    #if DEBUG
    print("\(function): \(message)")
    #endif
}
