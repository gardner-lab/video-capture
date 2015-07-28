//  Document.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 7/2/15.
//  Copyright © 2015

import Cocoa

/// A document represents a capture session, and includes preferences about all annotations and all devices. A very basic implementation that
/// reads and writes details via a property list binary format.
class Document : NSDocument {
    // session name
    var name: String = "Capture Session" {
        didSet {
//            setDisplayName(name.isEmpty ? nil : name)
        }
    }
    
    // documentation information
    var devVideo: String = ""
    var devAudio: String = ""
    var devSerial: String = ""
    
    // feedback trigger
    var feedbackTrigger = [String]()
    
    // output directory
    var outputDirectory: String = ""
    
    // annotation index
    var listAnnotations: [Annotation] = []
    
    lazy private var annotationTypes: [String: Annotation.Type] = ["circle": AnnotationCircle.self, "ellipse": AnnotationEllipse.self, "rectangle": AnnotationRectangle.self]
    
    // led brightness
    var ledBrightness: UInt8 = 0
    
    
    override init() {
        super.init()
        // Add your subclass-specific initialization here.
    }
    
    override func windowControllerDidLoadNib(aController: NSWindowController) {
        super.windowControllerDidLoadNib(aController)
        // Add any code here that needs to be executed once the windowController has loaded the document's window.
    }
    
    override class func autosavesInPlace() -> Bool {
        return true
    }
    
    override func makeWindowControllers() {
        // Returns the Storyboard that contains your Document window.
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController = storyboard.instantiateControllerWithIdentifier("Document Window Controller") as! NSWindowController
        self.addWindowController(windowController)
    }
    
    override func dataOfType(typeName: String) throws -> NSData {
        // only handle one type
        guard "edu.gardner.video-session" == typeName else {
            throw NSError(domain: NSOSStatusErrorDomain, code: writErr, userInfo: nil) // unimpErr
        }
        
        var dict = [String: AnyObject]()
        dict["Version"] = 1
        dict["Name"] = name
        dict["DeviceVideo"] = devVideo
        dict["DeviceAudio"] = devAudio
        dict["DeviceSerial"] = devSerial
        dict["FeedbackTrigger"] = feedbackTrigger
        dict["OuputDirectory"] = outputDirectory
        dict["LEDBrightness"] = Int(ledBrightness)
        dict["Annotations"] = listAnnotations.map {
            a -> [String: AnyObject] in
            var ret = a.toDictionary()
            for (name, type) in self.annotationTypes {
                if String(a.dynamicType) == String(type) {
                    ret["Type"] = name
                }
            }
            return ret
        }
        
        do {
            let data = try NSPropertyListSerialization.dataWithPropertyList(dict, format: .BinaryFormat_v1_0, options: 0)
            return data
        }
        catch {
            DLog("WRITE ERROR: serialization \(error)")
            throw NSError(domain: NSOSStatusErrorDomain, code: writErr, userInfo: nil)
        }
    }
    
    override func readFromData(data: NSData, ofType typeName: String) throws {
        // only handle one type
        guard "edu.gardner.video-session" == typeName else {
            throw NSError(domain: NSOSStatusErrorDomain, code: readErr, userInfo: nil) // unimpErr
        }
        
        // read dictionary
        let rawData: AnyObject
        do {
            rawData = try NSPropertyListSerialization.propertyListWithData(data, options: NSPropertyListReadOptions.Immutable, format: nil)
        }
        catch {
            DLog("READ ERROR: deserialization \(error)")
            
            throw NSError(domain: NSOSStatusErrorDomain, code: readErr, userInfo: nil)
        }
        
        // convert to dictionary type
        guard let dict = rawData as? [String: AnyObject] else {
            DLog("READ ERROR: cast failed")
            
            throw NSError(domain: NSOSStatusErrorDomain, code: readErr, userInfo: nil)
        }
        
        // check version flag
        guard let ver = dict["Version"] where (ver as? Int) == 1 else {
            DLog("READ ERROR: version check failed")
            
            throw NSError(domain: NSOSStatusErrorDomain, code: readErr, userInfo: nil)
        }
        
        name = dict["Name"] as? String ?? "Capture Session"
        devVideo = dict["DeviceVideo"] as? String ?? ""
        devAudio = dict["DeviceAudio"] as? String ?? ""
        devSerial = dict["DeviceSerial"] as? String ?? ""
        feedbackTrigger = dict["FeedbackTrigger"] as? [String] ?? [String]()
        outputDirectory = dict["OutputDirectory"] as? String ?? ""
        ledBrightness = UInt8(dict["LEDBrightness"] as? Int ?? 0)
        

        listAnnotations = []
        if let a = dict["Annotations"], let annots = a as? [[String: AnyObject]] {
            for a in annots {
                if let theVal = a["Type"], let typeName = theVal as? String, let type = self.annotationTypes[typeName] {
                    do {
                        let newAnnotation = try type.init(fromDictionary: a)
                        listAnnotations.append(newAnnotation)
                    }
                    catch {
                    }
                }
            }
        }
    }
}
