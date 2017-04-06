//  Annotations.swift
//  VideoCapture
//
//  Created by L. Nathan Perkins on 7/2/15.
//  Copyright © 2015

import Cocoa

enum AnnotationParseError: Error {
    case missingValue
}

/// Note all points are relative [0. - 1., 0. - 1.] with an upper left origin
/// as this better matches the video signal.
protocol Annotation {
    var id: Int { get }
    var name: String { get set }
    var color: NSColor { get set }
    
    init(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor)
    init(fromDictionary d: [String: Any]) throws
    static func create(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor) -> Annotation
    func drawFilled(_ context: NSGraphicsContext, inRect rect: NSRect)
    func drawOutline(_ context: NSGraphicsContext, inRect rect: NSRect)
    func containsPoint(_ point: NSPoint) -> Bool
    func generateImageCoordinates(_ rect: NSRect) -> [(Int, Int)]
    func generateImageDescription(_ rect: NSRect) -> String
    func toDictionary() -> [String: Any]
}

/// Helepr functions to convert the relative points of the annotations back into LLO pixel coorindates for drawing.
extension Annotation {
    private func makeAbsolutePoint(_ point: NSPoint, inRect rect: NSRect) -> NSPoint {
        let x = (point.x * rect.size.width) + rect.origin.x
        let y = (rect.size.height - (point.y * rect.size.height)) + rect.origin.y
        return NSPoint(x: x, y: y)
    }
    
    fileprivate func makeAbsoluteSize(_ size: NSSize, inRect rect: NSRect) -> NSSize {
        return NSSize(width: size.width * rect.width, height: size.height * rect.height)
    }
    
    fileprivate func makeAbsoluteRect(_ rect: NSRect, inRect frame: NSRect) -> NSRect {
        let width = rect.size.width * frame.size.width
        let height = rect.size.height * frame.size.height
        let x = (rect.origin.x * frame.size.width) + frame.origin.x
        let y = (frame.size.height - (rect.origin.y * frame.size.height)) + frame.origin.y - height
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

struct AnnotationCircle: Annotation {
    let id: Int
    var name = "ROI (circle)"
    var center: NSPoint
    var radius: CGFloat
    var color: NSColor
    
    init(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor) {
        nextId += 1
        id = nextId
        center = a
        
        let x = a.x - b.x, y = a.y - b.y
        radius = sqrt((x * x) + (y * y))
        color = c
    }
    
    static func create(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor) -> Annotation {
        return AnnotationCircle(startPoint: a, endPoint: b, color: c)
    }
    
    init(fromDictionary d: [String: Any]) throws {
        // set id
        if let theVal = d["Id"], let theId = theVal as? Int {
            id = theId
        }
        else {
            nextId += 1
            id = nextId
        }
        
        // name
        if let theVal = d["Name"], let theName = theVal as? String {
            name = theName
        }
        
        // center
        if let theVal = d["CenterX"], let theX = theVal as? CGFloat, let theOtherVal = d["CenterY"], let theY = theOtherVal as? CGFloat {
            center = NSPoint(x: theX, y: theY)
        }
        else {
            throw AnnotationParseError.missingValue
        }
        
        // radius
        if let theVal = d["Radius"], let theRadius = theVal as? CGFloat {
            radius = theRadius
        }
        else {
            throw AnnotationParseError.missingValue
        }
        
        // color
        if let firstVal = d["ColorRed"], let theRed = firstVal as? CGFloat, let secondVal = d["ColorGreen"], let theGreen = secondVal as? CGFloat, let thirdVal = d["ColorBlue"], let theBlue = thirdVal as? CGFloat {
            color = NSColor(red: theRed, green: theGreen, blue: theBlue, alpha: 1.0)
        }
        else {
            throw AnnotationParseError.missingValue
        }
    }
    
    func drawFilled(_ context: NSGraphicsContext, inRect rect: NSRect) {
        color.set()
        
        let drawOrigin = NSPoint(x: center.x - radius, y: center.y - radius)
        let drawSize = NSSize(width: radius * 2, height: radius * 2)
        let drawRect = makeAbsoluteRect(NSRect(origin: drawOrigin, size: drawSize), inRect: rect)
        
        let path = NSBezierPath(ovalIn: drawRect)
        path.fill()
    }
    
    func drawOutline(_ context: NSGraphicsContext, inRect rect: NSRect) {
        color.setStroke()
        
        let drawOrigin = NSPoint(x: center.x - radius, y: center.y - radius)
        let drawSize = NSSize(width: radius * 2, height: radius * 2)
        let drawRect = makeAbsoluteRect(NSRect(origin: drawOrigin, size: drawSize), inRect: rect)
        
        
        let path = NSBezierPath(ovalIn: drawRect)
        path.lineWidth = 4.0
        path.stroke()
    }
    
    func containsPoint(_ point: NSPoint) -> Bool {
        return (distance(center, point) <= radius)
    }
    
    func generateImageCoordinates(_ rect: NSRect) -> [(Int, Int)] {
        // scale everything according to the maximum dimension
        let maxDim = max(rect.size.width, rect.size.height)
        
        let r = maxDim * radius
        
        // image integer coordinates
        let imageOriginX = Int(center.x * maxDim - r - rect.origin.x), imageOriginY = Int(center.y * maxDim - r - rect.origin.y)
        let imageSizeWidth = Int(r * 2.0), imageSizeHeight = Int(r * 2.0)
        
        var ret: [(Int, Int)] = []
        ret.reserveCapacity(imageSizeWidth * imageSizeHeight)
        for x in 0...imageSizeWidth {
            for y in 0...imageSizeHeight {
                // check ample distance
                let a = CGFloat(x) - r, b = CGFloat(y) - r
                if r < sqrt((a * a) + (b * b)) {
                    continue
                }
                ret.append((imageOriginX + x, imageOriginY + y))
            }
        }
        return ret
    }
    
    func generateImageDescription(_ rect: NSRect) -> String {
        // scale everything according to the maximum dimension
        let maxDim = max(rect.size.width, rect.size.height)
        
        // image integer coordinates
        let imageCenterX = Int(center.x * maxDim - rect.origin.x), imageCenterY = Int(center.y * maxDim - rect.origin.y), imageRadius = Int(maxDim * radius)
        
        return "Circle; center = (\(imageCenterX), \(imageCenterY)); radius = \(imageRadius)"
    }
    
    func toDictionary() -> [String: Any] {
        var ret = [String: Any]()
        ret["Id"] = id
        ret["Name"] = name
        ret["ColorRed"] = color.redComponent
        ret["ColorGreen"] = color.greenComponent
        ret["ColorBlue"] = color.blueComponent
        
        // shape specific
        ret["CenterX"] = center.x
        ret["CenterY"] = center.y
        ret["Radius"] = radius
        
        return ret
    }
}

struct AnnotationEllipse: Annotation {
    let id: Int
    var name = "ROI (ellipse)"
    var origin: NSPoint
    var size: NSSize
    var color: NSColor
    
    init(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor) {
        nextId += 1
        id = nextId
        
        // use points as recntangle points (not that intuitive)
        origin = NSPoint(x: min(a.x, b.x), y: min(a.y, b.y))
        size = NSSize(width: max(a.x, b.x) - origin.x, height: max(a.y, b.y) - origin.y)
        
        color = c
    }
    
    static func create(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor) -> Annotation {
        return AnnotationEllipse(startPoint: a, endPoint: b, color: c)
    }
    
    init(fromDictionary d: [String: Any]) throws {
        // set id
        if let theVal = d["Id"], let theId = theVal as? Int {
            id = theId
        }
        else {
            nextId += 1
            id = nextId
        }
        
        // name
        if let theVal = d["Name"], let theName = theVal as? String {
            name = theName
        }
        
        // origin
        if let firstVal = d["OriginX"], let theX = firstVal as? CGFloat, let secondVal = d["OriginY"], let theY = secondVal as? CGFloat {
            origin = NSPoint(x: theX, y: theY)
        }
        else {
            throw AnnotationParseError.missingValue
        }
        
        // size
        if let firstVal = d["SizeWidth"], let theWidth = firstVal as? CGFloat, let secondVal = d["SizeHeight"], let theHeight = secondVal as? CGFloat {
            size = NSSize(width: theWidth, height: theHeight)
        }
        else {
            throw AnnotationParseError.missingValue
        }
        
        // color
        if let firstVal = d["ColorRed"], let theRed = firstVal as? CGFloat, let secondVal = d["ColorGreen"], let theGreen = secondVal as? CGFloat, let thirdVal = d["ColorBlue"], let theBlue = thirdVal as? CGFloat {
            color = NSColor(red: theRed, green: theGreen, blue: theBlue, alpha: 1.0)
        }
        else {
            throw AnnotationParseError.missingValue
        }
    }
    
    func drawFilled(_ context: NSGraphicsContext, inRect rect: NSRect) {
        color.set()
        
        let drawRect = makeAbsoluteRect(NSRect(origin: origin, size: size), inRect: rect)
        let path = NSBezierPath(ovalIn: drawRect)
        path.fill()
    }
    
    func drawOutline(_ context: NSGraphicsContext, inRect rect: NSRect) {
        color.setStroke()
        
        let drawRect = makeAbsoluteRect(NSRect(origin: origin, size: size), inRect: rect)
        let path = NSBezierPath(ovalIn: drawRect)
        path.lineWidth = 4.0
        path.stroke()
    }
    
    func containsPoint(_ point: NSPoint) -> Bool {
        let hw = size.width / 2, hh = size.height / 2
        let center = NSPoint(x: origin.x + hw, y: origin.y + hh)
        let x = (point.x - center.x) / hw, y = (point.y - center.y) / hh
        return ((x * x) + (y * y)) <= 1 // sqrt( ) not needed
    }
    
    func generateImageCoordinates(_ rect: NSRect) -> [(Int, Int)] {
        // scale everything according to the maximum dimension
        let maxDim = max(rect.size.width, rect.size.height)
        
        // oval coordinates
        let hw = (size.width * maxDim) / 2.0, hh = (size.height * maxDim) / 2.0
        
        // image integer coordinates
        let imageOriginX = Int(origin.x * maxDim - rect.origin.x), imageOriginY = Int(origin.y * maxDim - rect.origin.y)
        let imageSizeWidth = Int(size.width * maxDim), imageSizeHeight = Int(size.height * maxDim)
        
        var ret: [(Int, Int)] = []
        ret.reserveCapacity(imageSizeWidth * imageSizeHeight)
        for x in 0...imageSizeWidth {
            for y in 0...imageSizeHeight {
                // check ample distance
                let a = (CGFloat(x) - hw) / hw, b = (CGFloat(y) - hh) / hh
                if 1 < ((a * a) + (b * b)) {
                    continue
                }
                ret.append((imageOriginX + x, imageOriginY + y))
            }
        }
        return ret
    }
    
    func generateImageDescription(_ rect: NSRect) -> String {
        // scale everything according to the maximum dimension
        let maxDim = max(rect.size.width, rect.size.height)
        
        // image integer coordinates
        let imageOriginX = Int(origin.x * maxDim - rect.origin.x), imageOriginY = Int(origin.y * maxDim - rect.origin.y)
        let imageSizeWidth = Int(size.width * maxDim), imageSizeHeight = Int(size.height * maxDim)
        
        return "Ellipse; origin = (\(imageOriginX), \(imageOriginY)); size = (\(imageSizeWidth), \(imageSizeHeight))"
    }
    
    func toDictionary() -> [String: Any] {
        var ret = [String: Any]()
        ret["Id"] = id
        ret["Name"] = name
        ret["ColorRed"] = color.redComponent
        ret["ColorGreen"] = color.greenComponent
        ret["ColorBlue"] = color.blueComponent
        
        // shape specific
        ret["OriginX"] = origin.x
        ret["OriginY"] = origin.y
        ret["SizeWidth"] = size.width
        ret["SizeHeight"] = size.height
        
        return ret
    }
}

struct AnnotationRectangle: Annotation {
    let id: Int
    var name = "ROI (rect)"
    var origin: NSPoint
    var size: NSSize
    var color: NSColor
    
    init(startPoint a: CGPoint, endPoint b: CGPoint, color c: NSColor) {
        nextId += 1
        id = nextId
        origin = NSPoint(x: min(a.x, b.x), y: min(a.y, b.y))
        size = NSSize(width: max(a.x, b.x) - origin.x, height: max(a.y, b.y) - origin.y)
        color = c
    }
    
    static func create(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor) -> Annotation {
        return AnnotationRectangle(startPoint: a, endPoint: b, color: c)
    }
    
    init(fromDictionary d: [String: Any]) throws {
        // set id
        if let theVal = d["Id"], let theId = theVal as? Int {
            id = theId
        }
        else {
            nextId += 1
            id = nextId
        }
        
        // name
        if let theVal = d["Name"], let theName = theVal as? String {
            name = theName
        }
        
        // origin
        if let firstVal = d["OriginX"], let theX = firstVal as? CGFloat, let secondVal = d["OriginY"], let theY = secondVal as? CGFloat {
            origin = NSPoint(x: theX, y: theY)
        }
        else {
            throw AnnotationParseError.missingValue
        }
        
        // size
        if let firstVal = d["SizeWidth"], let theWidth = firstVal as? CGFloat, let secondVal = d["SizeHeight"], let theHeight = secondVal as? CGFloat {
            size = NSSize(width: theWidth, height: theHeight)
        }
        else {
            throw AnnotationParseError.missingValue
        }
        
        // color
        if let firstVal = d["ColorRed"], let theRed = firstVal as? CGFloat, let secondVal = d["ColorGreen"], let theGreen = secondVal as? CGFloat, let thirdVal = d["ColorBlue"], let theBlue = thirdVal as? CGFloat {
            color = NSColor(red: theRed, green: theGreen, blue: theBlue, alpha: 1.0)
        }
        else {
            throw AnnotationParseError.missingValue
        }
    }
    
    func drawFilled(_ context: NSGraphicsContext, inRect rect: NSRect) {
        color.set()
        
        let drawRect = makeAbsoluteRect(NSRect(origin: origin, size: size), inRect: rect)
        NSRectFill(drawRect)
    }
    
    func drawOutline(_ context: NSGraphicsContext, inRect rect: NSRect) {
        color.set()
        
        let drawRect = makeAbsoluteRect(NSRect(origin: origin, size: size), inRect: rect)
        NSFrameRectWithWidth(drawRect, 4.0)
    }
    
    func containsPoint(_ point: NSPoint) -> Bool {
        let diff = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        return 0 <= diff.x && 0 <= diff.y && size.width >= diff.x && size.height >= diff.y
    }
    
    func generateImageCoordinates(_ rect: NSRect) -> [(Int, Int)] {
        // scale everything according to the maximum dimension
        let maxDim = max(rect.size.width, rect.size.height)
        let imageOriginX = Int(origin.x * maxDim - rect.origin.x), imageOriginY = Int(origin.y * maxDim - rect.origin.y)
        let imageSizeWidth = Int(size.width * maxDim), imageSizeHeight = Int(size.height * maxDim)
        var ret: [(Int, Int)] = []
        ret.reserveCapacity(imageSizeWidth * imageSizeHeight)
        for x in imageOriginX..<(imageOriginX + imageSizeWidth) {
            for y in imageOriginY..<(imageOriginY + imageSizeHeight) {
                ret.append((x, y))
            }
        }
        return ret
    }
    
    func generateImageDescription(_ rect: NSRect) -> String {
        // scale everything according to the maximum dimension
        let maxDim = max(rect.size.width, rect.size.height)
        
        // image integer coordinates
        let imageOriginX = Int(origin.x * maxDim - rect.origin.x), imageOriginY = Int(origin.y * maxDim - rect.origin.y)
        let imageSizeWidth = Int(size.width * maxDim), imageSizeHeight = Int(size.height * maxDim)
        
        return "Rectangle; origin = (\(imageOriginX), \(imageOriginY)); size = (\(imageSizeWidth), \(imageSizeHeight))"
    }
    
    func toDictionary() -> [String: Any] {
        var ret = [String: Any]()
        ret["Id"] = id
        ret["Name"] = name
        ret["ColorRed"] = color.redComponent
        ret["ColorGreen"] = color.greenComponent
        ret["ColorBlue"] = color.blueComponent
        
        // shape specific
        ret["OriginX"] = origin.x
        ret["OriginY"] = origin.y
        ret["SizeWidth"] = size.width
        ret["SizeHeight"] = size.height
        
        return ret
    }
}
