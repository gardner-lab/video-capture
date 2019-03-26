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
private let keyPinDigitalToggleLED = "PinDigitalToggleLED"
private let keyPinAnalogLED = "PinAnalogLED"
private let keyPinAnalogSecondLED = "PinAnalogSecondLED"
private let keyPinDigitalSync = "PinDigitalSync"
private let keyTriggerType = "TriggerType"
private let keyTriggerPollTime = "TriggerPollTime"
private let keyTriggerValue = "TriggerValue"
private let keySecondsAfterSong = "SecondsAfterSong"
private let keyThresholdSongNonsongRatio = "ThresholdSongNonsongRatio"
private let keyThresholdSongBackgroundRatio = "ThresholdSongBackgroundRatio"
private let keyVideoFormat = "VideoFormat"
private let keyAudioFormat = "AudioFormat"

enum PreferenceVideoFormat: CustomStringConvertible, Equatable {
    case raw
    case h264
    
    init?(fromString s: String) {
        switch s {
        case "Raw":
            self = .raw
        case "H264":
            self = .h264
        default:
            return nil
        }
    }
    
    var description: String {
        get {
            switch self {
            case .h264:
                return "H264"
            case .raw:
                return "Raw"
            }
        }
    }
}

enum PreferenceAudioFormat: CustomStringConvertible, Equatable {
    case aac
    case raw // pcm
    
    init?(fromString s: String) {
        switch s {
        case "AAC":
            self = .aac
        case "Raw":
            self = .raw
        default:
            return nil
        }
    }
    
    var description: String {
        get {
            switch self {
            case .aac:
                return "AAC"
            case .raw:
                return "Raw"
            }
        }
    }
}

enum PreferenceTriggerType: CustomStringConvertible, Equatable {
    case arduinoPin
    
    init?(fromString s: String) {
        switch s {
        case "ArduinoPin", "Arduino Pin":
            self = .arduinoPin
        default:
            return nil
        }
    }
    
    var description: String {
        get {
            switch self {
            case .arduinoPin:
                return "Arduino Pin"
            }
        }
    }
}

/// Potentially customizable application preferences.
struct Preferences {
    // pin preferences
    var pinAnalogTrigger: Int {
        didSet {
            UserDefaults.standard.set(pinAnalogTrigger, forKey: keyPinAnalogTrigger)
        }
    }
    var pinDigitalCamera: Int {
        didSet {
            UserDefaults.standard.set(pinDigitalCamera, forKey: keyPinDigitalCamera)
        }
    }
    var pinDigitalFeedback: Int {
        didSet {
            UserDefaults.standard.set(pinDigitalFeedback, forKey: keyPinDigitalFeedback)
        }
    }
    var pinAnalogLED: Int {
        didSet {
            UserDefaults.standard.set(pinAnalogLED, forKey: keyPinAnalogLED)
        }
    }
    var pinAnalogSecondLED: Int {
        didSet {
            UserDefaults.standard.set(pinAnalogSecondLED, forKey: keyPinAnalogSecondLED)
        }
    }
    var pinDigitalToggleLED: Int {
        didSet {
            UserDefaults.standard.set(pinDigitalToggleLED, forKey: keyPinDigitalToggleLED)
        }
    }
    var pinDigitalSync: Int {
        didSet {
            UserDefaults.standard.set(pinDigitalSync, forKey: keyPinDigitalSync)
        }
    }
    
    // frames after song to store
    var secondsAfterSong: Double {
        didSet {
            UserDefaults.standard.set(secondsAfterSong, forKey: keySecondsAfterSong)
        }
    }
    
    // trigger
    var triggerType: PreferenceTriggerType {
        didSet {
            UserDefaults.standard.setValue(triggerType.description, forKey: keyTriggerType)
        }
    }
    
    // arduino trigger
    var triggerPollTime: Double {
        didSet {
            UserDefaults.standard.set(triggerPollTime, forKey: keyTriggerPollTime)
        }
    }
    var triggerValue: Int {
        didSet {
            UserDefaults.standard.set(triggerValue, forKey: keyTriggerValue)
        }
    }
    
    // thresholds
    var thresholdSongNongsongRatio: Double {
        didSet {
            UserDefaults.standard.set(thresholdSongNongsongRatio, forKey: keyThresholdSongNonsongRatio)
        }
    }
    var thresholdSongBackgroundRatio: Double {
        didSet {
            UserDefaults.standard.set(thresholdSongBackgroundRatio, forKey: keyThresholdSongBackgroundRatio)
        }
    }
    
    // output format
    var videoFormat: PreferenceVideoFormat {
        didSet {
            UserDefaults.standard.setValue(videoFormat.description, forKey: keyVideoFormat)
        }
    }
    
    var audioFormat: PreferenceAudioFormat {
        didSet {
            UserDefaults.standard.setValue(audioFormat.description, forKey: keyAudioFormat)
        }
    }
    
    init() {
        // register preference defaults
        Preferences.registerDefaults()
        
        // get defaults
        let defaults = UserDefaults.standard
        
        pinAnalogTrigger = defaults.integer(forKey: keyPinAnalogTrigger)
        pinDigitalCamera = defaults.integer(forKey: keyPinDigitalCamera)
        pinDigitalFeedback = defaults.integer(forKey: keyPinDigitalFeedback)
        pinAnalogLED = defaults.integer(forKey: keyPinAnalogLED)
        pinAnalogSecondLED = defaults.integer(forKey: keyPinAnalogSecondLED)
        pinDigitalToggleLED = defaults.integer(forKey: keyPinDigitalToggleLED)
        
        pinDigitalSync = defaults.integer(forKey: keyPinDigitalSync)
        secondsAfterSong = defaults.double(forKey: keySecondsAfterSong)
        triggerType = PreferenceTriggerType(fromString: defaults.string(forKey: keyTriggerType) ?? "Arduino Pin") ?? PreferenceTriggerType.arduinoPin
        triggerPollTime = defaults.double(forKey: keyTriggerPollTime)
        triggerValue = defaults.integer(forKey: keyTriggerValue)
        thresholdSongNongsongRatio = defaults.double(forKey: keyThresholdSongNonsongRatio)
        thresholdSongBackgroundRatio = defaults.double(forKey: keyThresholdSongBackgroundRatio)
        videoFormat = PreferenceVideoFormat(fromString: defaults.string(forKey: keyVideoFormat) ?? "H264") ?? PreferenceVideoFormat.h264
        audioFormat = PreferenceAudioFormat(fromString: defaults.string(forKey: keyAudioFormat) ?? "AAC") ?? PreferenceAudioFormat.aac
    }
    
    static let defaultPreferences: [String: Any] = [
        keyPinAnalogTrigger: NSNumber(value: 0 as Int),
        keyPinDigitalCamera: NSNumber(value: 4 as Int),
        keyPinDigitalFeedback: NSNumber(value: 9 as Int),
        keyPinAnalogLED: NSNumber(value: 66 as Int),
        keyPinAnalogSecondLED: NSNumber(value: 67 as Int),
        keyPinDigitalToggleLED: NSNumber(value: 12 as Int),
        keyPinDigitalSync: NSNumber(value: 7 as Int),
        keySecondsAfterSong: NSNumber(value: 1.5 as Double),
        keyTriggerType: "Arduino Pin",
        keyTriggerPollTime: NSNumber(value: 0.05 as Double),
        keyTriggerValue: NSNumber(value: 500 as Int),
        keyThresholdSongNonsongRatio: NSNumber(value: 1.4 as Double),
        keyThresholdSongBackgroundRatio: NSNumber(value: 25.0 as Double),
        keyVideoFormat: "H264",
        keyAudioFormat: "AAC"
    ]
    
    // track
    private static var _doneRegisteringDefaults = false
    
    static func registerDefaults() {
        // register defaults only once
        if _doneRegisteringDefaults { return }
        _doneRegisteringDefaults = true
        UserDefaults.standard.register(defaults: defaultPreferences)
    }
}
