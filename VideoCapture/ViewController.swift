//
//  ViewController.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 6/28/15.
//  Copyright (c) 2015 GardnerLab. All rights reserved.
//

import Cocoa
import AVFoundation
import CoreFoundation
import CoreGraphics
import CoreImage

class ViewController: NSViewController, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    @IBOutlet var listVideoSources: NSPopUpButton?
    @IBOutlet var listAudioSources: NSPopUpButton?
    @IBOutlet var listSerialPorts: NSPopUpButton?
    @IBOutlet var buttonToggle: NSButton?
    @IBOutlet var previewView: NSView?
    
    var deviceUniqueIDs = [Int: String]()
    
    // session information
    var isRunning = false
    var avSession: AVCaptureSession?
    var avInputVideo: AVCaptureInput?
    var avInputAudio: AVCaptureInput?
    var avPreviewLayer: AVCaptureVideoPreviewLayer?
    var avFileOut: AVCaptureFileOutput?
    var avVideoData: AVCaptureVideoDataOutput?
    
    var avVideoDispatchQueue: dispatch_queue_t?
    
    var ciContext: CIContext?
    
    var buffer: UnsafeMutablePointer<Void> = nil
    var bufferSize = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // fetch devices
        self.updateDeviceLists()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        // initialize preview background
        if let view = self.previewView, let root = view.layer {
            root.backgroundColor = CGColorGetConstantColor(kCGColorBlack)
        }
    }
    
    override func viewWillDisappear() {
        // end any capturing video
        self.stopProcessing()
        
        // end any session
        self.stopSession()
        
        // will disappear
        super.viewWillDisappear();
    }
    
    override func viewDidDisappear() {
        // call above
        super.viewDidDisappear()
        
        // terminate
        NSApp.terminate(nil)
    }

    override var representedObject: AnyObject? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    func updateDeviceLists() {
        // get all AV devices
        let devices = AVCaptureDevice.devices()
        
        // find video devices
        let devices_video = devices.filter({
            d -> Bool in
            let dev: AVCaptureDevice = d as! AVCaptureDevice
            return dev.hasMediaType(AVMediaTypeVideo) || dev.hasMediaType(AVMediaTypeMuxed)
        })
        
        // find the audio devices
        let devices_audio = devices.filter({
            d -> Bool in
            let dev: AVCaptureDevice = d as! AVCaptureDevice
            return dev.hasMediaType(AVMediaTypeAudio) || dev.hasMediaType(AVMediaTypeMuxed)
        })
        
//        let cb = {
//            (d: AnyObject?) -> String in
//            let dev: AVCaptureDevice = d as! AVCaptureDevice
//            return dev.uniqueID // dev.localizedName
//        }
        
        var newDeviceUniqueIDs = [Int: String]()
        var newDeviceIndex = 1
        
        if let list = self.listVideoSources {
            list.removeAllItems()
            list.addItemWithTitle("Video");
            for d in devices_video {
                let dev: AVCaptureDevice = d as! AVCaptureDevice
                let item = NSMenuItem()
                item.title = dev.localizedName
                item.tag = newDeviceIndex
                list.menu?.addItem(item)
                newDeviceUniqueIDs[newDeviceIndex] = dev.uniqueID
                newDeviceIndex++
            }
            list.synchronizeTitleAndSelectedItem()
        }
        
        if let list = self.listAudioSources {
            list.removeAllItems()
            list.addItemWithTitle("Audio")
            for d in devices_audio {
                let dev: AVCaptureDevice = d as! AVCaptureDevice
                let item = NSMenuItem()
                item.title = dev.localizedName
                item.tag = newDeviceIndex
                list.menu?.addItem(item)
                newDeviceUniqueIDs[newDeviceIndex] = dev.uniqueID
                newDeviceIndex++
            }
            list.synchronizeTitleAndSelectedItem()
        }
        
        self.deviceUniqueIDs = newDeviceUniqueIDs
    }
    
    func getVideoDeviceID() -> String? {
        if let list = self.listVideoSources, let selected = list.selectedItem, let deviceUniqueID = self.deviceUniqueIDs[selected.tag] {
            return deviceUniqueID
        }
        return nil
    }
    
    func getAudioDeviceID() -> String? {
        if let list = self.listAudioSources, let selected = list.selectedItem, let deviceUniqueID = self.deviceUniqueIDs[selected.tag] {
            return deviceUniqueID
        }
        return nil
    }
    
    func getDevice(deviceUniqueID: String, mediaTypes: [String]) -> AVCaptureDevice? {
        let dev = AVCaptureDevice(uniqueID: deviceUniqueID)
        if !mediaTypes.isEmpty {
            for mediaType in mediaTypes {
                if dev.hasMediaType(mediaType) {
                    return dev
                }
            }
            return nil
        }
        return dev
    }
    
    func addInput(device: AVCaptureDevice) -> AVCaptureDeviceInput? {
        // has session?
        guard let session = self.avSession else {
            return nil
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                return input
            }
            
            // log error
            NSLog("Unable to add desired input device.")
        }
        catch {
            // log error
            let e = error as NSError
            let desc = e.localizedDescription
            NSLog("Capturing device input failed: \(desc)")
        }
        
        return nil
    }
    
    func promptToStart() {
        guard !self.isRunning else {
            return;
        }
        
        let videoDeviceID = self.getVideoDeviceID()
        let audioDeviceID = self.getAudioDeviceID()
        if nil == videoDeviceID && nil == audioDeviceID {
            NSLog("No device selected.")
            return;
        }
        
        let panel = NSSavePanel()
        panel.title = (nil == videoDeviceID ? "Save Audio" : "Save Movie")
        
        // Let the user select any images supported by
        // the AVMovie.
        if nil != videoDeviceID {
            panel.allowedFileTypes = AVMovie.movieTypes()
            panel.allowsOtherFileTypes = false
            panel.nameFieldStringValue = "output.mov"
        }
        else {
            panel.nameFieldStringValue = "output.aac"
        }
        panel.canCreateDirectories = true
        panel.extensionHidden = false
        
        // callback for handling response
        let cb = {
            (result: Int) -> Void in
            if NSFileHandlingPanelOKButton == result {
                if let url = panel.URL {
                    self.startProcessing(url)
                }
            }
        }
        
        // show
        if let win = NSApp.keyWindow {
            panel.beginSheetModalForWindow(win, completionHandler: cb)
        }
        else {
            panel.beginWithCompletionHandler(cb)
        }
    }
    
    func startSession() {
        if nil == self.avSession {
            // create capture session
            let session = AVCaptureSession.new()
            self.avSession = session
            session.sessionPreset = AVCaptureSessionPresetMedium
            
            session.startRunning()
        }
        
        // preview layer
        if let view = self.previewView {
            let previewLayer = AVCaptureVideoPreviewLayer(session: self.avSession!)
            self.avPreviewLayer = previewLayer
            previewLayer.videoGravity = AVLayerVideoGravityResizeAspect
            previewLayer.frame = view.bounds
            
            // add to view hierarchy
            if let root = view.layer {
                root.backgroundColor = CGColorGetConstantColor(kCGColorBlack)
                root.addSublayer(previewLayer)
            }
        }
    }
    
    func createVideoOutputs(file: NSURL) -> Bool {
        guard let session = self.avSession else {
            return false
        }
        
        // create ci context
        if nil == self.ciContext {
            // options: [kCIContextOutputColorSpace: CGColorSpaceCreateDeviceGray()!] as [String: AnyObject]
            self.ciContext = CIContext()
        }
        
        // raw data
        let videoData = AVCaptureVideoDataOutput()
        self.avVideoData = videoData
        videoData.videoSettings = nil // [kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_16Gray)] as [NSObject: AnyObject] // nil: native format
        videoData.alwaysDiscardsLateVideoFrames = true
        
        // create serial dispatch queue
        let videoDispatchQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL)
        self.avVideoDispatchQueue = videoDispatchQueue
        videoData.setSampleBufferDelegate(self, queue: videoDispatchQueue)
        
        if !session.canAddOutput(videoData) {
            NSLog("Unable to add video data output.")
            return false
        }
        session.addOutput(videoData)
        
        // writer
        let movieOut = AVCaptureMovieFileOutput()
        self.avFileOut = movieOut
        if !session.canAddOutput(movieOut) {
            NSLog("Unable to add movie file output.")
            return false
        }
        session.addOutput(movieOut)
        
        // start writer
        movieOut.startRecordingToOutputFileURL(file, recordingDelegate:self)
        
        return true
    }
    
    func createAudioOutputs(file: NSURL) -> Bool {
        guard let session = self.avSession else {
            return false
        }
        
        // writer
        let audioOut = AVCaptureAudioFileOutput()
        self.avFileOut = audioOut
        if !session.canAddOutput(audioOut) {
            NSLog("Unable to add audio file output.")
            return false
        }
        session.addOutput(audioOut)
        
        // start writer
        audioOut.startRecordingToOutputFileURL(file, recordingDelegate:self)
        
        return true
    }
    
    func startProcessing(file: NSURL) -> Bool {
        guard !self.isRunning else {
            return false;
        }
        
        // get capture device
        if nil == self.avInputVideo && nil == self.avInputAudio {
            NSLog("No device selected.");
            return false;
        }
        
        // disable buttons
        self.listVideoSources?.enabled = false
        self.listAudioSources?.enabled = false
        self.buttonToggle?.title = "Stop Processing"
        
        self.isRunning = true
        
        // SETUP OUTPUTS
        if nil != self.avInputVideo {
            // unable to create video output
            if !self.createVideoOutputs(file) {
                self.stopProcessing()
            }
        }
        else {
            // unable to create audio output
            if !self.createAudioOutputs(file) {
                self.stopProcessing()
            }
        }
        
        return true
    }
    
    func stopProcessing() {
        guard self.isRunning else {
            return;
        }
        
        // stop data output
        if nil != self.avVideoData {
            self.avVideoData = nil;
        }
        
        // release dispatch queue
        if nil != self.avVideoDispatchQueue {
            self.avVideoDispatchQueue = nil;
        }
        
        // stop writing
        if let fileOut = self.avFileOut {
            if fileOut.recording {
                fileOut.stopRecording()
                return
            }
            self.avFileOut = nil
        }
        
        // free up buffer
        if 0 < self.bufferSize {
            free(self.buffer)
            self.buffer = nil
            self.bufferSize = 0
        }
        
        self.isRunning = false
        
        // disable buttons
        self.listVideoSources?.enabled = true
        self.listAudioSources?.enabled = true
        self.buttonToggle?.title = "Start Processing"
    }
    
    func stopSession() {
        // stop inputs
        if let videoInput = self.avInputVideo {
            if nil != self.avSession {
                self.avSession!.removeInput(videoInput)
            }
            self.avInputVideo = nil
        }
        
        if let audioInput = self.avInputAudio {
            if nil != self.avSession {
                self.avSession!.removeInput(audioInput)
            }
            self.avInputAudio = nil
        }
        
        // stop session
        if let session = self.avSession {
            session.stopRunning()
            
            self.avSession = nil
        }
        
        // release preview layer
        if let previewLayer = self.avPreviewLayer {
            previewLayer.removeFromSuperlayer()
            previewLayer.session = nil
            self.avPreviewLayer = nil
        }
    }

    @IBAction func selectVideoSource(sender: AnyObject?) {
        if let s = sender, let button = s as? NSPopUpButton, let selected = button.selectedItem, let deviceUniqueID = self.deviceUniqueIDs[selected.tag] {
            NSLog("Device ID: \(deviceUniqueID)")
            
            // get existing device
            if nil != self.avInputVideo {
                // should be defined
                assert(nil != self.avSession)
                
                if let inputVideoDevice = self.avInputVideo! as? AVCaptureDeviceInput {
                    if inputVideoDevice.device.uniqueID == deviceUniqueID {
                        NSLog("Same device.")
                        return
                    }
                }
                
                // remove existing
                self.avSession!.removeInput(self.avInputVideo!)
                self.avInputVideo = nil
            }
            else {
                // start sesion
                self.startSession()
            }
            
            // get device and add it
            if let videoDevice = self.getDevice(deviceUniqueID, mediaTypes: [AVMediaTypeVideo, AVMediaTypeMuxed]) {
                // add input
                self.avInputVideo = self.addInput(videoDevice)
                
                // start preview layer
                if nil != self.avInputVideo {
                    // update preview layer
                    if let previewLayer = self.avPreviewLayer {
                        previewLayer.connection.automaticallyAdjustsVideoMirroring = false
                        previewLayer.connection.videoMirrored = false
                    }
                }
            }
        }
        else {
            if nil != self.avInputVideo {
                // should be defined
                assert(nil != self.avSession)
                
                
                // remove video
                self.avSession!.removeInput(self.avInputVideo!)
                self.avInputVideo = nil
            }
        }
    }
    
    @IBAction func selectAudioSource(sender: AnyObject?) {
        if let s = sender, let button = s as? NSPopUpButton, let selected = button.selectedItem, let deviceUniqueID = self.deviceUniqueIDs[selected.tag] {
            NSLog("Device ID: \(deviceUniqueID)")
            
            // get existing device
            if nil != self.avInputAudio {
                // should be defined
                assert(nil != self.avSession)
                
                if let inputAudioDevice = self.avInputAudio! as? AVCaptureDeviceInput {
                    if inputAudioDevice.device.uniqueID == deviceUniqueID {
                        NSLog("Same device.")
                        return
                    }
                }
                
                // remove existing
                self.avSession!.removeInput(self.avInputAudio!)
                self.avInputAudio = nil
            }
            else {
                // start sesion
                self.startSession()
            }
            
            // get device and add it
            if let audioDevice = self.getDevice(deviceUniqueID, mediaTypes: [AVMediaTypeAudio, AVMediaTypeMuxed]) {
                self.avInputAudio = self.addInput(audioDevice)
            }
        }
        else {
            if nil != self.avInputAudio {
                // should be defined
                assert(nil != self.avSession)
                
                
                // remove audio
                self.avSession!.removeInput(self.avInputAudio!)
                self.avInputAudio = nil
            }
        }
    }
    
    @IBAction func selectSerialPort(sender: AnyObject?) {
        
    }

    @IBAction func toggleProcessing(sender: AnyObject?) {
        if (self.isRunning) {
            // stop processing
            self.stopProcessing()
        }
        else {
            // start processing
            self.promptToStart()
        }
    }
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError?) {
        var success = true;
        
        if let e = error where noErr != OSStatus(e.code) {
            if let val = e.userInfo[AVErrorRecordingSuccessfullyFinishedKey] {
                if let b = val as? Bool {
                    success = b
                }
            }
        }
        
        if (success) {
            NSLog("Success!")
        }
        else {
            NSLog("Failure! \(error)")
            
            // clear move
            self.avFileOut = nil
            
            // stop processing
            self.stopProcessing()
            
            // show alert
            let alert = NSAlert()
            alert.messageText = "Unable to process"
            if let e = error {
                alert.informativeText = e.localizedDescription
            }
            else {
                alert.informativeText = "An unknown error occurred."
            }
            alert.addButtonWithTitle("Ok")
            if let win = NSApp.keyWindow {
                alert.beginSheetModalForWindow(win, completionHandler:nil)
            }
            else {
                alert.runModal()
            }

            
            return
        }
        
        // still recording? likely switched files
        if let fileOut = self.avFileOut where fileOut.recording {
            return
        }
        
        // called as part of the stopping process
        self.stopProcessing()
    }
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        // get image buffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
//        if let a = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate) {
//            let attachments = a.takeRetainedValue() as NSDictionary
//        }
        
        let image = CIImage(CVImageBuffer: imageBuffer) //, options: attachments) // , options:attachments)
        
//        if nil == self.cgBitmapContext || self.lastExtent != image.extent {
//            // release existing
//            self.cgBitmapContext = nil
//            
//            // create new
//            let cgColorSpace = CGColorSpaceCreateDeviceGray()
//            self.cgBitmapContext = CGBitmapContextCreate(nil, Int(image.extent.width), Int(image.extent.height), 8, 0, cgColorSpace, CGImageAlphaInfo.None.rawValue)
//            
//            // store last extent
//            self.lastExtent = image.extent
//            
//            // failed
//            if nil == self.cgBitmapContext {
//                NSLog("Unable to create bitmap context.")
//                self.stopProcessing()
//                return;
//            }
//        }
        
        let bounds = image.extent, width = Int(bounds.width), height = Int(bounds.height)
        let bytesPerPixel: Int = 4 // four bytes per pixel kCIFormatARGB8
        let bytesPerRow = Int(bytesPerPixel * width)
        let bytesTotal = bytesPerRow * height
        
        // adjust buffer
        if bytesTotal > self.bufferSize {
            free(self.buffer)
            self.buffer = calloc(bytesTotal, sizeof(UInt8))
            self.bufferSize = bytesTotal
        }
        
        self.ciContext?.render(image, toBitmap: self.buffer, rowBytes: bytesPerRow, bounds: bounds, format: kCIFormatARGB8, colorSpace: nil)
        
        let bytes = UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>(self.buffer), count: Int(bytesTotal))
        var q: Int, brightnessByQuadrant: [Double] = [0, 0, 0, 0], halfWidth: Int = width / 2, halfHeight: Int = height / 2
        for (var i = 0, x = 0, y = 0; i < bytesTotal; i += bytesPerPixel) {
            // maintain coordinates
            if width == ++x {
                x = 0
                ++y
            }
            
            // get quadrant
            switch (x >= halfWidth, y >= halfHeight) {
            case (false, false):
                q = 0
            case (true, false):
                q = 1
            case (false, true):
                q = 2
            case (true, true):
                q = 3
            }
            
            // calculate brightness
            let red = Double(bytes[i + 1]), green = Double(bytes[i + 2]), blue = Double(bytes[i + 3])
            let brightness = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            
            brightnessByQuadrant[q] += brightness
        }
        
//        let avg = 4.0 / (Double(width) * Double(height))
//        for (lq, l) in [self.labelTopLeft, self.labelTopRight, self.labelBottomLeft, self.labelBottomRight].enumerate() {
//            if let label = l {
//                let val = Int(brightnessByQuadrant[lq] * avg)
//                label.stringValue = "\(val)"
//            }
//        }
    }
}

