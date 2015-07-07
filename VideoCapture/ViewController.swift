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

/// The video capture mode determines interface accessibility
enum VideoCaptureMode {
    case Configure
    case Monitor // monitor for triggering
    case TriggeredCapture // capturing, because triggered
    case ManualCapture // capturing, because manually triggered
    
    func isMonitoring() -> Bool {
        return self == .TriggeredCapture || self == .Monitor
    }
    
    func isCapturing() -> Bool {
        return self == .TriggeredCapture || self == .ManualCapture
    }
    
    func isEditable() -> Bool {
        return self == .Configure
    }
}

class ViewController: NSViewController, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, NSTableViewDelegate, NSTableViewDataSource, AnnotableViewerDelegate, ArduinoIODelegate {
    // document mode
    var mode = VideoCaptureMode.Configure {
        didSet {
            refreshInterface()
        }
    }
    
    @IBOutlet var textName: NSTextField?
    @IBOutlet var listVideoSources: NSPopUpButton?
    @IBOutlet var listAudioSources: NSPopUpButton?
    @IBOutlet var listSerialPorts: NSPopUpButton?
    @IBOutlet var sliderLedBrightness: NSSlider?
    @IBOutlet var buttonCapture: NSButton?
    @IBOutlet var buttonMonitor: NSButton?
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
    
    // app preferences
    var appPreferences = Preferences()
    
    // session information
    var avSession: AVCaptureSession?
    var avInputVideo: AVCaptureInput? {
        willSet {
            // has arduino?
            if let arduino = ioArduino {
                // toggle pin
                do {
                    try arduino.writeTo(appPreferences.pinDigitalCamera, digitalValue: nil != newValue)
                }
                catch {
                    DLog("ERROR Unable to toggle camera power.")
                }
            }
        }
        didSet {
            // update interface options
            refreshInterface()
            
            // changed state
            if (nil == oldValue) != (nil == avInputVideo) {
                refreshOutputs()
            }
        }
    }
    var avInputAudio: AVCaptureInput? {
        didSet {
            refreshInterface()
            
            // changed state
            if (nil == oldValue) != (nil == avInputAudio) {
                refreshOutputs()
            }
        }
    }
    var avPreviewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            // clean up old value
            if let oldPreviewLayer = oldValue {
                oldPreviewLayer.removeFromSuperlayer()
                oldPreviewLayer.session = nil
            }
            // setup new value
            if let newPreviewLayer = avPreviewLayer {
                newPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspect
                
                // add it
                if let containingView = self.previewView {
                    newPreviewLayer.frame = containingView.bounds
                
                    // add to view hierarchy
                    if let root = containingView.layer {
                        root.backgroundColor = CGColorCreateGenericGray(0.2, 1.0)
                        //CGColorGetConstantColor(kCGColorBlack)
                        root.addSublayer(newPreviewLayer)
                    }
                }
            }
        }
    }
    var avFileOut: AVCaptureFileOutput?
    var avVideoData: AVCaptureVideoDataOutput?
    var dirOut: NSURL?
    var dataOut: NSFileHandle?
    
    var avVideoDispatchQueue: dispatch_queue_t?
    
    // should be unused
    override var representedObject: AnyObject? {
        didSet {
            DLog("SET")
        }
    }
    var document: Document?
    
    // serial communications
    var ioArduino: ArduinoIO? {
        didSet {
            oldValue?.delegate = nil
            ioArduino?.delegate = self
            
            // refresh interface
            refreshInterface()
        }
    }
    
    // extraction information
    var extractValues: [Float] = []
    var extractBounds = CGSize(width: 0.0, height: 0.0)
    var extractArray: [(pixel: Int, annotation: Int)] = []
    
    // timer to redraw interface (saves time)
    var timerRedraw: NSTimer?
    
    // timer to dim LED and turn off camera
    //var timerRevertMode: NSTimer?
    
    // timer for monitoring
    var timerMonitor: NSTimer?
    
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
        nc.addObserver(self, selector: "avDeviceWasConnected:", name: AVCaptureDeviceWasConnectedNotification, object: nil)
        nc.addObserver(self, selector: "avDeviceWasDisconnected:", name: AVCaptureDeviceWasDisconnectedNotification, object: nil)
        
        // connect document
        if let doc = view.window?.windowController?.document {
            document = doc as? Document
            copyFromDocument()
        }
        
        // initialize preview background
        if let view = previewView, let root = view.layer {
            root.backgroundColor = CGColorCreateGenericGray(0.2, 1.0)
            //CGColorGetConstantColor(kCGColorBlack)
        }
        
        if let view = annotableView, let root = view.layer {
            view.wantsLayer = true
            root.zPosition = 1.0
        }
        
        // refresh interface
        refreshInterface()
    }
    
    override func viewWillDisappear() {
        // remove notification center
        NSNotificationCenter.defaultCenter().removeObserver(self)
        
        // end any session
        stopVideoData()
        stopVideoFile()
        stopAudioFile()
        stopSession()
        
        // will disappear
        super.viewWillDisappear();
    }
    
    override func viewDidDisappear() {
        // call above
        super.viewDidDisappear()
        
        // terminate
        //NSApp.terminate(nil)
    }
    
    private func copyFromDocument() {
        if let doc = document {
            DLog("DOCUMENT ->")
            
            textName?.stringValue = doc.name
            sliderLedBrightness?.integerValue = Int(doc.ledBrightness)
            
            var tagVideo = -1, tagAudio = -1, tagSerial = -1
            for (key, val) in deviceUniqueIDs.generate() {
                switch val {
                case doc.devVideo: tagVideo = key
                case doc.devAudio: tagAudio = key
                case doc.devSerial: tagSerial = key
                default: break
                }
            }
            
            if 0 <= tagVideo {
                listVideoSources?.selectItemWithTag(tagVideo)
            }
            else {
                listVideoSources?.selectItemAtIndex(0)
            }
            
            if 0 <= tagAudio {
                listAudioSources?.selectItemWithTag(tagAudio)
            }
            else {
                listAudioSources?.selectItemAtIndex(0)
            }
            
            if 0 <= tagSerial {
                listSerialPorts?.selectItemWithTag(tagSerial)
            }
            else {
                listSerialPorts?.selectItemAtIndex(0)
            }
            
            annotableView?.annotations = doc.listAnnotations
            tableAnnotations?.reloadData()
        }
    }
    
    private func copyToDocument() {
        if let doc = document {
            DLog("DOCUMENT <-")
            
            doc.name = textName?.stringValue ?? ""
            doc.ledBrightness = UInt8(sliderLedBrightness?.integerValue ?? 0 )
            if let inputVideo = avInputVideo, let inputVideoDevice = inputVideo as? AVCaptureDeviceInput {
                doc.devVideo = inputVideoDevice.device.uniqueID
            }
            else {
                doc.devVideo = ""
            }
            if let inputAudio = avInputAudio, let inputAudioDevice = inputAudio as? AVCaptureDeviceInput {
                doc.devAudio = inputAudioDevice.device.uniqueID
            }
            else {
                doc.devAudio = ""
            }
            if let arduino = ioArduino {
                doc.devSerial = arduino.serial?.path ?? ""
            }
            else {
                doc.devSerial = ""
            }
            doc.listAnnotations = annotableView?.annotations ?? []
            doc.updateChangeCount(.ChangeDone)
        }
    }
    
    private func refreshInterface() {
        // editability
        let editable = mode.isEditable()
        textName?.enabled = editable
        listVideoSources?.enabled = editable
        listAudioSources?.enabled = editable
        listSerialPorts?.enabled = editable
        sliderLedBrightness?.enabled = editable && nil != ioArduino
        // annotation names
        if let tv = tableAnnotations {
            let col = tv.columnWithIdentifier("name")
            if 0 <= col {
                tv.tableColumns[col].editable = editable
            }
        }
        
        // button modes
        switch mode {
        case .Configure:
            buttonCapture?.enabled = (nil != avInputVideo || nil != avInputAudio)
            buttonCapture?.title = "Start Capturing"
            buttonMonitor?.enabled = nil != ioArduino && (nil != avInputVideo || nil != avInputAudio)
            buttonMonitor?.title = "Start Monitoring"
        case .ManualCapture:
            buttonCapture?.enabled = true
            buttonCapture?.title = "Stop Capturing"
            buttonMonitor?.enabled = false
            buttonMonitor?.title = "Start Monitoring"
        case .TriggeredCapture:
            buttonCapture?.enabled = false
            buttonCapture?.title = "Stop Capturing"
            buttonMonitor?.enabled = true
            buttonMonitor?.title = "Stop Monitoring"
        case .Monitor:
            buttonCapture?.enabled = false
            buttonCapture?.title = "Start Capturing"
            buttonMonitor?.enabled = true
            buttonMonitor?.title = "Stop Monitoring"
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
        
        var newDeviceUniqueIDs = [Int: String]()
        var newDeviceIndex = 1
        
        // video sources
        if let list = self.listVideoSources {
            let selectedUniqueID: String
            if let inputVideo = avInputVideo, let inputVideoDevice = inputVideo as? AVCaptureDeviceInput {
                selectedUniqueID = inputVideoDevice.device.uniqueID
            }
            else {
                selectedUniqueID = ""
            }
            var selectTag = -1
            
            list.removeAllItems()
            list.addItemWithTitle("Video")
            for d in devices_video {
                let dev: AVCaptureDevice = d as! AVCaptureDevice
                let item = NSMenuItem()
                item.title = dev.localizedName
                item.tag = newDeviceIndex
                list.menu?.addItem(item)
                newDeviceUniqueIDs[newDeviceIndex] = dev.uniqueID
                if dev.uniqueID == selectedUniqueID {
                    selectTag = newDeviceIndex
                }
                newDeviceIndex++
            }
            if 0 <= selectTag {
                list.selectItemWithTag(selectTag)
            }
            else {
                list.selectItemAtIndex(0)
            }
            list.synchronizeTitleAndSelectedItem()
        }
        
        // audio sources
        if let list = self.listAudioSources {
            let selectedUniqueID: String
            if let inputAudio = avInputAudio, let inputAudioDevice = inputAudio as? AVCaptureDeviceInput {
                selectedUniqueID = inputAudioDevice.device.uniqueID
            }
            else {
                selectedUniqueID = ""
            }
            var selectTag = -1
            
            list.removeAllItems()
            list.addItemWithTitle("Audio")
            for d in devices_audio {
                let dev: AVCaptureDevice = d as! AVCaptureDevice
                let item = NSMenuItem()
                item.title = dev.localizedName
                item.tag = newDeviceIndex
                list.menu?.addItem(item)
                newDeviceUniqueIDs[newDeviceIndex] = dev.uniqueID
                if dev.uniqueID == selectedUniqueID {
                    selectTag = newDeviceIndex
                }
                newDeviceIndex++
            }
            if 0 <= selectTag {
                list.selectItemWithTag(selectTag)
            }
            else {
                list.selectItemAtIndex(0)
            }
            list.synchronizeTitleAndSelectedItem()
        }
        
        // serial ports
        if let list = self.listSerialPorts {
            let selectedUniqueID = ioArduino?.serial?.path ?? ""
            var selectTag = -1
            
            list.removeAllItems()
            list.addItemWithTitle("Arduino")
            for port in ORSSerialPortManager.sharedSerialPortManager().availablePorts as! [ORSSerialPort] {
                let item = NSMenuItem()
                item.title = port.name
                item.tag = newDeviceIndex
                list.menu?.addItem(item)
                newDeviceUniqueIDs[newDeviceIndex] = port.path
                if port.path == selectedUniqueID {
                    selectTag = newDeviceIndex
                }
                newDeviceIndex++
            }
            if 0 <= selectTag {
                list.selectItemWithTag(selectTag)
            }
            else {
                list.selectItemAtIndex(0)
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
            DLog("Unable to add desired input device.")
        }
        catch {
            // log error
            let e = error as NSError
            let desc = e.localizedDescription
            DLog("Capturing device input failed: \(desc)")
        }
        
        return nil
    }
    
    func promptToStartCapturing() {
        // can only start capture from an editable mode
        guard mode.isEditable() else {
            return
        }
        
        let videoDeviceID = self.getVideoDeviceID()
        let audioDeviceID = self.getAudioDeviceID()
        if nil == videoDeviceID && nil == audioDeviceID {
            DLog("No device selected.")
            return
        }
        
        let panel = NSSavePanel()
        panel.title = (nil == videoDeviceID ? "Save Audio" : "Save Movie")
        
        // get prefix
        var prefix = "Output"
        if let field = textName {
            if !field.stringValue.isEmpty {
                prefix = field.stringValue
            }
        }
        
        // Let the user select any images supported by
        // the AVMovie.
        if nil != videoDeviceID {
            panel.allowedFileTypes = AVMovie.movieTypes()
            panel.allowsOtherFileTypes = false
            panel.nameFieldStringValue = prefix + ".mov"
        }
        else {
            panel.allowedFileTypes = [AVFileTypeAppleM4A]
            panel.nameFieldStringValue = prefix + ".m4a"
        }
        panel.canCreateDirectories = true
        panel.extensionHidden = false
        
        // callback for handling response
        let cb = {
            (result: Int) -> Void in
            if NSFileHandlingPanelOKButton == result {
                if let url = panel.URL {
                    self.startCapturing(url)
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
    
    func promptToStartMonitoring() {
        // can only start from an editable mode
        guard mode.isEditable() else {
            return
        }
        
        if nil == self.ioArduino {
            DLog("No arduino selected.")
            return
        }
        
        let videoDeviceID = self.getVideoDeviceID()
        let audioDeviceID = self.getAudioDeviceID()
        if nil == videoDeviceID && nil == audioDeviceID {
            DLog("No device selected.")
            return
        }
        
        let panel = NSOpenPanel()
        panel.title = "Select Output Directory"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        
        // callback for handling response
        let cb = {
            (result: Int) -> Void in
            if NSFileHandlingPanelOKButton == result {
                if let url = panel.URL {
                    self.startMonitoring(url)
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
            session.sessionPreset = AVCaptureSessionPresetHigh
            
            session.startRunning()
        }
        
        // preview layer
        if nil == self.avPreviewLayer {
            let previewLayer = AVCaptureVideoPreviewLayer(session: self.avSession!)
            self.avPreviewLayer = previewLayer
        }
    }
    
    private func startVideoData() -> Bool {
        // already created
        guard nil == avVideoData else {
            return true
        }
        guard let session = avSession else {
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
            DLog("Unable to add video data output.")
            return false
        }
        session.addOutput(videoData)
        
        // create timer for redraw
        timerRedraw = NSTimer.scheduledTimerWithTimeInterval(0.1, target: self, selector: "timerUpdateValues:", userInfo: nil, repeats: true)
        
        return true
    }
    
    private func stopVideoData() {
        // stop timer
        if let timer = self.timerRedraw {
            timer.invalidate()
            self.timerRedraw = nil
        }
        
        // stop data output
        if nil != avVideoData {
            if let session = avSession {
                session.removeOutput(avVideoData!)
            }
            avVideoData = nil
        }
        
        // release dispatch queue
        if nil != avVideoDispatchQueue {
            avVideoDispatchQueue = nil
        }
        
        // free up buffer
        if 0 < bufferSize {
            free(buffer)
            buffer = nil
            bufferSize = 0
        }
    }
    
    private func startVideoFile() -> Bool {
        // already created
        guard nil == avFileOut else {
            return true
        }
        guard let session = avSession else {
            return false
        }
        
        let movieOut = AVCaptureMovieFileOutput()
        self.avFileOut = movieOut
        if !session.canAddOutput(movieOut) {
            DLog("Unable to add movie file output.")
            return false
        }
        session.addOutput(movieOut)
        
        return true
    }
    
    private func stopVideoFile() {
        // stop writing
        if nil != avFileOut {
            if let session = avSession {
                session.removeOutput(avFileOut!)
            }
            avFileOut = nil
        }
    }
    
    private func startAudioFile() -> Bool {
        // already created
        guard nil == avFileOut else {
            return true
        }
        guard let session = avSession else {
            return false
        }
        
        let audioOut = AVCaptureAudioFileOutput()
        self.avFileOut = audioOut
        if !session.canAddOutput(audioOut) {
            DLog("Unable to add audio file output.")
            return false
        }
        session.addOutput(audioOut)
        
        return true
    }
    
    private func stopAudioFile() {
        // stop writing
        if nil != avFileOut {
            if let session = avSession {
                session.removeOutput(avFileOut!)
            }
            avFileOut = nil
        }
    }
    
    private func createVideoOutputs(file: NSURL) -> Bool {
        // create raw data stream
        if nil == avVideoData {
            if !startVideoData() {
                return false
            }
        }
        
        // writer
        if nil == avFileOut {
            if !startVideoFile() {
                return false
            }
        }
        
        // start writer
        self.avFileOut!.startRecordingToOutputFileURL(file, recordingDelegate:self)
        
        return true
    }
    
    private func refreshOutputs() {
        if nil == avInputVideo && nil == avInputAudio {
            // no inputs
            stopVideoData()
            stopVideoFile()
            stopAudioFile()
        }
        else if nil == avInputVideo {
            // has movie out?
            stopVideoData()
            if let _ = self.avFileOut as? AVCaptureMovieFileOutput {
                stopVideoFile()
            }
            
            startAudioFile()
        }
        else {
            // has audio out?
            if let _ = self.avFileOut as? AVCaptureAudioFileOutput {
                stopAudioFile()
            }
            
            if nil == avFileOut && nil == avVideoData {
                startSession()
                avSession?.beginConfiguration()
                startVideoData()
                startVideoFile()
                avSession?.commitConfiguration()
            }
            else {
                startVideoData()
                startVideoFile()
            }
        }
    }
    
    func createAudioOutputs(file: NSURL) -> Bool {
        // writer
        if nil == avFileOut {
            if !startAudioFile() {
                return false
            }
        }
        
        // start writer
        if let audioOut = avFileOut! as? AVCaptureAudioFileOutput {
            audioOut.startRecordingToOutputFileURL(file, outputFileType: AVFileTypeAppleM4A, recordingDelegate: self)
        }
        
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
        var headers = ""
        
        // reserve capacity
        headers.reserveCapacity(256)
        
        if let doc = document {
            headers += "Session,\"\(doc.name)\"\n"
            headers += "Video,\"\(doc.devVideo)\"\n"
            headers += "Audio,\"\(doc.devAudio)\"\n"
            headers += "Arduino,\"\(doc.devSerial)\"\n"
            headers += "LED Brightness,\"\(doc.ledBrightness)\"\n"
        }
        
        let date = NSDate(), formatter = NSDateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        headers += "Date,\(formatter.stringFromDate(date))\n"
        
        headers += "Name"
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
    
    private func setupBeforeCapture() -> Bool {
        // create video inputs
        if nil != avInputVideo {
            if !startVideoData() {
                return false
            }
            if !startVideoFile() {
                return false
            }
        }
        else {
            if !startAudioFile() {
                return false
            }
        }
        
        return true
    }
    
    func startCapturing(file: NSURL) -> Bool {
        guard !mode.isCapturing() else {
            return false
        }
        
        // get capture device
        if nil == avInputVideo && nil == avInputAudio {
            DLog("No device selected.")
            return false
        }
        
        // update mode
        if mode.isMonitoring() {
            mode = .TriggeredCapture
        }
        else {
            mode = .ManualCapture
            
            // setup
            if !setupBeforeCapture() {
                stopDueToPermanentError()
            }
        }
        
        // SETUP OUTPUTS
        if nil != avInputVideo {
            // unable to create video output
            if !createVideoOutputs(file) {
                stopDueToPermanentError()
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
                stopDueToPermanentError()
                return false
            }
        }
        
        return true
    }
    
    /// Stops current capture session. Will return to monitoring if automatically triggered, otherwise will return to configuration mode.
    func stopCapturing() {
        guard mode.isCapturing() else {
            return
        }
        
        // stop writing
        if let fileOut = avFileOut {
            if fileOut.recording {
                fileOut.stopRecording()
                return
            }
        }
        
        // switch interface mode
        if mode.isMonitoring() {
            mode = .Monitor
        }
        else {
            mode = .Configure
        }
    }
    
    func startMonitoring(directory: NSURL) -> Bool {
        guard mode.isEditable() else {
            return false
        }
        
        guard var path = directory.path else {
            return false
        }
        
        // has arduino
        if nil == ioArduino {
            DLog("No arduino selected.")
            return false
        }
        
        // get capture device
        if nil == avInputVideo && nil == avInputAudio {
            DLog("No device selected.")
            return false
        }
        
        // file directory
        if !path.hasSuffix("/") {
            path += "/"
        }
        if !NSFileManager.defaultManager().isWritableFileAtPath(path) {
            let alert = NSAlert()
            alert.messageText = "Unable to write"
            alert.informativeText = "The selected directory is not writable."
            alert.addButtonWithTitle("Ok")
            if let win = NSApp.keyWindow {
                alert.beginSheetModalForWindow(win, completionHandler:nil)
            }
            else {
                alert.runModal()
            }
            return false
        }
        self.dirOut = directory
        
        // update mode
        mode = .Monitor
        
        // setup
        if !setupBeforeCapture() {
            stopDueToPermanentError()
        }
        
        // strat timer
        timerMonitor = NSTimer.scheduledTimerWithTimeInterval(appPreferences.triggerPollTime, target: self, selector: "monitorCheckTrigger:", userInfo: nil, repeats: true)
        
        // turn off led and camera
        do {
            try ioArduino?.writeTo(appPreferences.pinDigitalCamera, digitalValue: false)
            try ioArduino?.writeTo(appPreferences.pinAnalogLED, analogValue: UInt8(0))
        }
        catch {
            
        }
        
        return true
    }
    
    func monitorReceiveTrigger(value: UInt16) {
        // trigger value
        let isTriggered = (value > self.appPreferences.triggerValue)
        let isCapturing = self.mode.isCapturing()
        
        // right mode
        if isTriggered == isCapturing {
            return
        }
        
        // has triggered? start capturing
        if isTriggered {
            // turn on LED and camera
            do {
                try ioArduino?.writeTo(appPreferences.pinDigitalCamera, digitalValue: true)
                if let ledBrightness = sliderLedBrightness?.integerValue {
                    try ioArduino?.writeTo(appPreferences.pinAnalogLED, analogValue: UInt8(ledBrightness))
                }
            }
            catch {
                
            }
            
            guard let dir = dirOut else {
                DLog("Output directory has gone away.")
                stopMonitoring()
                return
            }
            
            // format
            let formatter = NSDateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH mm ss"
            
            // build file name
            let name = formatter.stringFromDate(NSDate()) + (avInputVideo == nil ? ".m4a" : ".mov")
            let file = dir.URLByAppendingPathComponent(name)
            
            // start capturing
            startCapturing(file)
        }
        else {
            // stop capturing
            self.stopCapturing()
            
            // turn off LED and camera
            do {
                try ioArduino?.writeTo(appPreferences.pinDigitalCamera, digitalValue: false)
                try ioArduino?.writeTo(appPreferences.pinAnalogLED, analogValue: UInt8(0))
            }
            catch {
                
            }
        }
        
    }
    
    func monitorCheckTrigger(timer: NSTimer!) {
        guard let arduino = ioArduino else {
            DLog("POLLING failed")
            stopMonitoring()
            return
        }
        
        do {
            try arduino.readAnalogValueFrom(appPreferences.pinAnalogTrigger, andExecute: {
                (val: UInt16?) -> Void in
                guard let value = val else {
                    DLog("POLLING failed: no value")
                    self.stopMonitoring()
                    return
                }
                
                // receive trigger
                self.monitorReceiveTrigger(value)
            })
        }
        catch {
            DLog("POLLING failed")
            stopMonitoring()
        }
    }
    
    func stopMonitoring() {
        guard mode.isMonitoring() else {
            return
        }
        
        // stop timer
        if nil != timerMonitor {
            timerMonitor!.invalidate()
            timerMonitor = nil
        }
        
        // stop capturing
        if mode.isCapturing() {
            // pretend to be manual capture (ensures stop capture tears down capturing apartus)
            mode = .ManualCapture
            
            // send stop capturing message
            stopCapturing()
            
            return
        }
        
        mode = .Configure
    }
    
    func stopSession() {
        if mode.isMonitoring() {
            stopMonitoring()
        }
        else if mode.isCapturing() {
            stopCapturing()
        }
        
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
        if nil != self.avPreviewLayer {
            self.avPreviewLayer = nil
        }
        
        // release arduino
        if nil != self.ioArduino {
            self.ioArduino = nil
        }
    }
    
    /// Stops capturing & monitoring.
    func stopDueToPermanentError() {
        if mode.isMonitoring() {
            stopMonitoring()
        }
        else if mode.isCapturing() {
            stopCapturing()
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
                // update document
                copyToDocument()
                
                // get formats
//                for f in videoDevice.formats {
//                    let f2 = f as! AVCaptureDeviceFormat
//                    let d = CMVideoFormatDescriptionGetDimensions(f2.formatDescription)
//                    DLog("\(d)")
//                }
                
                // add input
                avInputVideo = addInput(videoDevice)
                
                // start preview layer
                if nil != avInputVideo {
                    // update preview layer
                    if let previewLayer = avPreviewLayer {
                        previewLayer.connection.automaticallyAdjustsVideoMirroring = false
                        previewLayer.connection.videoMirrored = false
                    }
                }
            }
        }
        else {
            // update document
            copyToDocument()
            
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
                // update document
                copyToDocument()
                
                avInputAudio = addInput(audioDevice)
            }
        }
        else {
            // update document
            copyToDocument()
            
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
            
            // update document
            copyToDocument()
        }
        else {
            // update document
            copyToDocument()
            
            // has open port?
            if nil != ioArduino {
                // remove open port
                ioArduino = nil
            }
        }
    }

    @IBAction func toggleCapturing(sender: AnyObject?) {
        if mode.isCapturing() {
            // stop processing
            stopCapturing()
        }
        else {
            // start processing
            promptToStartCapturing()
        }
    }
    
    @IBAction func toggleMonitoring(send: AnyObject?) {
        if mode.isMonitoring() {
            // stop monitoring
            stopMonitoring()
        }
        else {
            // start monitoring
            promptToStartMonitoring()
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
            stopDueToPermanentError()
            
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
        stopCapturing()
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
                regionString.reserveCapacity(64)
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
                DLog("!!! SLOWER PROCESSING !!!")
                DLog("Format: \(CVPixelBufferGetPixelFormatType(imageBuffer))")
                
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
            sampleString.reserveCapacity(64)
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
        
        // update document
        copyToDocument()
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
    
    // monitoring
    func avDeviceWasConnected(notification: NSNotification) {
        updateDeviceLists()
        DLog("AV Devices were connected")
    }
    
    func avDeviceWasDisconnected(notification: NSNotification) {
        updateDeviceLists()
        DLog("AV Devices were disconnected")
    }
    
    // serial port
    func serialPortsWereConnected(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let connectedPorts = userInfo[ORSConnectedSerialPortsKey] as! [ORSSerialPort]
            DLog("Ports were connected: \(connectedPorts)")
            updateDeviceLists()
        }
    }
    
    func serialPortsWereDisconnected(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let disconnectedPorts: [ORSSerialPort] = userInfo[ORSDisconnectedSerialPortsKey] as! [ORSSerialPort]
            DLog("Ports were disconnected: \(disconnectedPorts)")
            updateDeviceLists()
        }
    }
    
    // arduino protocol
    
    func resetArduino() {
        DLog("ARDUINO reset")
        
        stopDueToPermanentError()
        
        // clear arduino
        ioArduino = nil
        
        // reset arduino selection
        listAudioSources?.selectItemAtIndex(0)
    }
    
    @IBAction func setLedBrightness(sender: AnyObject?) {
        if let s = sender, let slider = s as? NSSlider, let arduino = self.ioArduino {
            copyToDocument()
            do {
                DLog("ARDUINO brightness \(slider.integerValue)")
                try arduino.writeTo(13, analogValue: UInt8(slider.integerValue))
            }
            catch {
                DLog("ARDUINO brightness: failed! \(error)")
            }
        }
    }
    
    @IBAction func setName(sender: AnyObject?) {
        //if let s = sender, let field = s as? NSTextField {
        copyToDocument()
        //}
    }
    
    func arduinoError(message: String, isPermanent: Bool) {
        DLog("Arduino Error: \(message)")
        
        // permanent error
        if isPermanent {
            resetArduino()
        }
    }
}

