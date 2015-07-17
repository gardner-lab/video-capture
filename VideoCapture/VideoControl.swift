//
//  VideoController.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 7/17/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Foundation
import AVFoundation

enum VideoControlStatus {
    case None
    case ShouldStart
    case ShouldStop
}

class VideoControl: NSObject, AVCaptureFileOutputDelegate {
    private var status = VideoControlStatus.None
    private var url: NSURL?
    weak private var recordingDelegate: AVCaptureFileOutputRecordingDelegate?
    
    init(parent: AVCaptureFileOutputRecordingDelegate) {
        recordingDelegate = parent
    }
    
    func shouldStart(file: NSURL) {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        
        status = .ShouldStart
        url = file
    }
    
    func shouldStop() {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        
        status = .ShouldStop
    }
    
    func captureOutputShouldProvideSampleAccurateRecordingStart(captureOutput: AVCaptureOutput!) -> Bool {
        return true
    }
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        
        switch status {
        case .ShouldStart where !captureOutput.recording:
            captureOutput.startRecordingToOutputFileURL(url!, recordingDelegate: recordingDelegate)
            url = nil
            status = .None
        case .ShouldStop where captureOutput.recording:
            captureOutput.stopRecording()
            status = .None
        default: break
        }
    }
}
