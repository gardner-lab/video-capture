//  Common.swift
//  VideoCapture
//
//  Created by L. Nathan Perkins on 7/2/15.
//  Copyright © 2015

import Foundation

/// A logging function that only executes in debugging mode.
func DLog(message: String, function: String = __FUNCTION__ ) {
    #if DEBUG
    print("\(function): \(message)")
    #endif
}

func distance(a: CGPoint, _ b: CGPoint) -> CGFloat {
    let x = a.x - b.x, y = a.y - b.y
    return sqrt((x * x) + (y * y))
}