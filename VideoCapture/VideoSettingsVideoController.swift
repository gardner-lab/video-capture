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

class VideoSettingsVideoController: NSViewController {
    var session: AVCaptureSession?
    var videoInput: AVCaptureDeviceInput?
    
    var uvcCameraControl: UVCCameraControl?
    
    @IBOutlet var listVideoFormats: NSPopUpButton!
    @IBOutlet var listVideoFrameRates: NSPopUpButton!
    @IBOutlet var buttonAutoExposure: NSButton!
    @IBOutlet var sliderExposure: NSSlider!
    @IBOutlet var sliderGain: NSSlider!
    @IBOutlet var buttonAutoWhiteBalance: NSButton!
    @IBOutlet var sliderWhiteBalance: NSSlider!
    // @IBOutlet var textExposure: NSTextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    override func viewWillAppear() {
        // configure interface
        guard let videoDevice = self.videoInput?.device else { return }
        
        // list formats
        listVideoFormats.removeAllItems()
        var selectedIndex = -1
        for (index, format) in videoDevice.formats.enumerated() {
            // add to format list
            let item = NSMenuItem()
            item.title = format.niceDescription
            item.representedObject = format
            listVideoFormats.menu?.addItem(item)
            
            // ise selected?
            if format == videoDevice.activeFormat {
                selectedIndex = index
            }
        }
        if 0 <= selectedIndex {
            listVideoFormats.selectItem(at: selectedIndex)
        }
        
        // load uvc camera control
        if let uvcDetails = parseDeviceID(deviceID: videoDevice.uniqueID), let cameraControl = UVCCameraControl(locationID: uvcDetails.locationID){
            self.uvcCameraControl = cameraControl
            
            // exposure
            let exposure = cameraControl.getExposure()
            if exposure >= 0.0 && exposure <= 1.0 {
                self.buttonAutoExposure.isEnabled = true
                self.sliderExposure.isEnabled = !cameraControl.getAutoExposure()
                self.sliderExposure.floatValue = exposure
            }
            else {
                self.buttonAutoExposure.isEnabled = false
                self.sliderExposure.isEnabled = false
            }
            
            // gain
            let gain = cameraControl.getGain()
            if gain >= 0.0 && gain <= 1.0 {
                self.sliderGain.isEnabled = true
                self.sliderGain.floatValue = gain
            }
            else {
                self.sliderGain.isEnabled = false
            }
            
            // white balance
            let whiteBalance = cameraControl.getWhiteBalance()
            if whiteBalance >= 0.0 && whiteBalance <= 1.0 {
                self.buttonAutoWhiteBalance.isEnabled = true
                self.sliderWhiteBalance.isEnabled = !cameraControl.getAutoWhiteBalance()
                self.sliderWhiteBalance.floatValue = whiteBalance
            }
            else {
                self.buttonAutoWhiteBalance.isEnabled = false
                self.sliderWhiteBalance.isEnabled = false
            }
        }
        else {
            self.uvcCameraControl = nil
            self.sliderExposure.isEnabled = false
            self.sliderGain.isEnabled = false
        }
        
        // list frame rates
        self.refreshFrameRate(forFormat: videoDevice.activeFormat)
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
    
    func refreshFrameRate(forFormat format: AVCaptureDevice.Format) {
        // configure interface
        guard let videoDevice = self.videoInput?.device else { return }
        
        listVideoFrameRates.removeAllItems()
        var selectedIndex = -1
        for (index, frameRate) in format.videoSupportedFrameRateRanges.enumerated() {
            let item = NSMenuItem()
            item.title = String(format: "%.1f FPS / %.1f ms", frameRate.minFrameRate, frameRate.maxFrameDuration.seconds * 1_000.0)
            item.representedObject = frameRate
            listVideoFrameRates.menu?.addItem(item)
            
            if videoDevice.activeVideoMinFrameDuration == frameRate.minFrameDuration && videoDevice.activeVideoMaxFrameDuration == frameRate.maxFrameDuration {
                //self.refreshExposure(forFrameRate: frameRate)
                selectedIndex = index
            }
        }
        if 0 <= selectedIndex {
            listVideoFrameRates.selectItem(at: selectedIndex)
        }
    }
    
    func getFormat() -> AVCaptureDevice.Format? {
        if let selectedVideoFormat = listVideoFormats.selectedItem {
            guard let representedObject = selectedVideoFormat.representedObject as? AVCaptureDevice.Format else {
                fatalError("Expected represented object.")
            }
            return representedObject
        }
        return nil
    }
    
    @IBAction func selectFormat(_ sender: NSPopUpButton!) {
        guard let format = self.getFormat() else { return }
        self.refreshFrameRate(forFormat: format)
        
        // update format
        if let videoDevice = self.videoInput?.device {
            self.whileConfiguring {
                videoDevice.activeFormat = format
            }
        }
    }
    
    func getFrameRate() -> AVFrameRateRange? {
        if let selectedFrameRate = listVideoFrameRates.selectedItem {
            guard let representedObject = selectedFrameRate.representedObject as? AVFrameRateRange else {
                fatalError("Expected represented object.")
            }
            return representedObject
        }
        return nil
    }
    
    @IBAction func selectFrameRate(_ sender: NSPopUpButton!) {
        guard let frameRate = self.getFrameRate() else { return }
    
        // update frame rate
        if let videoDevice = self.videoInput?.device {
            // will crash if fails, bad
            self.whileConfiguring {
                videoDevice.activeVideoMinFrameDuration = frameRate.minFrameDuration
                videoDevice.activeVideoMaxFrameDuration = frameRate.maxFrameDuration
            }
        }
    }
    
    @IBAction func toggleAutoExposure(_ sender: NSButton!) {
        let enableAutoExposure: Bool
        switch sender.state {
        case .on:
            enableAutoExposure = true
            break
        default:
            enableAutoExposure = false
            break
        }
        self.sliderExposure.isEnabled = !enableAutoExposure
        
        // update auto exposure
        if let cameraControl = self.uvcCameraControl {
            self.whileConfiguring {
                cameraControl.setAutoExposure(enableAutoExposure)
            }
        }
    }
    
    @IBAction func setExposure(_ sender: NSSlider!) {
        // update exposure
        if let cameraControl = self.uvcCameraControl {
            self.whileConfiguring {
                cameraControl.setExposure(sender.floatValue)
            }
        }
    }
    
    @IBAction func setGain(_ sender: NSSlider!) {
        // update gain
        if let cameraControl = self.uvcCameraControl {
            self.whileConfiguring {
                cameraControl.setGain(sender.floatValue)
            }
        }
    }
    
    @IBAction func toggleAutoWhiteBalance(_ sender: NSButton!) {
        let enableAutoWhiteBalance: Bool
        switch sender.state {
        case .on:
            enableAutoWhiteBalance = true
            break
        default:
            enableAutoWhiteBalance = false
            break
        }
        self.sliderWhiteBalance.isEnabled = !enableAutoWhiteBalance
        
        // update auto white balance
        if let cameraControl = self.uvcCameraControl {
            self.whileConfiguring {
                cameraControl.setAutoWhiteBalance(enableAutoWhiteBalance)
            }
        }
    }
    
    @IBAction func setWhiteBalance(_ sender: NSSlider!) {
        // update white balance
        if let cameraControl = self.uvcCameraControl {
            self.whileConfiguring {
                cameraControl.setWhiteBalance(sender.floatValue)
            }
        }
    }
    
    override func viewWillDisappear() {
        // release camera control
        self.uvcCameraControl = nil
    }
    
    override func viewDidDisappear() {
        // releases represented objects
        listVideoFormats.removeAllItems()
        listVideoFrameRates.removeAllItems()
    }
}
