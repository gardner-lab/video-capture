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
import ORSSerial

class ViewController: NSViewController, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, NSTableViewDelegate, NSTableViewDataSource, AnnotableViewerDelegate, ArduinoIODelegate {
    @IBOutlet var listVideoSources: NSPopUpButton?
    @IBOutlet var listAudioSources: NSPopUpButton?
    @IBOutlet var listSerialPorts: NSPopUpButton?
    @IBOutlet var sliderLedBrightness: NSSlider?
    @IBOutlet var buttonToggle: NSButton?
    @IBOutlet var previewView: NSView?
    @IBOutlet var annotableView: AnnotableViewer? {
        didSet {
            oldValue?.delegate = nil
            annotableView?.delegate = self
            annotableView?.wantsLayer = true
        }
    }
    @IBOutlet var tableAnnotations: NSTableView? {
        didSet {
            oldValue?.setDelegate(nil)
            oldValue?.setDataSource(nil)
            tableAnnotations?.setDelegate(self)
            tableAnnotations?.setDataSource(self)
        }
    }
    
    var deviceUniqueIDs = [Int: String]()
    
    var editable = true {
        didSet {
            listVideoSources?.enabled = editable
            listAudioSources?.enabled = editable
            listSerialPorts?.enabled = editable
            sliderLedBrightness?.enabled = editable && nil != ioArduino
            if let tv = tableAnnotations {
                let col = tv.columnWithIdentifier("name")
                if 0 <= col {
                    tv.tableColumns[col].editable = editable
                }
            }
        }
    }
    
    // app preferences
    var appPreferences = Preferences()
    
    // session information
    var isRunning = false
    var avSession: AVCaptureSession?
    var avInputVideo: AVCaptureInput? {
        willSet {
            // turn on power
            if nil != ioArduino {
                do {
                    try ioArduino?.writeTo(appPreferences.pinDigitalCamera, digitalValue: nil != newValue)
                }
                catch {
                    DLog("ERROR Unable to toggle camera power.")
                }
            }
        }
    }
    var avInputAudio: AVCaptureInput?
    var avPreviewLayer: AVCaptureVideoPreviewLayer?
    var avFileOut: AVCaptureFileOutput?
    var avVideoData: AVCaptureVideoDataOutput?
    var dataOut: NSFileHandle?
    
    var avVideoDispatchQueue: dispatch_queue_t?
    
    // serial communications
    var ioArduino: ArduinoIO? {
        didSet {
            oldValue?.delegate = nil
            ioArduino?.delegate = self
            
            // update serial port
            sliderLedBrightness?.enabled = editable && nil != ioArduino
        }
    }
    
    // extraction information
    var extractValues: [Float] = []
    var extractBounds = CGSize(width: 0.0, height: 0.0)
    var extractArray: [(pixel: Int, annotation: Int)] = []
    
    // timer to redraw interface (saves time)
    var timerRedraw: NSTimer?
    
    
    // timer to dim LED and turn off camera
    var timerRevertMode: NSTimer?
    
    // used by manual reading system
    var ciContext: CIContext?
    var buffer: UnsafeMutablePointer<Void> = nil
    var bufferSize = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // fetch devices
        updateDeviceLists()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        // listen for serial changes
        let nc = NSNotificationCenter.defaultCenter()
        nc.addObserver(self, selector: "serialPortsWereConnected:", name: ORSSerialPortsWereConnectedNotification, object: nil)
        nc.addObserver(self, selector: "serialPortsWereDisconnected:", name: ORSSerialPortsWereDisconnectedNotification, object: nil)
        
        // initialize preview background
        if let view = previewView, let root = view.layer {
            root.backgroundColor = CGColorGetConstantColor(kCGColorBlack)
        }
        
        if let view = annotableView, let root = view.layer {
            view.wantsLayer = true
            root.zPosition = 1.0
        }
    }
    
    override func viewWillDisappear() {
        // remove notification center
        NSNotificationCenter.defaultCenter().removeObserver(self)
        
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
        //NSApp.terminate(nil)
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
        
        // video sources
        if let list = self.listVideoSources {
            list.removeAllItems()
            list.addItemWithTitle("Video")
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
        
        // audio sources
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
        
        // serial ports
        if let list = self.listSerialPorts {
            list.removeAllItems()
            list.addItemWithTitle("Arduino")
            for port in ORSSerialPortManager.sharedSerialPortManager().availablePorts as! [ORSSerialPort] {
                let item = NSMenuItem()
                item.title = port.name
                item.tag = newDeviceIndex
                list.menu?.addItem(item)
                newDeviceUniqueIDs[newDeviceIndex] = port.path
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
        
        // raw data
        let videoData = AVCaptureVideoDataOutput()
        self.avVideoData = videoData
        videoData.videoSettings = nil // nil: native format
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
            DLog("Unable to add audio file output.")
            return false
        }
        session.addOutput(audioOut)
        
        // start writer
        audioOut.startRecordingToOutputFileURL(file, recordingDelegate:self)
        
        return true
    }
    
    private func openDataFile(dataFile: NSURL) -> Bool {
        // get annotable view
        guard let annotView = self.annotableView else {
            return false
        }
        
        // no annotations
        guard annotView.annotations.count > 0 else {
            return false
        }
        
        // get file path
        guard let path = dataFile.path else {
            return false
        }
        
        // create file
        guard NSFileManager.defaultManager().createFileAtPath(path, contents: nil, attributes: nil) else {
            DLog("Unable to create data file: \(dataFile.path)")
            return false
        }
        
        // file handle
        let fileHandle: NSFileHandle
        
        // get file handle
        do {
            fileHandle = try NSFileHandle(forWritingToURL: dataFile)
        }
        catch {
            DLog("Unable to open data file handle: \(error)")
            return false
        }
        
        // write header information
        var headers = "Name"
        for annot in annotView.annotations {
            headers += ",\(annot.name)"
        }
        headers += "\n"
        
        // write data
        if let data = headers.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true) {
            fileHandle.writeData(data)
        }
        
        // store data output stream
        dataOut = fileHandle
        
        return true
    }
    
    func startProcessing(file: NSURL) -> Bool {
        guard !isRunning else {
            return false
        }
        
        // get capture device
        if nil == avInputVideo && nil == avInputAudio {
            DLog("No device selected.");
            return false;
        }
        
        // disable buttons
        editable = false
        buttonToggle?.title = "Stop Capturing"
        
        isRunning = true
        
        // SETUP OUTPUTS
        if nil != avInputVideo {
            // unable to create video output
            if !createVideoOutputs(file) {
                stopProcessing()
                return false
            }
            
            // file for data
            if let fileForData = file.URLByDeletingPathExtension?.URLByAppendingPathExtension("csv") {
                openDataFile(fileForData)
            }
        }
        else {
            // unable to create audio output
            if !createAudioOutputs(file) {
                stopProcessing()
                return false
            }
        }
        
        // setup timer
        timerRedraw = NSTimer.scheduledTimerWithTimeInterval(0.1, target: self, selector: "timerUpdateValues:", userInfo: nil, repeats: true)
        
        return true
    }
    
    func stopProcessing() {
        guard isRunning else {
            return;
        }
        
        // stop timer
        if nil != self.timerRedraw {
            self.timerRedraw!.invalidate()
            self.timerRedraw = nil
        }
        
        // stop data output
        if nil != avVideoData {
            if nil != avSession {
                avSession!.removeOutput(avVideoData!)
            }
            avVideoData = nil
        }
        
        // release dispatch queue
        if nil != avVideoDispatchQueue {
            avVideoDispatchQueue = nil
        }
        
        // close file
        if nil != dataOut {
            dataOut?.closeFile()
            dataOut = nil
        }
        
        // stop writing
        if let fileOut = avFileOut {
            if fileOut.recording {
                fileOut.stopRecording()
                return
            }
            if nil != avSession {
                avSession!.removeOutput(avFileOut!)
            }
            avFileOut = nil
        }
        
        // free up buffer
        if 0 < bufferSize {
            free(buffer)
            buffer = nil
            bufferSize = 0
        }
        
        isRunning = false
        
        // disable buttons
        buttonToggle?.title = "Start Capturing"
        editable = true
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
        
        // release arduino
        if nil != self.ioArduino {
            self.ioArduino = nil
        }
    }

    @IBAction func selectVideoSource(sender: AnyObject?) {
        if let s = sender, let button = s as? NSPopUpButton, let selected = button.selectedItem, let deviceUniqueID = deviceUniqueIDs[selected.tag] {
            DLog("Device ID: \(deviceUniqueID)")
            
            // get existing device
            if nil != avInputVideo {
                // should be defined
                assert(nil != avSession)
                
                if let inputVideoDevice = avInputVideo! as? AVCaptureDeviceInput {
                    if inputVideoDevice.device.uniqueID == deviceUniqueID {
                        DLog("Same device.")
                        return
                    }
                }
                
                // remove existing
                avSession!.removeInput(avInputVideo!)
                avInputVideo = nil
            }
            else {
                // start sesion
                startSession()
            }
            
            // get device and add it
            if let videoDevice = getDevice(deviceUniqueID, mediaTypes: [AVMediaTypeVideo, AVMediaTypeMuxed]) {
                // add input
                avInputVideo = addInput(videoDevice)
                
                // start preview layer
                if nil != avInputVideo {
                    // update preview layer
                    if let previewLayer = avPreviewLayer {
                        previewLayer.connection.automaticallyAdjustsVideoMirroring = false
                        previewLayer.connection.videoMirrored = false
                        
                        NSLog("\(previewLayer.frame)")
                    }
                }
            }
        }
        else {
            if nil != avInputVideo {
                // should be defined
                assert(nil != avSession)
                
                
                // remove video
                avSession!.removeInput(avInputVideo!)
                avInputVideo = nil
            }
        }
    }
    
    @IBAction func selectAudioSource(sender: AnyObject?) {
        if let s = sender, let button = s as? NSPopUpButton, let selected = button.selectedItem, let deviceUniqueID = deviceUniqueIDs[selected.tag] {
            DLog("Device ID: \(deviceUniqueID)")
            
            // get existing device
            if nil != avInputAudio {
                // should be defined
                assert(nil != avSession)
                
                if let inputAudioDevice = avInputAudio! as? AVCaptureDeviceInput {
                    if inputAudioDevice.device.uniqueID == deviceUniqueID {
                        DLog("Same device.")
                        return
                    }
                }
                
                // remove existing
                avSession!.removeInput(avInputAudio!)
                avInputAudio = nil
            }
            else {
                // start sesion
                startSession()
            }
            
            // get device and add it
            if let audioDevice = getDevice(deviceUniqueID, mediaTypes: [AVMediaTypeAudio, AVMediaTypeMuxed]) {
                avInputAudio = addInput(audioDevice)
            }
        }
        else {
            if nil != avInputAudio {
                // should be defined
                assert(nil != self.avSession)
                
                
                // remove audio
                avSession!.removeInput(avInputAudio!)
                avInputAudio = nil
            }
        }
    }
    
    @IBAction func selectSerialPort(sender: AnyObject?) {
        if let s = sender, let button = s as? NSPopUpButton, let selected = button.selectedItem, let devicePath = deviceUniqueIDs[selected.tag] {
            DLog("Device Path: \(devicePath)")
            
            // get existing device
            if nil != ioArduino {
                if ioArduino!.serial?.path == devicePath {
                    DLog("Same device.")
                    return
                }
                
                // remove device
                ioArduino = nil
            }
            
            // open new port
            do {
                try ioArduino = ArduinoIO(path: devicePath)
                try ioArduino!.setPinMode(appPreferences.pinDigitalCamera, to: ArduinoIOPin.Output) // pin 4: digital camera relay
                try ioArduino!.setPinMode(appPreferences.pinDigitalWhiteNoise, to: ArduinoIOPin.Output) // pin 9: digital white noise stimulation
                try ioArduino!.setPinMode(appPreferences.pinAnalogLED, to: ArduinoIOPin.Output) // pin 13: analog brightness
                //try ioArduino!.setPinMode(appPreferences.pinAnalogTrigger, to: ArduinoIOPin.Input) // pin: 0 analog trigger
                
                // turn camera on, if already selected
                if nil != self.avInputVideo {
                    try ioArduino!.writeTo(appPreferences.pinDigitalCamera, digitalValue: true)
                }
            }
            catch {
                ioArduino = nil
            }
        }
        else {
            // has open port?
            if nil != ioArduino {
                // remove open port
                ioArduino = nil
            }
        }
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
            DLog("CAPTURE success!")
        }
        else {
            DLog("CAPTURE failure: \(error)")
            
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
    
    private func updateExtractionList(dimensions: CGSize) { // , _ rep: NSBitmapImageRep
        // build mapping between square annotable dimensions and recntagular video dimensions
        // including the largest dimension, which servers as the sacling factor
        let maxDim: CGFloat, videoFrame: CGRect
        if dimensions.width > dimensions.height {
            maxDim = dimensions.width
            videoFrame = CGRect(origin: CGPoint(x: 0.0, y: (maxDim - dimensions.height) / 2.0), size: dimensions)
        }
        else if dimensions.height > dimensions.width {
            maxDim = dimensions.height
            videoFrame = CGRect(origin: CGPoint(x: (maxDim - dimensions.width) / 2.0, y: 0.0), size: dimensions)
        }
        else {
            maxDim = dimensions.width
            videoFrame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: dimensions)
        }
        let maxX = Int(dimensions.width), maxY = Int(dimensions.height)
        
        extractArray.removeAll()
        if let view = self.annotableView {
            for (i, annot) in view.annotations.enumerate() {
                
                // generate image coordinates
                for (x, y) in annot.generateImageCoordinates(videoFrame) {
                    // NSLog("x: \(x), y: \(y)")
                    if x < 0 || x >= maxX || y < 0 || y >= maxY {
                        continue
                    }
                    
                    // debugging
//                    rep.setColor(annot.color, atX: x, y: y)
                    
                    extractArray.append(pixel: maxX * y + x, annotation: i)
                }
            }
            
            // string for describing output (stored to shape)
            if nil != self.dataOut {
                var regionString = "Region"
                for annot in view.annotations {
                    regionString += ",\"" + annot.generateImageDescription(videoFrame) + "\""
                }
                regionString += "\n"
                
                // write data
                if let data = regionString.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true) {
                    self.dataOut?.writeData(data)
                }
            }
        }

        // debugging
//        let prop = [String : AnyObject]()
//        let data = rep.representationUsingType(NSBitmapImageFileType.NSPNGFileType, properties: prop)
//        data?.writeToURL(NSURL(fileURLWithPath: "/Users/nathan/Desktop/debug.png"), atomically: false)
        
    }
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        // get image buffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        var annotSum: [Float]
        var annotCnt: [Int]
        
        if kCVPixelFormatType_422YpCbCr8 == CVPixelBufferGetPixelFormatType(imageBuffer) {
            // express processing, access buffer directly

            let width = CVPixelBufferGetWidth(imageBuffer), height = CVPixelBufferGetHeight(imageBuffer)
            let boundsSize = CGSize(width: width, height: height)
            
            // check extraction list
            if boundsSize != extractBounds {
                // update extraction list
                updateExtractionList(boundsSize)
                
                // update extract bounds
                extractBounds = boundsSize
            }
            
            // lock buffer
            CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
            
            // get buffer
            let bytesPerPixel = 2
            let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
            let bytesTotal = bytesPerRow * height
            let bytes = UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>(CVPixelBufferGetBaseAddress(imageBuffer)), count: Int(bytesTotal))
            
            annotSum = [Float](count: extractValues.count, repeatedValue: 0.0)
            annotCnt = [Int](count: extractValues.count, repeatedValue: 0)
            for (pixel, annotIdx) in extractArray {
                if annotIdx >= annotSum.count {
                    continue
                }
                let i = pixel * bytesPerPixel + 1
                let brightness = Float(bytes[i])
                
                // increment values
                annotSum[annotIdx] += brightness
                annotCnt[annotIdx]++
            }
            
            // unlock buffer
            CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        }
        else {
            //        if let a = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate) {
            //            let attachments = a.takeRetainedValue() as NSDictionary
            //        }
            
            let image = CIImage(CVImageBuffer: imageBuffer) //, options: attachments) // , options:attachments)
            
            let bounds = image.extent, width = Int(bounds.size.width), height = Int(bounds.size.height)
            let bytesPerPixel: Int = 4 // four bytes per pixel kCIFormatARGB8
            let bytesPerRow = Int(bytesPerPixel * width)
            let bytesTotal = bytesPerRow * height
            
            // check extraction list
            if bounds.size != extractBounds {
                DLog("Using slower processing chain.")
                
                //            let rep = NSBitmapImageRep(CIImage: image)
                //            let img = NSImage(size: rep.size)
                //            img.addRepresentation(rep)
                //
                // update extraction list
                updateExtractionList(bounds.size)
                
                
                // update extract bounds
                extractBounds = bounds.size
            }
            
            // check that context exists
            if nil == self.ciContext {
                self.ciContext = CIContext()
            }
            
            // adjust buffer
            if bytesTotal > self.bufferSize {
                free(self.buffer)
                self.buffer = calloc(bytesTotal, sizeof(UInt8))
                self.bufferSize = bytesTotal
            }
            
            self.ciContext?.render(image, toBitmap: self.buffer, rowBytes: bytesPerRow, bounds: bounds, format: kCIFormatARGB8, colorSpace: nil)
            
            let bytes = UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>(self.buffer), count: Int(bytesTotal))
            annotSum = [Float](count: extractValues.count, repeatedValue: 0.0)
            annotCnt = [Int](count: extractValues.count, repeatedValue: 0)
            for (pixel, annotIdx) in extractArray {
                if annotIdx >= annotSum.count {
                    continue
                }
                let i = pixel * bytesPerPixel
                let red = Float(bytes[i + 1]), green = Float(bytes[i + 2]), blue = Float(bytes[i + 3])
                let brightness = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                
                // increment values
                annotSum[annotIdx] += brightness
                annotCnt[annotIdx]++
            }
        }
        
        // update values
        extractValues = zip(annotSum, annotCnt).map {
            sum, cnt in return cnt > 0 ? sum / Float(cnt) : 0.0
        }
        
        // string
        if nil != self.dataOut {
            // get timestamp
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer), timestampAsSeconds = CMTimeGetSeconds(timestamp)
            
            // build sample string
            var sampleString = "\(timestampAsSeconds)"
            for val in extractValues {
                sampleString += ",\(val)"
            }
            sampleString += "\n"
            
            // write data
            if let data = sampleString.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true) {
                self.dataOut?.writeData(data)
            }
        }
    }
    
    func timerUpdateValues(timer: NSTimer!) {
        if let tv = self.tableAnnotations {
            tv.reloadDataForRowIndexes(NSIndexSet(indexesInRange: NSRange(location: 0, length: extractValues.count)), columnIndexes: NSIndexSet(index: 2))
        }
    }
    
    func didChangeAnnotations(newAnnotations: [Annotation]) {
        // clear extract values
        extractValues = [Float](count: newAnnotations.count, repeatedValue: 0.0)
        
        // reset bounds (force reloading list of pixels)
        extractBounds = CGSize(width: 0.0, height: 0.0)
        
        // force redrawing of table
        tableAnnotations?.reloadData()
    }
    
    func numberOfRowsInTableView(tableView: NSTableView) -> Int {
        guard let annotView = self.annotableView else {
            return 0
        }
        return annotView.annotations.count
    }
    
    func tableView(tableView: NSTableView, objectValueForTableColumn tableColumn: NSTableColumn?, row: Int) -> AnyObject? {
        guard let col = tableColumn, let annotView = self.annotableView else {
            return nil
        }
        
        // handle column identifiers
        switch (col.identifier) {
        case "color":
            if row < annotView.annotations.count {
                return annotView.annotations[row].color
            }
            return nil
        case "name":
            if row < annotView.annotations.count {
                return annotView.annotations[row].name
            }
            return "ROI"
        case "value":
            if row < extractValues.count {
                return Int(extractValues[row])
            }
            return nil
        default:
            return nil
        }
    }
    
    func tableView(tableView: NSTableView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, row: Int) {
        guard let col = tableColumn, let annotView = self.annotableView else {
            return
        }
        
        if "name" == col.identifier && row < annotView.annotations.count {
            if let newName = object as? String {
                annotView.annotations[row].name = newName
            }
        }
    }
    
    // serial port
    func serialPortsWereConnected(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let connectedPorts = userInfo[ORSConnectedSerialPortsKey] as! [ORSSerialPort]
            NSLog("Ports were connected: \(connectedPorts)")
            updateDeviceLists()
        }
    }
    
    func serialPortsWereDisconnected(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let disconnectedPorts: [ORSSerialPort] = userInfo[ORSDisconnectedSerialPortsKey] as! [ORSSerialPort]
            NSLog("Ports were disconnected: \(disconnectedPorts)")
            updateDeviceLists()
        }
    }
    
    // arduino protocol
    
    func resetArduino() {
        DLog("ARDUINO reset")
        
        if isRunning {
            stopProcessing()
        }
        
        // clear arduino
        ioArduino = nil
        
        // reset arduino selection
        listAudioSources?.selectItemAtIndex(0)
    }
    
    @IBAction func setLedBrightness(sender: AnyObject?) {
        if let s = sender, let slider = s as? NSSlider, let arduino = self.ioArduino {
            do {
                DLog("ARDUINO brightness \(slider.integerValue)")
                try arduino.writeTo(13, analogValue: UInt8(slider.integerValue))
            }
            catch {
                DLog("ARDUINO brightness: failed! \(error)")
            }
        }
    }
    
    func arduinoError(message: String, isPermanent: Bool) {
        DLog("Arduino Error: \(message)")
        
        // permanent error
        if isPermanent {
            resetArduino()
        }
    }
}

