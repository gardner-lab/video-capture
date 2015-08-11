//  Preferences.swift
//  VideoCapture
//
//  Created by L. Nathan Perkins on 7/2/15.
//  Copyright © 2015

import Foundation

enum PreferenceVideoFormat {
    case Raw
    case H264
}

/// Potentially customizable application preferences.
struct Preferences {
    // pin preferences
    let pinAnalogTrigger = 0
    let pinDigitalCamera = 4
    let pinDigitalFeedback = 9
    let pinAnalogLED = 13
    
    // how often to poll trigger
    let triggerPollTime = 0.05
    let triggerValue: UInt16 = 500
    
    // output format
    let videoFormat = PreferenceVideoFormat.H264
}
