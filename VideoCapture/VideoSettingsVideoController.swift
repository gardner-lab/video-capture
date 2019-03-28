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

class VideoSettingsVideoController: NSViewController {
    var session: AVCaptureSession?
    var videoInput: AVCaptureDeviceInput?
    
    @IBOutlet var listVideoFormats: NSPopUpButton!
    @IBOutlet var listVideoFrameRates: NSPopUpButton!
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
        
        // list frame rates
        self.refreshFrameRate(forFormat: videoDevice.activeFormat)
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
    
//    @IBAction func selectFrameRate(_ sender: NSPopUpButton!) {
//        guard let frameRate = self.getFrameRate() else { return }
//        self.refreshExposure(forFrameRate: frameRate)
//    }
//    
//    func refreshExposure(forFrameRate: AVFrameRateRange) {
//        
//    }
    
    override func viewWillDisappear() {
        guard let session = self.session else { return }
        guard let videoDevice = self.videoInput?.device else { return }
        
        // lock device for configuration
        try! videoDevice.lockForConfiguration()
        
        // begin session configuration
        session.beginConfiguration()
        
        // configure: format
        if let format = getFormat() {
            videoDevice.activeFormat = format
        }
        
        // configure: frame rate
        if let frameRate = getFrameRate() {
            videoDevice.activeVideoMinFrameDuration = frameRate.minFrameDuration
            videoDevice.activeVideoMaxFrameDuration = frameRate.maxFrameDuration
        }
        
        // commit session configuration
        session.commitConfiguration()
        
        // unlock the device
        videoDevice.unlockForConfiguration()
        
        // TODO: save to document
    }
    
    override func viewDidDisappear() {
        // releases represented objects
        listVideoFormats.removeAllItems()
        listVideoFrameRates.removeAllItems()
    }
}
