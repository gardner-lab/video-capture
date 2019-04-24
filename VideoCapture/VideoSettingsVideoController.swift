//
//  VideoSettingsVideoController.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 3/28/19.
//  Copyright © 2019 GardnerLab. All rights reserved.
//

import Cocoa
import AVFoundation

fileprivate extension AVCaptureDevice.Format
{
    var uniqueID: String {
        get {
            return self.description
        }
    }
    
    var niceDescription: String {
        get {
            let dim = CMVideoFormatDescriptionGetDimensions(self.formatDescription)
            
            // get frame rate(s)
            let frameRates = self.videoSupportedFrameRateRanges.map {
                return $0.minFrameRate
            }
            
            // multiple frame rates
            if 1 < frameRates.count {
                return String(format: "%d × %d, %.1f–%.1f FPS", dim.width, dim.height, frameRates.min()!, frameRates.max()!)
            }
            
            return String(format: "%d × %d, %.1f FPS", dim.width, dim.height, frameRates[0])
        }
    }
}

fileprivate func parseSubstringHexToUInt32(str: String, range: NSRange) -> UInt32? {
    guard let str_range = Range(range, in: str) else { return nil }
    
    // get substring
    let substr = str[str_range]
    
    var ret: UInt32 = 0
    let scanner = Scanner(string: String(substr))
    guard scanner.scanHexInt32(&ret) else { return nil }
    
    return ret
}

fileprivate func parseDeviceID(deviceID: String) -> (locationID: UInt32, vendorID: UInt32, productID: UInt32)? {
    // validate device ID
    let pattern = try! NSRegularExpression(pattern: "^0x([a-f0-9]{8})([a-f0-9]{4})([a-f0-9]{4})$", options: .caseInsensitive)
    guard let match = pattern.firstMatch(in: deviceID, options: [], range: NSRange(deviceID.startIndex..<deviceID.endIndex, in: deviceID)) else { return nil }
    
    // pull out parts
    guard let locationID = parseSubstringHexToUInt32(str: deviceID, range: match.range(at: 1)) else { return nil }
    guard let vendorID = parseSubstringHexToUInt32(str: deviceID, range: match.range(at: 2)) else { return nil }
    guard let productID = parseSubstringHexToUInt32(str: deviceID, range: match.range(at: 3)) else { return nil }
    
    return (locationID: locationID, vendorID: vendorID, productID: productID)
}

class UCLAScope {
    private enum Command: Int {
        case recordingStart = 0x01
        case recordingEnd = 0x02
        case configureCMOS = 0x03
        case fps5 = 0x11
        case fps10 = 0x12
        case fps15 = 0x13
        case fps20 = 0x14
        case fps30 = 0x15
        case fps60 = 0x16
    }
    
    let cameraControl: UVCCameraControl
    
    init?(videoDevice: AVCaptureDevice) {
        // get UVC camera controls
        guard let uvcDetails = parseDeviceID(deviceID: videoDevice.uniqueID) else { return nil }
        guard let uvcCameraControl = UVCCameraControl(locationID: uvcDetails.locationID) else { return nil }
        
        // UCLA scope most support saturation command
        if !uvcCameraControl.canSetSaturation() {
            DLog("UCLA: Non UCLA DAQ detected")
            return nil
        }
        
        self.cameraControl = uvcCameraControl
    }
    
    private func send(command: Command) -> Bool {
        // send command via saturation channel
        return self.cameraControl.setData(command.rawValue, withLength: 2, forSelector: 0x07, at: 0x02)
    }
    
    func configureCMOS() {
        if !self.send(command: .configureCMOS) {
            DLog("UCLA: Unable to configure CMOS")
        }
    }
    
    func recordingStart() {
        if !self.send(command: .recordingStart) {
            DLog("UCLA: Unable to send start recording signal")
        }
    }
    
    func recordingEnd() {
        if !self.send(command: .recordingEnd) {
            DLog("UCLA: Unable to send end recording signal")
        }
    }
    
    func setFrameRate(_ fps: Int) {
        let command: Command
        switch fps {
        case 5: command = .fps5
        case 10: command = .fps10
        case 15: command = .fps15
        case 20: command = .fps20
        case 30: command = .fps30
        case 60: command = .fps60
        default:
            DLog("UCLA: Invalid frame rate \(fps)")
            return
        }
        
        if !self.send(command: command) {
            DLog("UCLA: Unable to set frame rate")
        }
    }
    
    func setExposure(_ exposure: Float) {
        if !self.cameraControl.setBrightness(exposure) {
            DLog("UCLA: Unable to set exposure")
        }
    }
 
    // requires implementing: hue
//    func setLEDBrightness(_ brightness: Float) {
//        if !self.cameraControl.setHue
//    }
    
    func setGain(_ gain: Float) {
        if !self.cameraControl.setGain(gain) {
            DLog("UCLA: Unable to set gain")
        }
    }
}

class VideoSettingsVideoController: NSViewController {
    var session: AVCaptureSession?
    var videoInput: AVCaptureDeviceInput?
    
    var uclaScope: UCLAScope?
    
    @IBOutlet var listVideoFrameRates: NSPopUpButton!
    @IBOutlet var sliderExposure: NSSlider!
    @IBOutlet var sliderGain: NSSlider!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    override func viewWillAppear() {
        // configure interface
        guard let videoDevice = self.videoInput?.device else { return }
        
        if let uclaScope = UCLAScope(videoDevice: videoDevice) {
            // store scope
            self.uclaScope = uclaScope
            
            // enable controls
            self.listVideoFrameRates.isEnabled = true
            self.sliderExposure.isEnabled = true
            self.sliderGain.isEnabled = true
        }
        else {
            // disable controls
            self.listVideoFrameRates.isEnabled = false
            self.sliderExposure.isEnabled = false
            self.sliderGain.isEnabled = false
        }
    }
    
    private func whileConfiguring(cb: () -> ()) {
        if let videoDevice = self.videoInput?.device {
            // will crash if fails, bad
            try! videoDevice.lockForConfiguration()
            cb()
            videoDevice.unlockForConfiguration()
        }
        else {
            cb()
        }
    }
    
    @IBAction func selectFrameRate(_ sender: NSPopUpButton!) {
        guard let uclaScope = self.uclaScope else { return }
        
        if let selectedItem = sender.selectedItem {
            self.whileConfiguring {
                uclaScope.setFrameRate(selectedItem.tag)
            }
        }
    }
    
    @IBAction func setExposure(_ sender: NSSlider!) {
        guard let uclaScope = self.uclaScope else { return }
        
        self.whileConfiguring {
            uclaScope.setExposure(sender.floatValue)
        }
    }
    
    @IBAction func setGain(_ sender: NSSlider!) {
        guard let uclaScope = self.uclaScope else { return }
        
        // update gain
        self.whileConfiguring {
            uclaScope.setGain(sender.floatValue)
        }
    }
    
    override func viewWillDisappear() {
        // release camera control
        self.uclaScope = nil
    }
}
