//
//  DebounceBoolean.swift
//  SongDetector
//
//  Created by Nathan Perkins on 9/7/15.
//  Copyright © 2015 Gardner Lab. All rights reserved.
//

import Foundation


class DebounceBoolean
{
    let checks: Int
    private var last = false
    private var count: Int = 0
    
    var lastValue: Bool {
        get {
            return last
        }
    }
    
    init(checks: Int, initial: Bool = false) {
        DLog("Debouce(checks=\(checks))")
        
        self.checks = checks
        last = initial
    }
    
    func debounce(val: Bool) -> Bool {
        // same value, easy
        if last == val {
            count = 0
            return val
        }
        
        // exceeded threshold?
        if checks <= ++count {
            last = val
            count = 0
            return val
        }
        
        return last
    }
}