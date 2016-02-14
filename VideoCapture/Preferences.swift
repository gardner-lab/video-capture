//  Preferences.swift
//  VideoCapture
//
//  Created by L. Nathan Perkins on 7/2/15.
//  Copyright © 2015

import Foundation
import Cocoa

private let keyPinAnalogTrigger = "PinAnalogTrigger"
private let keyPinDigitalCamera = "PinDigitalCamera"
private let keyPinDigitalFeedback = "PinDigitalFeedback"
private let keyPinAnalogLED = "PinAnalogLED"
private let keySecondsAfterSong = "SecondsAfterSong"
private let keyThresholdSongNonsongRatio = "ThresholdSongNonsongRatio"
private let keyThresholdSongBackgroundRatio = "ThresholdSongBackgroundRatio"
private let keyVideoFormat = "VideoFormat"

enum PreferenceVideoFormat: CustomStringConvertible {
    case Raw
    case H264
    
    init?(fromString s: String) {
        switch s {
        case "Raw":
            self = .Raw
        case "H264":
            self = .H264
        default:
            return nil
        }
    }
    
    var description: String {
        get {
            switch self {
            case .H264:
                return "H264"
            case .Raw:
                return "Raw"
            }
        }
    }
}

/// Potentially customizable application preferences.
struct Preferences {
    // pin preferences
    var pinAnalogTrigger: Int {
        didSet {
            NSUserDefaults.standardUserDefaults().setInteger(pinAnalogTrigger, forKey: keyPinAnalogTrigger)
        }
    }
    var pinDigitalCamera: Int {
        didSet {
            NSUserDefaults.standardUserDefaults().setInteger(pinDigitalCamera, forKey: keyPinDigitalCamera)
        }
    }
    var pinDigitalFeedback: Int {
        didSet {
            NSUserDefaults.standardUserDefaults().setInteger(pinDigitalFeedback, forKey: keyPinDigitalFeedback)
        }
    }
    var pinAnalogLED: Int {
        didSet {
            NSUserDefaults.standardUserDefaults().setInteger(pinAnalogLED, forKey: keyPinAnalogLED)
        }
    }
    
    // frames after song to store
    var secondsAfterSong: Double {
        didSet {
            NSUserDefaults.standardUserDefaults().setDouble(secondsAfterSong, forKey: keySecondsAfterSong)
        }
    }
    
    // thresholds
    var thresholdSongNongsongRatio: Double {
        didSet {
            NSUserDefaults.standardUserDefaults().setDouble(thresholdSongNongsongRatio, forKey: keyThresholdSongNonsongRatio)
        }
    }
    var thresholdSongBackgroundRatio: Double {
        didSet {
            NSUserDefaults.standardUserDefaults().setDouble(thresholdSongBackgroundRatio, forKey: keyThresholdSongBackgroundRatio)
        }
    }
    
    // output format
    var videoFormat: PreferenceVideoFormat {
        didSet {
            NSUserDefaults.standardUserDefaults().setValue(videoFormat.description, forKey: keyVideoFormat)
        }
    }
    
    init() {
        // get defaults
        let defaults = NSUserDefaults.standardUserDefaults()
        
        pinAnalogTrigger = defaults.integerForKey(keyPinAnalogTrigger)
        pinDigitalCamera = defaults.integerForKey(keyPinDigitalCamera)
        pinDigitalFeedback = defaults.integerForKey(keyPinDigitalFeedback)
        pinAnalogLED = defaults.integerForKey(keyPinAnalogLED)
        secondsAfterSong = defaults.doubleForKey(keySecondsAfterSong)
        thresholdSongNongsongRatio = defaults.doubleForKey(keyThresholdSongNonsongRatio)
        thresholdSongBackgroundRatio = defaults.doubleForKey(keyThresholdSongBackgroundRatio)
        videoFormat = PreferenceVideoFormat(fromString: defaults.stringForKey(keyVideoFormat) ?? "H264") ?? PreferenceVideoFormat.H264
    }
    
    static let defaultPreferences: [String: AnyObject] = [
        keyPinAnalogTrigger: NSNumber(integer: 0),
        keyPinDigitalCamera: NSNumber(integer: 4),
        keyPinDigitalFeedback: NSNumber(integer: 9),
        keyPinAnalogLED: NSNumber(integer: 13),
        keySecondsAfterSong: NSNumber(double: 1.5),
        keyThresholdSongNonsongRatio: NSNumber(double: 1.4),
        keyThresholdSongBackgroundRatio: NSNumber(double: 25.0),
        keyVideoFormat: "H264"
    ]
    
    static func registerDefaults() {
        NSUserDefaults.standardUserDefaults().registerDefaults(defaultPreferences)
    }
}
