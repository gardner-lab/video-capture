//  ViewController.swift
//  VideoCapture
//
//  Created by L. Nathan Perkins on 6/28/15.
//  Copyright © 2015

import Cocoa
import AVFoundation
import CoreFoundation
import CoreGraphics
import CoreImage
import QuartzCore
import ORSSerial

let kPasteboardROI = "edu.gardner.roi"

/// The video capture mode determines interface item behavior.
enum VideoCaptureMode {
    case configure
    case monitor // monitor for triggering
    case triggeredCapture // capturing, because triggered
    case manualCapture // capturing, because manually triggered
    
    func isMonitoring() -> Bool {
        return self == .triggeredCapture || self == .monitor
    }
    
    func isCapturing() -> Bool {
        return self == .triggeredCapture || self == .manualCapture
    }
    
    func isEditable() -> Bool {
        return self == .configure
    }
}

enum LED {
    case Primary
    case Secondary
}

class ViewController: NSViewController, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    // document mode
    var mode = VideoCaptureMode.configure {
        didSet {
            DispatchQueue.main.async {
                self.refreshInterface()
            }
        }
    }
    
    @IBOutlet weak var textName: NSTextField!
    @IBOutlet weak var tokenFeedback: NSTokenField!
    @IBOutlet weak var listVideoSources: NSPopUpButton!
    @IBOutlet weak var listAudioSources: NSPopUpButton!
    @IBOutlet weak var listSerialPorts: NSPopUpButton!
    @IBOutlet weak var textLedBrightness: NSTextField!
    @IBOutlet weak var sliderLedBrightness: NSSlider!
    @IBOutlet weak var buttonToggleLed: NSButton!
    @IBOutlet weak var buttonCapture: NSButton!
    @IBOutlet weak var buttonMonitor: NSButton!
    @IBOutlet weak var buttonStill: NSButton!
    @IBOutlet weak var previewView: NSView!
    @IBOutlet weak var tableAnnotations: NSTableView!
    @IBOutlet weak var annotableView: AnnotableViewer! {
        didSet {
            oldValue?.delegate = nil
            annotableView?.delegate = self
            annotableView?.wantsLayer = true
        }
    }
    
    var deviceUniqueIDs = [Int: String]()
    
    // app preferences
    var appPreferences = Preferences()
    
    // session information
    var avSession: AVCaptureSession?
    var avInputVideo: AVCaptureDeviceInput? {
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
            // manage list of used devices
            if let ov = oldValue {
                AppDelegate.instance.stopUsingDevice(ov.device.uniqueID)
            }
            if let nv = avInputVideo {
                AppDelegate.instance.startUsingDevice(nv.device.uniqueID)
            }
            
            // update interface options
            refreshInterface()
            
            // changed state
            if (nil == oldValue) != (nil == avInputVideo) {
                refreshOutputs()
            }
        }
    }
    var avInputAudio: AVCaptureDeviceInput? {
        didSet {
            // manage list of used devices
            if let ov = oldValue {
                AppDelegate.instance.stopUsingDevice(ov.device.uniqueID)
            }
            if let nv = avInputAudio {
                AppDelegate.instance.startUsingDevice(nv.device.uniqueID)
            }
            
            // update interface options
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
                newPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
                
                // add it
                if let containingView = self.previewView {
                    // initial size
                    newPreviewLayer.frame = containingView.bounds
                
                    // add to view hierarchy
                    if let root = containingView.layer {
                        root.backgroundColor = CGColor(gray: 0.2, alpha: 1.0)
                        if nil == root.layoutManager {
                            root.layoutManager = CAConstraintLayoutManager()
                        }
                        
                        // add constraints
                        newPreviewLayer.addConstraint(CAConstraint(attribute: CAConstraintAttribute.minX, relativeTo: "superlayer", attribute: CAConstraintAttribute.maxX, scale: 0.0, offset: 0.0))
                        newPreviewLayer.addConstraint(CAConstraint(attribute: CAConstraintAttribute.minY, relativeTo: "superlayer", attribute: CAConstraintAttribute.maxY, scale: 0.0, offset: 0.0))
                        newPreviewLayer.addConstraint(CAConstraint(attribute: CAConstraintAttribute.width, relativeTo: "superlayer", attribute: CAConstraintAttribute.width))
                        newPreviewLayer.addConstraint(CAConstraint(attribute: CAConstraintAttribute.height, relativeTo: "superlayer", attribute: CAConstraintAttribute.height))
                        
                        root.addSublayer(newPreviewLayer)
                    }
                }
            }
        }
    }
    var avFileControl: CaptureControl?
    var avFileOut: AVCaptureFileOutput?
    var avVideoData: AVCaptureVideoDataOutput?
    var avVideoCaptureStill: AVCaptureStillImageOutput?
    var dirOut: URL?
    var dataOut: FileHandle?
    
    var avVideoDispatchQueue: DispatchQueue?
    
    var activeLED = LED.Primary {
        didSet {
            // get arduino
            guard let arduino = ioArduino else { return }
            
            // figure out old and new pin
            let oldPin: Int, newPin: Int
            switch activeLED {
            case .Primary:
                oldPin = appPreferences.pinAnalogSecondLED!
                newPin = appPreferences.pinAnalogLED
                buttonToggleLed.title = "1"
            case .Secondary:
                oldPin = appPreferences.pinAnalogLED
                newPin = appPreferences.pinAnalogSecondLED!
                buttonToggleLed.title = "2"
            }
            
            // get led brightness
            guard let ledBrightness = sliderLedBrightness?.integerValue, ledBrightness > 0 else { return }
            
            // set values
            do {
                try arduino.writeTo(oldPin, analogValue: 0)
                try arduino.writeTo(newPin, analogValue: UInt8(ledBrightness))
            }
            catch {
                DLog("ARDUINO brightness: failed! \(error)")
            }
        }
    }
    
    // should be unused
    override var representedObject: Any? {
        didSet {
            DLog("SET")
        }
    }
    var document: Document?
    
    // serial communications
    var ioArduino: ArduinoIO? {
        didSet {
            // manage list of used devices
            if let ov = oldValue, let path = ov.serial?.path {
                AppDelegate.instance.stopUsingDevice(path)
            }
            if let nv = ioArduino, let path = nv.serial?.path {
                AppDelegate.instance.startUsingDevice(path)
            }
            
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
    var extractNames: [String] = []
    var extractEquation: EquationElement? = nil
    var extractEquationOn: Bool = false
    var extractRegionString = ""
    
    // timer to redraw interface (saves time)
    var timerRedraw: Timer?
    
    // timer to dim LED and turn off camera
    //var timerRevertMode: NSTimer?
    
    // timer for monitoring
    var timerMonitor: Timer?
    
    // used by manual reading system
    var ciContext: CIContext?
    var buffer: UnsafeMutableRawPointer? = nil
    var bufferSize = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // fetch devices
        updateDeviceLists()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        // listen for serial changes
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(ViewController.serialPortsWereConnected(_:)), name: NSNotification.Name.ORSSerialPortsWereConnected, object: nil)
        nc.addObserver(self, selector: #selector(ViewController.serialPortsWereDisconnected(_:)), name: NSNotification.Name.ORSSerialPortsWereDisconnected, object: nil)
        nc.addObserver(self, selector: #selector(ViewController.avDeviceWasConnected(_:)), name: NSNotification.Name.AVCaptureDeviceWasConnected, object: nil)
        nc.addObserver(self, selector: #selector(ViewController.avDeviceWasDisconnected(_:)), name: NSNotification.Name.AVCaptureDeviceWasDisconnected, object: nil)
        
        // connect document
        if let doc = view.window?.windowController?.document {
            document = doc as? Document
            copyFromDocument()
        }
        
        // initialize preview background
        if let view = previewView, let root = view.layer {
            root.backgroundColor = CGColor(gray: 0.2, alpha: 1.0)
            //CGColorGetConstantColor(kCGColorBlack)
        }
        
        if let view = annotableView, let root = view.layer {
            view.wantsLayer = true
            root.zPosition = 1.0
        }
        
        // initialize drag from table
        if let tv = tableAnnotations {
            tv.registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: kPasteboardROI)])
        }
        if let tf = tokenFeedback {
            tf.registerForDraggedTypes([NSPasteboard.PasteboardType.string, NSPasteboard.PasteboardType(rawValue: kPasteboardROI)])
        }
        
        // hide/show toggle button
        buttonToggleLed?.isHidden = nil == appPreferences.pinAnalogSecondLED
        
        // refresh interface
        refreshInterface()
    }
    
    override func viewWillDisappear() {
        #if BENCHMARK
            Time.printAll()
        #endif
        
        // remove notification center
        NotificationCenter.default.removeObserver(self)
        
        // stop any acquisitions
        if mode.isMonitoring() {
            stopMonitoring()
        }
        else if mode.isCapturing() {
            stopCapturing()
        }
        
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
            textName?.stringValue = doc.name
            sliderLedBrightness?.integerValue = Int(doc.ledBrightness)
            textLedBrightness?.integerValue = Int(doc.ledBrightness)
            
            var tagVideo = -1, tagAudio = -1, tagSerial = -1
            for (key, val) in deviceUniqueIDs {
                switch val {
                case doc.devVideo: tagVideo = key
                case doc.devAudio: tagAudio = key
                case doc.devSerial: tagSerial = key
                default: break
                }
            }
            
            if 0 <= tagVideo {
                listVideoSources?.selectItem(withTag: tagVideo)
                selectVideoSource(listVideoSources)
            }
            else {
                listVideoSources?.selectItem(at: 0)
            }
            
            if 0 <= tagAudio {
                listAudioSources?.selectItem(withTag: tagAudio)
                selectAudioSource(listAudioSources)
            }
            else {
                listAudioSources?.selectItem(at: 0)
            }
            
            if 0 <= tagSerial {
                listSerialPorts?.selectItem(withTag: tagSerial)
                selectSerialPort(listSerialPorts)
            }
            else {
                listSerialPorts?.selectItem(at: 0)
            }
            
            annotableView?.annotations = doc.listAnnotations
            didChangeAnnotations(doc.listAnnotations)
            
            tokenFeedback?.objectValue = doc.feedbackTrigger.map {
                (str: String) -> Any
                in
                let re = Regex(pattern: "^ROI[0-9]+$")
                if re.match(str) {
                    let s = str.index(str.startIndex, offsetBy: 3), e = str.endIndex
                    if let id = Int(str[s..<e]) {
                        return TokenROI(id: id)
                    }
                }
                return str
            }
            equationEdited(tokenFeedback)
        }
    }
    
    fileprivate func copyToDocument() {
        if let doc = document {
            doc.name = textName?.stringValue ?? ""
            doc.ledBrightness = UInt8(sliderLedBrightness?.integerValue ?? 0 )
            if let inputVideoDevice = avInputVideo {
                doc.devVideo = inputVideoDevice.device.uniqueID
            }
            else {
                doc.devVideo = ""
            }
            if let inputAudioDevice = avInputAudio {
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
            
            // store token feedback
            if let tf = tokenFeedback, let tokens = tf.objectValue as? [AnyObject] {
                doc.feedbackTrigger = tokens.map {
                    (o: AnyObject) -> String
                    in
                    if let t = o as? TokenROI {
                        return "ROI\(t.id)"
                    }
                    return o as? String ?? ""
                }
            }
            
            doc.updateChangeCount(.changeDone)
        }
    }
    
    private func refreshInterface() {
        // editability
        let editable = mode.isEditable()
        textName?.isEnabled = editable
        tokenFeedback?.isEnabled = editable
        buttonStill.isEnabled = editable && nil != avInputVideo
        listVideoSources?.isEnabled = editable
        listAudioSources?.isEnabled = editable
        listSerialPorts?.isEnabled = editable
        sliderLedBrightness?.isEnabled = editable && nil != ioArduino
        textLedBrightness?.isEnabled = editable && nil != ioArduino
        buttonToggleLed?.isEnabled = editable && nil != ioArduino
        annotableView?.isEnabled = editable
        // annotation names
        if let tv = tableAnnotations {
            let col = tv.column(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "name"))
            if 0 <= col {
                tv.tableColumns[col].isEditable = editable
            }
        }
        
        // button modes
        switch mode {
        case .configure:
            buttonCapture?.isEnabled = (nil != avInputVideo || nil != avInputAudio)
            buttonCapture?.title = "Start Capturing"
            buttonMonitor?.isEnabled = (nil != avInputVideo || nil != avInputAudio) && nil != ioArduino
            buttonMonitor?.title = "Start Monitoring Pin"
        case .manualCapture:
            buttonCapture?.isEnabled = true
            buttonCapture?.title = "Stop Capturing"
            buttonMonitor?.isEnabled = false
            buttonMonitor?.title = "Start Monitoring Pin"
        case .triggeredCapture:
            buttonCapture?.isEnabled = false
            buttonCapture?.title = "Stop Capturing"
            buttonMonitor?.isEnabled = true
            buttonMonitor?.title = "Stop Monitoring Pin"
        case .monitor:
            buttonCapture?.isEnabled = false
            buttonCapture?.title = "Start Capturing"
            buttonMonitor?.isEnabled = true
            buttonMonitor?.title = "Stop Monitoring Pin"
        }
    }
    
    func updateDeviceLists() {
        // get all AV devices
        let devices = AVCaptureDevice.devices()
        
        // find video devices
        let devices_video = devices.filter({
            d -> Bool in
            let dev: AVCaptureDevice = d 
            return dev.hasMediaType(AVMediaType.video) || dev.hasMediaType(AVMediaType.muxed)
        })
        
        // find the audio devices
        let devices_audio = devices.filter({
            dev -> Bool in
            return dev.hasMediaType(AVMediaType.audio) || dev.hasMediaType(AVMediaType.muxed)
        })
        
        var newDeviceUniqueIDs = [Int: String]()
        var newDeviceIndex = 1
        
        // video sources
        if let list = self.listVideoSources {
            let selectedUniqueID: String
            if let inputVideoDevice = avInputVideo {
                selectedUniqueID = inputVideoDevice.device.uniqueID
            }
            else {
                selectedUniqueID = ""
            }
            var selectTag = -1
            
            list.removeAllItems()
            list.addItem(withTitle: "Video")
            for dev in devices_video {
                let item = NSMenuItem()
                if dev.isInUseByAnotherApplication {
                    item.title = dev.localizedName + " (in use)"
                    item.isEnabled = false
                }
                else {
                    item.title = dev.localizedName
                }
                item.tag = newDeviceIndex
                list.menu?.addItem(item)
                newDeviceUniqueIDs[newDeviceIndex] = dev.uniqueID
                if dev.uniqueID == selectedUniqueID {
                    selectTag = newDeviceIndex
                }
                newDeviceIndex += 1
            }
            if 0 <= selectTag {
                list.selectItem(withTag: selectTag)
            }
            else {
                list.selectItem(at: 0)
            }
            list.synchronizeTitleAndSelectedItem()
        }
        
        // audio sources
        if let list = self.listAudioSources {
            let selectedUniqueID: String
            if let inputAudioDevice = avInputAudio {
                selectedUniqueID = inputAudioDevice.device.uniqueID
            }
            else {
                selectedUniqueID = ""
            }
            var selectTag = -1
            
            list.removeAllItems()
            list.addItem(withTitle: "Audio")
            for dev in devices_audio {
                let item = NSMenuItem()
                if dev.isInUseByAnotherApplication {
                    item.title = "\(dev.localizedName) (in use)"
                    item.isEnabled = false
                }
                else if dev.localizedName == "USB2.0 MIC" {
                    // try to give it a nicer name
                    let parts = dev.uniqueID.split { $0 == ":" }
                    let c = parts.count
                    if c > 1 {
                        item.title = "USB MIC (\(parts[c-2]) \(parts[c-1]))"
                    }
                    else {
                        item.title = "\(dev.localizedName)"
                    }
                }
                else {
                    item.title = dev.localizedName
                }
                item.tag = newDeviceIndex
                list.menu?.addItem(item)
                newDeviceUniqueIDs[newDeviceIndex] = dev.uniqueID
                if dev.uniqueID == selectedUniqueID {
                    selectTag = newDeviceIndex
                }
                newDeviceIndex += 1
            }
            if 0 <= selectTag {
                list.selectItem(withTag: selectTag)
            }
            else {
                list.selectItem(at: 0)
            }
            list.synchronizeTitleAndSelectedItem()
        }
        
        // serial ports
        if let list = self.listSerialPorts {
            let selectedUniqueID = ioArduino?.serial?.path ?? ""
            var selectTag = -1
            
            list.removeAllItems()
            list.addItem(withTitle: "Arduino")
            for port in ORSSerialPortManager.shared().availablePorts {
                let item = NSMenuItem()
                item.title = port.name
                item.tag = newDeviceIndex
                list.menu?.addItem(item)
                newDeviceUniqueIDs[newDeviceIndex] = port.path
                if port.path == selectedUniqueID {
                    selectTag = newDeviceIndex
                }
                newDeviceIndex += 1
            }
            if 0 <= selectTag {
                list.selectItem(withTag: selectTag)
            }
            else {
                list.selectItem(at: 0)
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
    
    func getDevice(_ deviceUniqueID: String, mediaTypes: [AVMediaType]) -> AVCaptureDevice? {
        guard let dev = AVCaptureDevice(uniqueID: deviceUniqueID) else { return nil }
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
    
    func addInput(_ device: AVCaptureDevice) -> AVCaptureDeviceInput? {
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
            panel.allowedFileTypes = AVMovie.movieTypes().map {
                return $0.rawValue
            }
            panel.allowsOtherFileTypes = false
            panel.nameFieldStringValue = prefix + ".mov"
        }
        else {
            panel.allowedFileTypes = [AVFileType.m4a.rawValue]
            panel.nameFieldStringValue = prefix + ".m4a"
        }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        
        // callback for handling response
        let cb = {
            (result: NSApplication.ModalResponse) -> Void in
            if NSApplication.ModalResponse.OK == result {
                if let url = panel.url {
                    self.startCapturing(url)
                }
            }
        }
        
        // show
        if let win = NSApp.keyWindow {
            panel.beginSheetModal(for: win, completionHandler: cb)
        }
        else {
            panel.begin(completionHandler: cb)
        }
    }
    
    func promptToStartMonitoring() {
        // can only start from an editable mode
        guard mode.isEditable() else {
            return
        }
        
        // required inputs
        switch appPreferences.triggerType {
        case .arduinoPin:
            if nil == ioArduino {
                DLog("No arduino selected.")
                return
            }
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
            (result: NSApplication.ModalResponse) -> Void in
            if NSApplication.ModalResponse.OK == result {
                if let url = panel.url {
                    self.startMonitoring(url)
                }
            }
        }
        
        // turn off LED before hand (avoid bleaching)
        do {
            try ioArduino?.writeTo(appPreferences.pinAnalogLED, analogValue: UInt8(0))
            if let pin = appPreferences.pinAnalogSecondLED {
                try ioArduino?.writeTo(pin, analogValue: UInt8(0))
            }
        }
        catch { }
        
        // show
        if let win = NSApp.keyWindow {
            panel.beginSheetModal(for: win, completionHandler: cb)
        }
        else {
            panel.begin(completionHandler: cb)
        }
    }
    
    func startSession() {
        if nil == self.avSession {
            // create capture session
            let session = AVCaptureSession()
            self.avSession = session
            session.sessionPreset = AVCaptureSession.Preset.high
            
            session.startRunning()
        }
        
        // preview layer
        if nil == self.avPreviewLayer {
            let previewLayer = AVCaptureVideoPreviewLayer(session: self.avSession!)
            self.avPreviewLayer = previewLayer
        }
    }
    
    @discardableResult private func startVideoData() -> Bool {
        // already created
        guard nil == avVideoData else {
            return true
        }
        guard let session = avSession else {
            return false
        }
        
        // begin configuring (can be nested)
        session.beginConfiguration()
        
        // raw data
        let videoData = AVCaptureVideoDataOutput()
        avVideoData = videoData
        videoData.videoSettings = nil // nil: native format
        videoData.alwaysDiscardsLateVideoFrames = true
        
        // create serial dispatch queue
        let videoDispatchQueue = DispatchQueue(label: "VideoDataOutputQueue")
        avVideoDispatchQueue = videoDispatchQueue
        videoData.setSampleBufferDelegate(self, queue: videoDispatchQueue)
        
        if !session.canAddOutput(videoData) {
            DLog("Unable to add video data output.")
            return false
        }
        session.addOutput(videoData)
        
        // create capture session
        let videoStill = AVCaptureStillImageOutput()
        avVideoCaptureStill = videoStill
        //videoStill.outputSettings = [AVVideoCodecKey: NSNumber(unsignedInt: kCMVideoCodecType_JPEG)]
        videoStill.outputSettings = [kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)]
        
        if !session.canAddOutput(videoStill) {
            DLog("Unable to add video still.")
            return false
        }
        session.addOutput(videoStill)
        
        // commit configuration
        session.commitConfiguration()
        
        // create timer for redraw
        timerRedraw = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(ViewController.timerUpdateValues(_:)), userInfo: nil, repeats: true)
        
        return true
    }
    
    private func stopVideoData() {
        // stop timer
        if let timer = self.timerRedraw {
            timer.invalidate()
            self.timerRedraw = nil
        }
        
        // begin configuring (can be nested)
        avSession?.beginConfiguration()
        
        // stop data output
        if nil != avVideoData {
            avSession?.removeOutput(avVideoData!)
            avVideoData = nil
        }
        
        // stop still output
        if nil != avVideoCaptureStill {
            avSession?.removeOutput(avVideoCaptureStill!)
            avVideoCaptureStill = nil
        }
        
        // commit configuration
        avSession?.commitConfiguration()
        
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
    
    @discardableResult private func startVideoFile() -> Bool {
        // already created
        guard nil == avFileOut else {
            return true
        }
        guard let session = avSession else {
            return false
        }
        
        // create file control
        if nil == avFileControl {
            avFileControl = CaptureControl(parent: self)
        }
        
        // create nice capture
        let movieOut = AVCaptureMovieFileOutput()
        movieOut.delegate = avFileControl
        
        // add session
        if !session.canAddOutput(movieOut) {
            DLog("Unable to add movie file output.")
            return false
        }
        session.addOutput(movieOut)
        
        // output settings (must be configured after adding session, otherwise no connection)
        switch appPreferences.videoFormat {
        case .raw:
            // configure video connection with empty dictionary
            if let con = movieOut.connection(with: .video) {
                let settings: [String : Any] = [:]
                movieOut.setOutputSettings(settings, for: con)
            }
            
        case .h264:
            break // default, no configuration required
        }
        
        // audio output settings
        switch appPreferences.audioFormat {
        case .raw:
            // configure audio connection with lossless format
            if let con = movieOut.connection(with: .audio) {
                movieOut.setOutputSettings([
                    AVFormatIDKey: kAudioFormatAppleLossless // TODO: kAudioFormatFLAC maybe?
                    ], for: con)
            }
        case .aac:
            break
        }
        
        // store output
        avFileOut = movieOut
        
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
    
    @discardableResult private func startAudioFile() -> Bool {
        // already created
        guard nil == avFileOut else {
            return true
        }
        guard let session = avSession else {
            return false
        }
        
        // create file control
        if nil == avFileControl {
            avFileControl = CaptureControl(parent: self, outputFileType: AVFileType.m4a)
        }
        
        // create nice capture
        let audioOut = AVCaptureAudioFileOutput()
        audioOut.delegate = avFileControl
        
        // add session
        if !session.canAddOutput(audioOut) {
            DLog("Unable to add audio file output.")
            return false
        }
        session.addOutput(audioOut)
        
        // configure audio format
        switch appPreferences.audioFormat {
        case .aac:
            break
        case .raw:
            audioOut.audioSettings = [
                AVFormatIDKey: kAudioFormatAppleLossless // TODO: kAudioFormatFLAC maybe?
            ]
        }
        
        self.avFileOut = audioOut
        
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
    
    private func createVideoOutputs(_ file: URL) -> Bool {
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
        
        // remove conflicting file
        do {
            try FileManager.default.removeItem(at: file)
        }
        catch {}
        
        // start writer
        avFileControl?.shouldStart(file)
        
        return true
    }
    
    private func refreshOutputs() {
        if nil == avInputVideo && nil == avInputAudio {
            // no inputs
            avSession?.beginConfiguration()
            stopVideoData()
            stopVideoFile()
            stopAudioFile()
            avSession?.commitConfiguration()
            return
        }
        
        // start session
        startSession()
        
        // lock configuration
        avSession?.beginConfiguration()
        
        // stop existing files
        stopVideoData()
        stopVideoFile()
        stopAudioFile()
        
        // restart files / data
        if nil == avInputVideo {
            startAudioFile()
        }
        else {
            startVideoData()
            startVideoFile()
        }
        
        // commit configuration
        avSession?.commitConfiguration()
    }
    
    func createAudioOutputs(_ file: URL) -> Bool {
        // writer
        if nil == avFileOut {
            if !startAudioFile() {
                return false
            }
        }
        
        // remove conflicting file
        do {
            try FileManager.default.removeItem(at: file)
        }
        catch {}
        
        // start writer
        avFileControl?.shouldStart(file)
        
        return true
    }
    
    @discardableResult private func openDataFile(_ dataFile: URL) -> Bool {
        // get annotable view
        guard let annotView = self.annotableView else {
            return false
        }
        
        // no annotations
        // TODO: decide about guard
        //guard annotView.annotations.count > 0 else {
        //    return false
        //}
        
        // get file path
        let path = dataFile.path
        
        // remove conflicting file
        do {
            try FileManager.default.removeItem(atPath: path)
        }
        catch {}
        
        // create file
        guard FileManager.default.createFile(atPath: path, contents: nil, attributes: nil) else {
            DLog("Unable to create data file: \(dataFile.path)")
            return false
        }
        
        // file handle
        let fileHandle: FileHandle
        
        // get file handle
        do {
            fileHandle = try FileHandle(forWritingTo: dataFile)
        }
        catch {
            DLog("Unable to open data file handle: \(error)")
            return false
        }
        
        // write header information
        var headers = ""
        
        // reserve capacity
        headers.reserveCapacity(512)
        
        // save document information
        if let doc = document {
            headers += "Session,\"\(doc.name)\"\n"
            headers += "Video,\"\(doc.devVideo)\"\n"
            headers += "Audio,\"\(doc.devAudio)\"\n"
            headers += "Arduino,\"\(doc.devSerial)\"\n"
            headers += "LED Brightness,\"\(doc.ledBrightness)\"\n"
        }
        
        let date = Date(), formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // save state information
        let processInfo = ProcessInfo.processInfo
        headers += "Computer,\"\(processInfo.hostName)\"\n"
        headers += "Operating System,\"\(processInfo.operatingSystemVersionString)\"\n"
        headers += "Software Version,\"\(AppDelegate.instance.version)\"\n"
        headers += "Computer Uptime,\"\(processInfo.systemUptime)\"\n"
        headers += "Process Uptime,\"\(date.timeIntervalSince(AppDelegate.instance.started as Date))\"\n"
        headers += "Date,\"\(formatter.string(from: date))\"\n"
        
        if !extractRegionString.isEmpty {
            headers += "\(extractRegionString)\n"
        }
        
        // print column headers
        headers += "Time"
        for annot in annotView.annotations {
            headers += ",\(annot.name)"
        }
        if nil != extractEquation {
            headers += ",\(extractEquation!.description)"
        }
        headers += "\n"
        
        // write data
        if let data = headers.data(using: String.Encoding.utf8, allowLossyConversion: true) {
            fileHandle.write(data)
        }
        
        // store data output stream
        if let queue = avVideoDispatchQueue {
            // prevent race condition with output buffer, since it uses same queue
            queue.async {
                self.dataOut = fileHandle
            }
        }
        else {
            dataOut = fileHandle
        }
        
        return true
    }
    
    private func closeDataFile() {
        guard let fileHandle = dataOut else {
            return
        }
        
        if let queue = avVideoDispatchQueue {
            // prevent race condition with output buffer
            queue.async {
                self.dataOut = nil
                fileHandle.closeFile()
            }
        }
        else {
            self.dataOut = nil
            fileHandle.closeFile()
        }
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
    
    @discardableResult func startCapturing(_ file: URL) -> Bool {
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
            mode = .triggeredCapture
        }
        else {
            mode = .manualCapture
            
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
            let fileForData = file.deletingPathExtension().appendingPathExtension("csv")
            openDataFile(fileForData)
        }
        else {
            // unable to create audio output
            if !createAudioOutputs(file) {
                stopDueToPermanentError()
                return false
            }
            
            // file for data
            let fileForData = file.deletingPathExtension().appendingPathExtension("csv")
            openDataFile(fileForData)
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
            if fileOut.isRecording {
                avFileControl?.shouldStop()
            }
        }
        
        // close CSV file
        if nil != dataOut {
            closeDataFile()
        }
        
        // switch interface mode
        if mode.isMonitoring() {
            mode = .monitor
        }
        else {
            mode = .configure
        }
    }
    
    @discardableResult func startMonitoring(_ directory: URL) -> Bool {
        guard mode.isEditable() else {
            return false
        }
        
        var path = directory.path
        
        // required inputs
        switch appPreferences.triggerType {
        case .arduinoPin:
            if nil == ioArduino {
                DLog("No arduino selected.")
                return false
            }
        }
        
        // get capture device
        if nil == avInputVideo && nil == avInputAudio {
            DLog("No audio device selected.")
            return false
        }
        
        // file directory
        if !path.hasSuffix("/") {
            path += "/"
        }
        if !FileManager.default.isWritableFile(atPath: path) {
            let alert = NSAlert()
            alert.messageText = "Unable to write"
            alert.informativeText = "The selected directory is not writable."
            alert.addButton(withTitle: "Ok")
            if let win = NSApp.keyWindow {
                alert.beginSheetModal(for: win, completionHandler:nil)
            }
            else {
                alert.runModal()
            }
            return false
        }
        self.dirOut = directory
        
        // update mode
        mode = .monitor
        
        // start audio data
        switch appPreferences.triggerType {
        case .arduinoPin:
            // strat timer
            timerMonitor = Timer.scheduledTimer(timeInterval: appPreferences.triggerPollTime, target: self, selector: #selector(ViewController.monitorCheckTrigger(_:)), userInfo: nil, repeats: true)
        }
        
        // setup
        if !setupBeforeCapture() {
            stopDueToPermanentError()
        }
        
        // turn off led and camera
        do {
            try ioArduino?.writeTo(appPreferences.pinDigitalCamera, digitalValue: false)
            try ioArduino?.writeTo(appPreferences.pinAnalogLED, analogValue: UInt8(0))
            if let pin = appPreferences.pinAnalogSecondLED {
                try ioArduino?.writeTo(pin, analogValue: UInt8(0))
            }
        }
        catch {
            
        }
        
        return true
    }
    
    func stopMonitoring() {
        guard mode.isMonitoring() else {
            return
        }
        
        // stop timer (for pin based monitoring)
        if nil != timerMonitor {
            timerMonitor!.invalidate()
            timerMonitor = nil
        }
        
        // stop capturing
        if mode.isCapturing() {
            // pretend to be manual capture (ensures stop capture tears down capturing apartus)
            mode = .manualCapture
            
            // send stop capturing message
            stopCapturing()
            
            return
        }
        
        mode = .configure
    }
    
    // BEGIN ARDUINO MONITORING
    
    func monitorReceiveTrigger(_ value: UInt16) {
        // trigger value
        let shouldCapture = (Int(value) > appPreferences.triggerValue)
        
        // trigger value
        let isCapturing = mode.isCapturing()
        
        // right mode
        if shouldCapture == isCapturing {
            return
        }
        
        // has triggered? start capturing
        if shouldCapture {
            // get output directory
            guard let dir = dirOut else {
                DLog("Output directory has gone away.")
                stopMonitoring()
                return
            }
            
            // turn on LED and camera
            do {
                try ioArduino?.writeTo(appPreferences.pinDigitalCamera, digitalValue: true)
                if let ledBrightness = sliderLedBrightness?.integerValue {
                    // set led pin
                    if activeLED == .Secondary, let pin = appPreferences.pinAnalogSecondLED {
                        try ioArduino?.writeTo(pin, analogValue: UInt8(ledBrightness))
                    }
                    else {
                        try ioArduino?.writeTo(appPreferences.pinAnalogLED, analogValue: UInt8(ledBrightness))
                    }
                    
                    // set sync pin
                    try ioArduino?.writeTo(appPreferences.pinDigitalSync, digitalValue: true)
                    
                    // must schedule clean up on main thread
                    DispatchQueue.main.async {
                        // start sync timer
                        Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(self.disableSyncPin(_:)), userInfo: nil, repeats: false)
                    }
                }
            }
            catch {
            }
            
            // format
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH mm ss"
            
            // build file name
            let name = formatter.string(from: Date()) + (avInputVideo == nil ? ".m4a" : ".mov")
            let file = dir.appendingPathComponent(name)
            
            // start capturing
            startCapturing(file)
        }
        else {
            // stop capturing
            stopCapturing()
            
            // turn off LED and camera
            do {
                try ioArduino?.writeTo(appPreferences.pinDigitalCamera, digitalValue: false)
                try ioArduino?.writeTo(appPreferences.pinAnalogLED, analogValue: UInt8(0))
                if let pin = appPreferences.pinAnalogSecondLED {
                    try ioArduino?.writeTo(pin, analogValue: 0)
                }
            }
            catch {
                
            }
        }
    }
    
    @objc func disableSyncPin(_ timer: Timer!) {
        // turn off sync pin
        do {
            // set sync pin
            try ioArduino?.writeTo(appPreferences.pinDigitalSync, digitalValue: false)
        }
        catch { }
    }
    
    @objc func monitorCheckTrigger(_ timer: Timer!) {
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
    
    // END ARDUINO MONITORING
    
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

    @IBAction func selectVideoSource(_ sender: NSPopUpButton!) {
        if let selected = sender.selectedItem, let deviceUniqueID = deviceUniqueIDs[selected.tag] {
            DLog("Device ID: \(deviceUniqueID)")
            
            // is device used?
            if AppDelegate.instance.isUsingDevice(deviceUniqueID) && avInputVideo?.device.uniqueID != deviceUniqueID {
                // show alert
                let alert = NSAlert()
                alert.messageText = "Device already in use"
                alert.informativeText = "The device you selected is already in use in another window. Running multiple captures from the same device may cause problems."
                alert.addButton(withTitle: "Ok")
                if let win = NSApp.keyWindow {
                    alert.beginSheetModal(for: win, completionHandler:nil)
                }
                else {
                    alert.runModal()
                }
                
                // reset selector
                sender.selectItem(at: 0)
                
                return
            }
            
            // get existing device
            if nil != avInputVideo {
                // should be defined
                assert(nil != avSession)
                
                if let inputVideoDevice = avInputVideo {
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
            if let videoDevice = getDevice(deviceUniqueID, mediaTypes: [AVMediaType.video, AVMediaType.muxed]) {
                // get formats
//                for f in videoDevice.formats {
//                    print("\(f)")
//                    let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
//                    DLog("\(d)")
//                }
                
                // add input
                avInputVideo = addInput(videoDevice)
                
                // update document
                copyToDocument()
                
                // start preview layer
                if nil != avInputVideo {
                    // update preview layer
                    if let previewLayer = avPreviewLayer {
                        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
                        previewLayer.connection?.isVideoMirrored = false
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
                
                // update document
                copyToDocument()
            }
        }
    }
    
    @IBAction func selectAudioSource(_ sender: NSPopUpButton!) {
        if let selected = sender.selectedItem, let deviceUniqueID = deviceUniqueIDs[selected.tag] {
            DLog("Device ID: \(deviceUniqueID)")
            
            // is device used?
            if AppDelegate.instance.isUsingDevice(deviceUniqueID) && avInputAudio?.device.uniqueID != deviceUniqueID {
                // show alert
                let alert = NSAlert()
                alert.messageText = "Device already in use"
                alert.informativeText = "The device you selected is already in use in another window. Running multiple captures from the same device may cause problems."
                alert.addButton(withTitle: "Ok")
                if let win = NSApp.keyWindow {
                    alert.beginSheetModal(for: win, completionHandler:nil)
                }
                else {
                    alert.runModal()
                }
                
                // reset selector
                sender.selectItem(at: 0)
                
                return
            }
            
            // get existing device
            if nil != avInputAudio {
                // should be defined
                assert(nil != avSession)
                
                if let inputAudioDevice = avInputAudio {
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
            if let audioDevice = getDevice(deviceUniqueID, mediaTypes: [AVMediaType.audio, AVMediaType.muxed]) {
                avInputAudio = addInput(audioDevice)
                
                // update document
                copyToDocument()
            }
        }
        else {
            if nil != avInputAudio {
                // should be defined
                assert(nil != self.avSession)
                
                // remove audio
                avSession!.removeInput(avInputAudio!)
                avInputAudio = nil
                
                // update document
                copyToDocument()
            }
        }
    }
    
    @IBAction func selectSerialPort(_ sender: NSPopUpButton!) {
        if let selected = sender.selectedItem, let devicePath = deviceUniqueIDs[selected.tag] {
            DLog("Device Path: \(devicePath)")
            
            // is device used?
            if AppDelegate.instance.isUsingDevice(devicePath) && ioArduino?.serial?.path != devicePath {
                // show alert
                let alert = NSAlert()
                alert.messageText = "Device already in use"
                alert.informativeText = "The device you selected is already in use in another window. Running multiple captures from the same device may cause problems."
                alert.addButton(withTitle: "Ok")
                if let win = NSApp.keyWindow {
                    alert.beginSheetModal(for: win, completionHandler:nil)
                }
                else {
                    alert.runModal()
                }
                
                // reset selector
                sender.selectItem(at: 0)
                
                return
            }
            
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
                try ioArduino!.setPinMode(appPreferences.pinDigitalCamera, to: ArduinoIOPin.output) // pin 4: digital camera relay
                try ioArduino!.setPinMode(appPreferences.pinDigitalFeedback, to: ArduinoIOPin.output) // pin 9: digital feedback
                try ioArduino!.setPinMode(appPreferences.pinAnalogLED, to: ArduinoIOPin.output) // pin 13: analog brightness
                if let pin = appPreferences.pinAnalogSecondLED {
                    try ioArduino!.setPinMode(pin, to: .output) // pin x: analog brightness
                }
                try ioArduino!.setPinMode(appPreferences.pinDigitalSync, to: ArduinoIOPin.output) // pin 7: digital sync
                //if appPreferences.triggerType == .ArduinoPin {
                //    try ioArduino!.setPinMode(appPreferences.pinAnalogTrigger, to: ArduinoIOPin.Input) // pin: 0 analog trigger
                //}
                
                // turn camera on, if already selected
                if nil != self.avInputVideo {
                    try ioArduino!.writeTo(appPreferences.pinDigitalCamera, digitalValue: true)
                }
            }
            catch {
                DLog("Unable to communicate with selected Arduino. \(error)")
                ioArduino = nil
            }
            
            // update document
            copyToDocument()
        }
        else {
            // has open port?
            if nil != ioArduino {
                // remove open port
                ioArduino = nil
                
                // update document
                copyToDocument()
            }
        }
    }

    @IBAction func toggleCapturing(_ sender: NSButton!) {
        if mode.isCapturing() {
            // stop processing
            stopCapturing()
        }
        else {
            // start processing
            promptToStartCapturing()
        }
    }
    
    @IBAction func toggleMonitoring(_ sender: NSButton!) {
        if mode.isMonitoring() {
            // stop monitoring
            stopMonitoring()
        }
        else {
            // start monitoring
            promptToStartMonitoring()
        }
    }
    
    @IBAction func captureStill(_ sender: NSButton!) {
        guard let videoStill = avVideoCaptureStill else { return }
        guard !videoStill.isCapturingStillImage else { return }
        guard let conn = videoStill.connection(with: AVMediaType.video) else { return }
        
        sender.isEnabled = false
        
        videoStill.captureStillImageAsynchronously(from: conn) {
            (sampleBuffer: CMSampleBuffer?, error: Error?) -> Void
            in
            
            defer {
                // on main thread
                DispatchQueue.main.async {
                    sender.isEnabled = true
                }
            }
            
            // no sample buffer?
            if sampleBuffer == nil {
                DLog("ERROR: \(error!)")
                return
            }
            
            // get image buffer
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer!) else {
                return
            }
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent)
            
            DispatchQueue.main.async {
                // save panel
                let panel = NSSavePanel()
                panel.allowsOtherFileTypes = false
                
                // get prefix
                var prefix = "Output"
                if let field = self.textName {
                    if !field.stringValue.isEmpty {
                        prefix = field.stringValue
                    }
                }
                
                panel.title = "Save Still Image"
                panel.allowedFileTypes = ["tiff"]
                panel.nameFieldStringValue = prefix + ".tiff"
                panel.canCreateDirectories = true
                panel.isExtensionHidden = false
                
                // callback for handling response
                let cb = {
                    (result: NSApplication.ModalResponse) -> Void in
                    if NSApplication.ModalResponse.OK == result {
                        if let url = panel.url {
                            // delete existting
                            let fm = FileManager.default
                            if fm.fileExists(atPath: url.path) {
                                do {
                                    try FileManager.default.removeItem(at: url)
                                }
                                catch { }
                            }
                            
                            // setup TIFF properties to enable LZW compression
                            
                            // create dictionary
                            var keyCallbacks = kCFTypeDictionaryKeyCallBacks
                            var valueCallbacks = kCFTypeDictionaryValueCallBacks
                            
                            var compression = NSBitmapImageRep.TIFFCompression.lzw.rawValue
                            
                            let saveOpts = CFDictionaryCreateMutable(nil, 0, &keyCallbacks,  &valueCallbacks)
                            let tiffProps = CFDictionaryCreateMutable(nil, 0, &keyCallbacks, &valueCallbacks)
                            let key = kCGImagePropertyTIFFCompression
                            let val = CFNumberCreate(nil, CFNumberType.intType, &compression)
                            CFDictionarySetValue(tiffProps, Unmanaged.passUnretained(key).toOpaque(), Unmanaged.passUnretained(val!).toOpaque())
                            
                            let key2 = kCGImagePropertyTIFFDictionary
                            CFDictionarySetValue(saveOpts, Unmanaged.passUnretained(key2).toOpaque(), Unmanaged.passUnretained(tiffProps!).toOpaque())
                            
                            if let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) {
                                CGImageDestinationAddImage(destination, cgImage!, saveOpts)
                                CGImageDestinationFinalize(destination)
                            }
                        }
                    }
                }
                
                // show
                panel.beginSheetModal(for: self.view.window!, completionHandler: cb)
            }
        }
    }
    
    func fileOutput(_ captureOutput: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        var success = true, isReadable = true
        
        if nil != error {
            success = false
//            if let val = e.userInfo[AVErrorRecordingSuccessfullyFinishedKey] {
//                if let b = val as? Bool {
//                    isReadable = b
//                }
//            }
        }
        
        if success {
            DLog("CAPTURE success!")
        }
        else {
            DLog("CAPTURE failure: \(String(describing: error))")
            
            // clear move
            avFileOut = nil
            
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
            if isReadable {
                alert.informativeText += " The file should be readable."
            }
            alert.addButton(withTitle: "Ok")
            if let win = NSApp.keyWindow {
                alert.beginSheetModal(for: win, completionHandler:nil)
            }
            else {
                alert.runModal()
            }

            return
        }
        
        // still recording? likely switched files
        if let fileOut = avFileOut, fileOut.isRecording {
            DLog("CAPTURE switched file?")
            return
        }
        
        // called as part of the stopping process
        stopCapturing()
    }
    
    private func updateExtractionList(_ dimensions: CGSize) { // , _ rep: NSBitmapImageRep
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
        extractNames.removeAll()
        if let view = annotableView {
            for (i, annot) in view.annotations.enumerated() {
                // append names (used by placeholders in equations)
                extractNames.append("ROI\(annot.id)")
                
                // generate image coordinates
                for (x, y) in annot.generateImageCoordinates(videoFrame) {
                    if x < 0 || x >= maxX || y < 0 || y >= maxY {
                        continue
                    }
                    
                    // debugging
//                    rep.setColor(annot.color, atX: x, y: y)
                    
                    extractArray.append((pixel: maxX * y + x, annotation: i))
                }
            }
            
            // string for describing output (stored to shape)
            var regionString = "Region"
            regionString.reserveCapacity(64)
            for annot in view.annotations {
                regionString += ",\"" + annot.generateImageDescription(videoFrame) + "\""
            }
            
            // write data
            extractRegionString = regionString
        }
        else {
            // clear extract region string
            extractRegionString = ""
        }
        extractValues = [Float](repeating: 0.0, count: extractNames.count)

        // debugging
//        let prop = [String : AnyObject]()
//        let data = rep.representationUsingType(NSBitmapImageFileType.NSPNGFileType, properties: prop)
//        data?.writeToURL(NSURL(fileURLWithPath: "/Users/nathan/Desktop/debug.png"), atomically: false)
        
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        #if BENCHMARK
            Time.stopAndSave(withName: "wait")
            Time.start(withName: "process")
            
            // get time
            let tm1 = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            Time.save(withName: "frame", andValue: CMTimeGetSeconds(tm1))
        #endif
        
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
            CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags.readOnly);
            
            // get buffer
            let bytesPerPixel = 2
            let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
            let bytesTotal = bytesPerRow * height
            let bytes = UnsafeBufferPointer<UInt8>(start: CVPixelBufferGetBaseAddress(imageBuffer)!.assumingMemoryBound(to: UInt8.self), count: Int(bytesTotal))
            
            annotSum = [Float](repeating: 0.0, count: extractValues.count)
            annotCnt = [Int](repeating: 0, count: extractValues.count)
            for (pixel, annotIdx) in extractArray {
                if annotIdx >= annotSum.count {
                    continue
                }
                let i = pixel * bytesPerPixel + 1
                let brightness = Float(bytes[i])
                
                // increment values
                annotSum[annotIdx] += brightness
                annotCnt[annotIdx] += 1
            }
            
            // unlock buffer
            CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags.readOnly);
        }
        else {
            //        if let a = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate) {
            //            let attachments = a.takeRetainedValue() as NSDictionary
            //        }
            
            let image = CIImage(cvImageBuffer: imageBuffer) //, options: attachments) // , options:attachments)
            
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
                self.buffer = calloc(bytesTotal, MemoryLayout<UInt8>.stride)
                self.bufferSize = bytesTotal
            }
            
            self.ciContext?.render(image, toBitmap: self.buffer!, rowBytes: bytesPerRow, bounds: bounds, format: kCIFormatARGB8, colorSpace: nil)
            
            let bytes = UnsafeBufferPointer<UInt8>(start: self.buffer!.assumingMemoryBound(to: UInt8.self), count: Int(bytesTotal))
            annotSum = [Float](repeating: 0.0, count: extractValues.count)
            annotCnt = [Int](repeating: 0, count: extractValues.count)
            for (pixel, annotIdx) in extractArray {
                if annotIdx >= annotSum.count {
                    continue
                }
                let i = pixel * bytesPerPixel
                let red = Float(bytes[i + 1]), green = Float(bytes[i + 2]), blue = Float(bytes[i + 3])
                let brightness = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                
                // increment values
                annotSum[annotIdx] += brightness
                annotCnt[annotIdx] += 1
            }
        }
        
        // sync
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        
        // update values
        extractValues = zip(annotSum, annotCnt).map {
            sum, cnt in return cnt > 0 ? sum / Float(cnt) : 0.0
        }
        
        // equation
        if nil != extractEquation {
            var ph = [String: Float]()
            for (i, v) in extractValues.enumerated() {
                ph[extractNames[i]] = v
            }
            
            let nv = (extractEquation!.evaluate(ph) > 0.0)
            if extractEquationOn != nv {
                extractEquationOn = nv
                if let arduino = self.ioArduino, (nv == false || !mode.isEditable()) {
                    // update feedback pin
                    do {
                        try arduino.writeTo(appPreferences.pinDigitalFeedback, digitalValue: nv)
                    }
                    catch {
                        DLog("FEEDBACK error: \(error)")
                    }
                }
            }
        }
        
        // string
        if nil != dataOut {
            // get timestamp
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer), timestampAsSeconds = CMTimeGetSeconds(timestamp)
            
            // build sample string
            var sampleString = "\(timestampAsSeconds)"
            sampleString.reserveCapacity(64)
            for val in extractValues {
                sampleString += ",\(val)"
            }
            if nil != extractEquation {
                sampleString += ",\(extractEquationOn)"
            }
            sampleString += "\n"
            
            // write data
            if let data = sampleString.data(using: String.Encoding.utf8, allowLossyConversion: true) {
                dataOut?.write(data)
            }
        }
        
        #if BENCHMARK
            Time.stopAndSave(withName: "process")
            Time.start(withName: "wait")
        #endif
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        DLog("DROPPED FRAME!")
        
        // string
        if nil != dataOut {
            // get timestamp
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer), timestampAsSeconds = CMTimeGetSeconds(timestamp)
            
            // build sample string
            let sampleString = "\(timestampAsSeconds),dropped\n"
            
            // write data
            if let data = sampleString.data(using: String.Encoding.utf8, allowLossyConversion: true) {
                dataOut?.write(data)
            }
        }
    }
    
    @objc func timerUpdateValues(_ timer: Timer!) {
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        if let tv = tableAnnotations {
            tv.reloadData(forRowIndexes: IndexSet(integersIn: 0..<extractValues.count), columnIndexes: IndexSet(integer: 2))
        }
        if nil != extractEquation {
            if extractEquationOn {
                tokenFeedback?.backgroundColor = NSColor.green
            }
            else {
                tokenFeedback?.backgroundColor = NSColor.textBackgroundColor
            }
        }
    }
    
    // MARK: - arduino delegate and controls
    
    // monitoring
    @objc func avDeviceWasConnected(_ notification: Notification) {
        updateDeviceLists()
        DLog("AV Devices were connected")
    }
    
    @objc func avDeviceWasDisconnected(_ notification: Notification) {
        updateDeviceLists()
        DLog("AV Devices were disconnected")
    }
    
    // serial port
    @objc func serialPortsWereConnected(_ notification: Notification) {
        if let userInfo = (notification as NSNotification).userInfo {
            let connectedPorts = userInfo[ORSConnectedSerialPortsKey] as! [ORSSerialPort]
            DLog("Ports were connected: \(connectedPorts)")
            updateDeviceLists()
        }
    }
    
    @objc func serialPortsWereDisconnected(_ notification: Notification) {
        if let userInfo = (notification as NSNotification).userInfo {
            let disconnectedPorts: [ORSSerialPort] = userInfo[ORSDisconnectedSerialPortsKey] as! [ORSSerialPort]
            DLog("Ports were disconnected: \(disconnectedPorts)")
            updateDeviceLists()
        }
    }
    
    func resetArduino() {
        DLog("ARDUINO reset")
        
        stopDueToPermanentError()
        
        // clear arduino
        ioArduino = nil
        
        // reset arduino selection'
        listSerialPorts?.selectItem(at: 0)
    }
    
    // MARK: - interface options
    
    @IBAction func setLedBrightness(_ sender: NSControl!) {
        // synchronize values
        if sender !== sliderLedBrightness {
            sliderLedBrightness.integerValue = sender.integerValue
        }
        if sender !== textLedBrightness {
            textLedBrightness.integerValue = sender.integerValue
        }
        
        if let arduino = ioArduino {
            copyToDocument()
            do {
                DLog("ARDUINO brightness \(sender.integerValue)")
                if activeLED == .Secondary, let pin = appPreferences.pinAnalogSecondLED {
                    try arduino.writeTo(pin, analogValue: UInt8(sender.integerValue))
                }
                else {
                    try arduino.writeTo(appPreferences.pinAnalogLED, analogValue: UInt8(sender.integerValue))
                }
            }
            catch {
                DLog("ARDUINO brightness: failed! \(error)")
            }
        }
    }
    
    @IBAction func toggleLed(_ sender: NSButton!) {
        switch activeLED {
        case .Primary:
            activeLED = .Secondary
        case .Secondary:
            activeLED = .Primary
        }
    }
    
    @IBAction func setName(_ sender: NSTextField!) {
        //if let s = sender, let field = s as? NSTextField {
        copyToDocument()
        //}
    }
    
    @IBAction func equationEdited(_ sender: NSTokenField!) {
        // get array of tokens
        let tokens = sender.objectValue as! [AnyObject]
        let str = tokens.map({
            (o: AnyObject) -> String
            in
            if let t = o as? TokenROI {
                return "ROI\(t.id)"
            }
            return o as? String ?? ""
        }).joined(separator: "")
        
        // reset background color
        sender.backgroundColor = NSColor.textBackgroundColor
        
        // empty? disable equation
        if str.isEmpty {
            extractEquation = nil
        }
        else {
            do {
                let eq = try equationParse(str)
                extractEquation = eq.simplify()
                DLog("\(extractEquation!.description)")
            }
            catch {
                extractEquation = nil
                DLog("EQUATION error: \(error)")
                sender.backgroundColor = NSColor(red: 242.0 / 255.0, green: 222.0 / 255.0, blue: 222.0 / 255.0, alpha: 1.0)
            }
        }
        
        // update document
        copyToDocument()
    }
}

extension ViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        guard let annotView = self.annotableView else {
            return 0
        }
        return annotView.annotations.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let col = tableColumn, let annotView = self.annotableView else {
            return nil
        }
        
        // handle column identifiers
        switch (col.identifier.rawValue) {
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
    
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard let col = tableColumn, let annotView = self.annotableView else {
            return
        }
        
        if "name" == col.identifier.rawValue && row < annotView.annotations.count {
            if let newName = object as? String {
                annotView.annotations[row].name = newName
            }
        }
    }
    
    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
        guard rowIndexes.count == 1 else {
            return false
        }
        guard let annotView = annotableView else {
            return false
        }
        
        // get row
        let row = rowIndexes.first!
        if row < annotView.annotations.count {
            // assemble data (just dictionary with ID)
            let dict: [String: Any] = ["id": annotView.annotations[row].id]
            let data = NSArchiver.archivedData(withRootObject: dict)
            pboard.declareTypes([NSPasteboard.PasteboardType(rawValue: kPasteboardROI), NSPasteboard.PasteboardType.string], owner: nil)
            pboard.setData(data, forType: NSPasteboard.PasteboardType(rawValue: kPasteboardROI))
            pboard.setString(annotView.annotations[row].name, forType: NSPasteboard.PasteboardType.string)
            return true
        }
        
        return false
    }
}

extension ViewController: AnnotableViewerDelegate {
    func didChangeAnnotations(_ newAnnotations: [Annotation]) {
        // clear extract values
        extractValues = [Float](repeating: 0.0, count: newAnnotations.count)
        
        // reset bounds (force reloading list of pixels)
        extractBounds = CGSize(width: 0.0, height: 0.0)
        
        // force redrawing of table
        tableAnnotations?.reloadData()
        
        // update document
        copyToDocument()
        
        //        let attach = NSTextAttachment(fileWrapper: nil)
        //        let cell = AnnotationCell()
        //        attach.attachmentCell = cell
        //
        //        let tfas = NSMutableAttributedString(attributedString: textFeedback!.attributedStringValue)
        //        DLog("\(tfas)")
        //        tfas.appendAttributedString(NSAttributedString(attachment: attach))
        //        textFeedback?.attributedStringValue = tfas
        //        //textFeedback?.cell?.insertValue(NSAttributedString(attachment: attach), atIndex: 0, inPropertyWithKey: )
    }
}

extension ViewController: ArduinoIODelegate {
    func arduinoError(_ message: String, isPermanent: Bool) {
        DLog("Arduino Error: \(message)")
        
        // permanent error
        if isPermanent {
            resetArduino()
        }
    }
}

extension ViewController: NSTokenFieldDelegate {
    // return an array of represented objects you want to add.
    // If you want to reject the add, return an empty array.
    // returning nil will cause an error.
    func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
        return tokens.filter {
            (o: Any) -> Bool
            in
            if o is String {
                return true
            }
            if let roi = o as? TokenROI {
                if let annotView = self.annotableView {
                    for annot in annotView.annotations {
                        if annot.id == roi.id {
                            return true
                        }
                    }
                }
            }
            return false
        }
    }
    
    // If you return nil or don't implement these delegate methods, we will assume
    // editing string = display string = represented object
    func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
        if let o = representedObject as? TokenROI {
            if let annotView = annotableView {
                for annot in annotView.annotations {
                    if annot.id == o.id {
                        return annot.name
                    }
                }
            }
            return "Unknown Annotation"
        }
        if let s = representedObject as? String {
            return s
        }
        return nil
    }
    
    func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
        if let o = representedObject as? TokenROI {
            return "ROI\(o.id)"
        }
        if let s = representedObject as? String {
            return s
        }
        return nil
    }
    
    func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> (Any)? {
        let re = Regex(pattern: "^ROI[0-9]+$")
        if re.match(editingString) {
            let s = editingString.index(editingString.startIndex, offsetBy: 3), e = editingString.endIndex
            if let id = Int(editingString[s..<e]) {
                return TokenROI(id: id)
            }
        }
        return editingString
    }
    
    // Return an array of represented objects to add to the token field.
    func tokenField(_ tokenField: NSTokenField, readFrom pboard: NSPasteboard) -> [Any]? {
        var ret = [Any]()
        if let data = pboard.data(forType: NSPasteboard.PasteboardType(rawValue: kPasteboardROI)), let un = NSUnarchiver.unarchiveObject(with: data), let dict = un as? NSDictionary {
            if let v = dict["id"], let id = v as? Int {
                ret.append(TokenROI(id: id))
            }
        }
        return ret
    }
    
    func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenField.TokenStyle {
        if representedObject is TokenROI {
            return NSTokenField.TokenStyle.default
        }
        return NSTokenField.TokenStyle.none
    }
}

class TokenROI: NSObject
{
    let id: Int
    
    init(id: Int) {
        self.id = id
        super.init()
    }
}
