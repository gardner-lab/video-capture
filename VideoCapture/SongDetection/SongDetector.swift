//
//  SongDetector.swift
//  SongDetector
//
//  Created by Nathan Perkins on 9/7/15.
//  Copyright © 2015 Gardner Lab. All rights reserved.
//

import Foundation
import Accelerate
import AVFoundation

protocol SongDetectorDelegate: class
{
    func songDetectionDidChangeTo(val: Bool)
}

class SongDetector: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate
{
    let shortTimeFourierTransform: CircularShortTimeFourierTransform
    let samplingRate: Double
    
    // delegate
    weak var delegate: SongDetectorDelegate?
    
    var bandSong: [(Double, Double)] = [(2500, 6700)] {
        didSet {
            self.rangeSong = bandSong.flatMap {
                return self.shortTimeFourierTransform.frequencyIndexRangeFrom($0.0, to: $0.1, forSampleRate: self.samplingRate)
            }
        }
    }
    var bandNonSong: [(Double, Double)] = [(500, 2000)] {
        didSet {
            self.rangeNonSong = bandNonSong.flatMap {
                return self.shortTimeFourierTransform.frequencyIndexRangeFrom($0.0, to: $0.1, forSampleRate: self.samplingRate)
            }
        }
    }
    
    var thresholdSongNonsongRatio = 1.4
    var thresholdSongBackgroundRatio = 1.4
    
    var iterationsAfterSong = 0 // measured in terms of non-overlapping STFT segments
    var secondsAfterSong: Double {
        get {
            let timePerSTFT = shortTimeFourierTransform.timePerSTFT(forSampleRate: samplingRate)
            return Double(iterationsAfterSong) * timePerSTFT
        }
        set {
            let timePerSTFT = shortTimeFourierTransform.timePerSTFT(forSampleRate: samplingRate)
            iterationsAfterSong = Int(newValue / timePerSTFT)
        }
    }
    
    private var rangeSong: [(Int, Int)]
    private var rangeNonSong: [(Int, Int)]
    
    private var smoothBackgroundSong: ExponentialMovingAverage
    private var smoothSong: ExponentialMovingAverage
    private var smoothNonSong: ExponentialMovingAverage
    private var debounceDetection: DebounceBoolean
    
    private var wasDoubleTriggered = false
    private var iterationsRemainingAfterSong: Int = 0
    
    var lastSongNonsongRatio: Double {
        get {
            return smoothSong.lastValue / smoothNonSong.lastValue
        }
    }
    
    var lastSongBackgroundRatio: Double {
        get {
            return smoothSong.lastValue / smoothBackgroundSong.lastValue
        }
    }
    
    var lastDecibelSong: Double {
        get {
            return 20.0 * log10(smoothSong.lastValue)
        }
    }
    
    var lastDetected: Bool {
        get {
            return debounceDetection.lastValue
        }
    }
    
    // parameters in seconds
    var smoothBackgroundTau = 600.0 {
        didSet {
            let timePerSTFT = shortTimeFourierTransform.timePerSTFT(forSampleRate: samplingRate)
            let oldBackgroundSong = smoothBackgroundSong.lastValue
            smoothBackgroundSong = ExponentialMovingAverage(tau: smoothBackgroundTau, timePerSample: timePerSTFT, initial: oldBackgroundSong)
        }
    }
    var smoothTau = 0.0002 {
        didSet {
            let timePerSTFT = shortTimeFourierTransform.timePerSTFT(forSampleRate: samplingRate)
            let oldSong = smoothSong.lastValue, oldNonSong = smoothNonSong.lastValue
            smoothSong = ExponentialMovingAverage(tau: smoothTau, timePerSample: timePerSTFT, initial: oldSong)
            smoothNonSong = ExponentialMovingAverage(tau: smoothTau, timePerSample: timePerSTFT, initial: oldNonSong)
        }
    }
    var debounce = 0.0075 {
        didSet {
            let timePerSTFT = shortTimeFourierTransform.timePerSTFT(forSampleRate: samplingRate)
            let oldDetection = debounceDetection.lastValue
            debounceDetection = DebounceBoolean(checks: Int(round(debounce / timePerSTFT)), initial: oldDetection)
        }
    }
    
    init(samplingRate: Double, stftLength: Int = 128, stftOverlap: Int = 0) {
        // store sampling rate
        self.samplingRate = samplingRate
        
        // make circular STFT
        let stft = CircularShortTimeFourierTransform(windowLength: stftLength, withOverlap: stftOverlap)
        shortTimeFourierTransform = stft
        
        // fill index ranges
        rangeSong = bandSong.flatMap {
            return stft.frequencyIndexRangeFrom($0.0, to: $0.1, forSampleRate: samplingRate)
        }
        rangeNonSong = bandNonSong.flatMap {
            return stft.frequencyIndexRangeFrom($0.0, to: $0.1, forSampleRate: samplingRate)
        }
        
        // create smoothing and debounce
        let timePerSTFT = stft.timePerSTFT(forSampleRate: samplingRate)
        
        smoothSong = ExponentialMovingAverage(tau: smoothTau, timePerSample: timePerSTFT)
        smoothNonSong = ExponentialMovingAverage(tau: smoothTau, timePerSample: timePerSTFT)
        
        smoothBackgroundSong = ExponentialMovingAverage(tau: smoothBackgroundTau, timePerSample: timePerSTFT)
        
        debounceDetection = DebounceBoolean(checks: Int(round(debounce / timePerSTFT)))
        
        // call super initializer
        super.init()
    }
    
    func supportsFormat(audioDescription: AudioStreamBasicDescription) -> Bool {
        // must be linear PCM
        if audioDescription.mFormatID != kAudioFormatLinearPCM {
            return false
        }
        
        // is interleaved
        let isFloat = 0 < (audioDescription.mFormatFlags & kAudioFormatFlagIsFloat)
        
        return isFloat && 32 == audioDescription.mBitsPerChannel
    }
    
    func configureForAudioFormat(audioDescription: AudioStreamBasicDescription) {
        // is interleaved
        let isFloat = 0 < (audioDescription.mFormatFlags & kAudioFormatFlagIsFloat)
        
        DLog("\(isFloat) \(audioDescription.mBitsPerChannel)")
        
        shortTimeFourierTransform.resetWindow()
    }
    
    func processSampleBuffer(sampleBuffer: CMSampleBuffer) {
        // has samples
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard 0 < numSamples else {
            return
        }
        
        // get format
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            DLog("Unable to get format information.")
            return
        }
        let audioDescription = CMAudioFormatDescriptionGetStreamBasicDescription(format)
        
        // checks
        guard audioDescription[0].mFormatID == kAudioFormatLinearPCM else {
            fatalError("Invalid audio format.")
        }
        
        // get audio buffer
        guard let audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            DLog("Unable to get audio buffer.")
            return
        }
        
        // get data pointer
        var lengthAtOffset: Int = 0, totalLength: Int = 0
        var inSamples: UnsafeMutablePointer<Int8> = nil
        CMBlockBufferGetDataPointer(audioBuffer, 0, &lengthAtOffset, &totalLength, &inSamples)
        
        // is interleaved
        let isInterleaved = 1 < audioDescription[0].mChannelsPerFrame && 0 == (audioDescription[0].mFormatFlags & kAudioFormatFlagIsNonInterleaved)
        let isFloat = 0 < (audioDescription[0].mFormatFlags & kAudioFormatFlagIsFloat)
        
        // is float?
        if isFloat {
            switch (isInterleaved, audioDescription[0].mBitsPerChannel) {
            case (true, 64):
                var samples = UnsafeMutablePointer<Float>.alloc(numSamples)
                defer {
                    samples.destroy()
                    samples.dealloc(numSamples)
                }
                
                // double: convert
                vDSP_vdpsp(UnsafeMutablePointer<Double>(inSamples), vDSP_Stride(audioDescription[0].mChannelsPerFrame), samples, 1, vDSP_Length(numSamples))
                shortTimeFourierTransform.appendData(samples, withSamples: numSamples)
                
            case (true, 32):
                // seems dumb, can't find a copy operation
                var samples = UnsafeMutablePointer<Float>.alloc(numSamples)
                defer {
                    samples.destroy()
                    samples.dealloc(numSamples)
                }
                
                // double: convert
                var zero: Float = 0.0
                vDSP_vsadd(UnsafeMutablePointer<Float>(inSamples), vDSP_Stride(audioDescription[0].mChannelsPerFrame), &zero, samples, 1, vDSP_Length(numSamples))
                shortTimeFourierTransform.appendData(samples, withSamples: numSamples)
                
            case (false, 64):
                var samples = UnsafeMutablePointer<Float>.alloc(numSamples)
                defer {
                    samples.destroy()
                    samples.dealloc(numSamples)
                }
                
                // double: convert
                vDSP_vdpsp(UnsafeMutablePointer<Double>(inSamples), 1, samples, 1, vDSP_Length(numSamples))
                shortTimeFourierTransform.appendData(samples, withSamples: numSamples)
                
            case (false, 32):
                // float: add directly
                shortTimeFourierTransform.appendData(UnsafeMutablePointer<Float>(inSamples), withSamples: numSamples)
                
            default:
                fatalError("Unrecognized floating point format.")
            }
        }
        else {
            // all integer formats require a temporary array (maybe a bit wasteful)
            var samples = UnsafeMutablePointer<Float>.alloc(numSamples)
            defer {
                samples.destroy()
                samples.dealloc(numSamples)
            }
            switch (isInterleaved, audioDescription[0].mBitsPerChannel) {
            case (true, 32):
                vDSP_vflt32(UnsafePointer<Int32>(inSamples), vDSP_Stride(audioDescription[0].mChannelsPerFrame), samples, 1, UInt(numSamples))
                
            case (true, 16):
                vDSP_vflt16(UnsafePointer<Int16>(inSamples), vDSP_Stride(audioDescription[0].mChannelsPerFrame), samples, 1, UInt(numSamples))
                
            case (true, 8):
                vDSP_vflt8(UnsafePointer<Int8>(inSamples), vDSP_Stride(audioDescription[0].mChannelsPerFrame), samples, 1, UInt(numSamples))
                
            case (false, 32):
                vDSP_vflt32(UnsafePointer<Int32>(inSamples), 1, samples, 1, UInt(numSamples))
                
            case (false, 16):
                vDSP_vflt16(UnsafePointer<Int16>(inSamples), 1, samples, 1, UInt(numSamples))
                
            case (false, 8):
                vDSP_vflt8(UnsafePointer<Int8>(inSamples), 1, samples, 1, UInt(numSamples))
                
            default:
                fatalError("Unrecognized integer format.")
            }
            
            // append it
            shortTimeFourierTransform.appendData(samples, withSamples: numSamples)
        }
    }
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        processSampleBuffer(sampleBuffer)
        if nil != delegate {
            processNewValues()
        }
    }
    
    func processNewValues() {
        // for each sample
        while processNewValue() {}
    }
    
    func processNewValue() -> Bool {
        guard let power = shortTimeFourierTransform.extractPower() else {
            return false
        }
        
        // extract power
        var powerSong: Double = 0.0, countSong: Int = 0
        var powerNonSong: Double = 0.0, countNonSong: Int = 0
        var ret: Float = 0.0
        
        for (start, end) in rangeSong {
            let len = end - start
            vDSP_sve(UnsafePointer<Float>(power).advancedBy(start), 1, &ret, vDSP_Length(len))
            powerSong += Double(ret)
            countSong += len
        }
        
        for (start, end) in rangeNonSong {
            let len = end - start
            vDSP_sve(UnsafePointer<Float>(power).advancedBy(start), 1, &ret, vDSP_Length(len))
            powerNonSong += Double(ret)
            countNonSong += len
        }
        
        let curPowerSong = smoothSong.ingest(powerSong / Double(countSong))
        let curPowerBackgroundSong = smoothBackgroundSong.ingest(powerSong / Double(countSong))
        let curPowerNonSong = smoothNonSong.ingest(powerNonSong / Double(countNonSong))
        let curRatio = curPowerSong / curPowerNonSong
        let curBackgroundSongRatio = curPowerSong / curPowerBackgroundSong
        
        // get old and new value (to detect change)
        var oldValue = debounceDetection.lastValue
        var newValue = debounceDetection.debounce(curRatio >= thresholdSongNonsongRatio && curBackgroundSongRatio >= thresholdSongBackgroundRatio)
        
        // check for double trigger
        if newValue && !oldValue && !wasDoubleTriggered && iterationsRemainingAfterSong > 0 {
            wasDoubleTriggered = true
        }
        
        // implement iterations after song
        if oldValue && !newValue && iterationsAfterSong > 0 {
            iterationsRemainingAfterSong = iterationsAfterSong * (wasDoubleTriggered ? 2 : 1)
            newValue = true
        }
        else if !oldValue && !newValue && iterationsRemainingAfterSong > 0 {
            // in iterations after song period, pretend like it is still true
            oldValue = true
            
            // decrement, and while still greater than zero, pretend it is true
            // as to only trigger the did change response at the end of the number of iterations
            if 0 < --iterationsRemainingAfterSong {
                newValue = true
            }
        }
        
        // send did change
        if oldValue != newValue {
            delegate?.songDetectionDidChangeTo(newValue)
        }
        
        return true
    }
    
    func isSong() -> Bool {
        processNewValues()
        return lastDetected
    }
}