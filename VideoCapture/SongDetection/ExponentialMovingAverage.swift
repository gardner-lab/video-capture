//
//  ExponentialMovingAverage.swift
//  SongDetector
//
//  Created by Nathan Perkins on 9/4/15.
//  Copyright © 2015 Gardner Lab. All rights reserved.
//

import Foundation

class ExponentialMovingAverage
{
    let k: Double
    private var last: Double = 0.0
    private var count: Int = 0
    
    var lastValue: Double {
        get {
            return last
        }
    }
    
    init(tau: Double, initial: Double = 0.0) {
        k = exp(-2 * M_PI / tau)
        last = initial
    }
    
    func ingest(val: Double) -> Double {
        if 1 == ++count {
            last = val
            return val
        }
        else {
            last = ((1 - k) * val) + (k * last)
            return last
        }
    }
}