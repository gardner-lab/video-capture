//
//  VideoController.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 7/17/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Foundation
import AVFoundation

class CaptureControl: NSObject, AVCaptureFileOutputDelegate {
    enum Status {
        case none
        case shouldStart
        case shouldStop
    }
    
    private var status = CaptureControl.Status.none
    private var url: URL?
    private var outputFileType: AVFileType
    weak private var recordingDelegate: AVCaptureFileOutputRecordingDelegate?
    
    init(parent: AVCaptureFileOutputRecordingDelegate, outputFileType: AVFileType = AVFileType.m4a) {
        self.recordingDelegate = parent
        self.outputFileType = outputFileType
    }
    
    func shouldStart(_ file: URL) {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        
        status = .shouldStart
        url = file
    }
    
    func shouldStop() {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        
        status = .shouldStop
    }
    
    func fileOutputShouldProvideSampleAccurateRecordingStart(_ captureOutput: AVCaptureFileOutput) -> Bool {
        return true
    }
    
    func fileOutput(_ captureOutput: AVCaptureFileOutput, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        
        switch status {
        case .shouldStart where !captureOutput.isRecording:
            if let captureAudioOutput = captureOutput as? AVCaptureAudioFileOutput {
                captureAudioOutput.startRecording(to: url!, outputFileType: outputFileType, recordingDelegate: recordingDelegate!)
            }
            else {
                captureOutput.startRecording(to: url!, recordingDelegate: recordingDelegate!)
            }
            url = nil
            status = .none
        case .shouldStop where captureOutput.isRecording:
            captureOutput.stopRecording()
            status = .none
        default: break
        }
    }
}
