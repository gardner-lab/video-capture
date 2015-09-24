//
//  Schmitt.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 9/24/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Foundation

enum SchmittTrigger
{
    case Standard
    case LeadingEdge
    case FallingEdge
}

enum SchmittState
{
    case Idle
    case Low
    case High
}

/// This is an approximation of the Schmitt filter used in the TDT setup. It does not actually use processor timing function, but
/// simply maintains a frame.
class SchmittForCapture
{
    let trigger = SchmittTrigger.FallingEdge
    let framesHigh: Int
    let framesLow: Int
    
    var state: SchmittState = .Idle
    var count: Int = 0
    
    var lastInput: Bool = false
    var lastOutput: Bool {
        get {
            switch state {
            case .High: return true
            default: return false
            }
        }
    }
    
    init(frameRate: Double, timeHigh: Double, timeLow: Double) {
        self.framesHigh = Int(timeHigh / frameRate)
        self.framesLow = Int(timeLow / frameRate)
    }
    
    init(framesHigh: Int, framesLow: Int) {
        self.framesHigh = framesHigh
        self.framesLow = framesLow
    }
    
    func reset() {
        state = .Idle
        lastInput = false
        count = 0
    }
    
    func processFrame(input: Bool) -> Bool {
        // existing state
        switch state {
        case .Low:
            if --count <= 0 {
                state = .Idle // signal has become idle again
                // run through trigger code
            }
            else {
                return false // low signal
            }
        case .High:
            if --count <= 0 {
                state = .Low
                count = framesLow
                return false // signal just became low
            }
            else {
                return true // high signal
            }
        case .Idle: break // run through trigger code
        }
        
        // determine if this is a trigger
        let isTrigger: Bool
        
        switch trigger {
        case .Standard: isTrigger = input
        case .LeadingEdge: isTrigger = input && !lastInput
        case .FallingEdge: isTrigger = !input && lastInput
        }
        
        lastInput = input
        
        if isTrigger {
            state = .High
            count = framesLow
            return true
        }
        
        return false
    }
}
