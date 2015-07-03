//
//  Preferences.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 7/2/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Foundation

struct Preferences {
    // pin preferences
    let pinAnalogTrigger = 0
    let pinDigitalCamera = 4
    let pinDigitalWhiteNoise = 9
    let pinAnalogLED = 13
    
    // how often to poll trigger
    let triggerPollTime = 0.05
    let triggerValue: UInt16 = 500
}
