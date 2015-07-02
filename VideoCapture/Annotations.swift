//
//  Annotations.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 7/2/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Cocoa

/// Note all points are relative [0. - 1., 0. - 1.] with an upper left origin
/// as this better matches the video signal.
protocol Annotation {
    var id: Int { get }
    var name: String { get set }
    var color: NSColor { get set }
    
    init(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor)
    func drawFilled(context: NSGraphicsContext, inRect rect: NSRect)
    func drawOutline(context: NSGraphicsContext, inRect rect: NSRect)
    func containsPoint(point: NSPoint) -> Bool
    func generateImageCoordinates(rect: NSRect) -> [(Int, Int)]
    func generateImageDescription(rect: NSRect) -> String
}

/// Helepr functions to convert the relative points of the annotations back into LLO pixel coorindates for drawing.
extension Annotation {
    private func makeAbsolutePoint(point: NSPoint, inRect rect: NSRect) -> NSPoint {
        let x = (point.x * rect.size.width) + rect.origin.x
        let y = (rect.size.height - (point.y * rect.size.height)) + rect.origin.y
        return NSPoint(x: x, y: y)
    }
    
    private func makeAbsoluteSize(size: NSSize, inRect rect: NSRect) -> NSSize {
        return NSSize(width: size.width * rect.width, height: size.height * rect.height)
    }
    
    private func makeAbsoluteRect(rect: NSRect, inRect frame: NSRect) -> NSRect {
        let width = rect.size.width * frame.size.width
        let height = rect.size.height * frame.size.height
        let x = (rect.origin.x * frame.size.width) + frame.origin.x
        let y = (frame.size.height - (rect.origin.y * frame.size.height)) + frame.origin.y - height
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private func distance(a: CGPoint, _ b: CGPoint) -> CGFloat {
    let x = a.x - b.x, y = a.y - b.y
    return sqrt((x * x) + (y * y))
}

struct AnnotationCircle: Annotation {
    let id: Int
    var name = "ROI (circle)"
    var center: NSPoint
    var radius: CGFloat
    var color: NSColor
    
    init(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor) {
        id = ++nextId
        center = a
        
        let x = a.x - b.x, y = a.y - b.y
        radius = sqrt((x * x) + (y * y))
        color = c
    }
    
    func drawFilled(context: NSGraphicsContext, inRect rect: NSRect) {
        color.set()
        
        let drawOrigin = NSPoint(x: center.x - radius, y: center.y - radius)
        let drawSize = NSSize(width: radius * 2, height: radius * 2)
        let drawRect = makeAbsoluteRect(NSRect(origin: drawOrigin, size: drawSize), inRect: rect)
        
        let path = NSBezierPath(ovalInRect: drawRect)
        path.fill()
    }
    
    func drawOutline(context: NSGraphicsContext, inRect rect: NSRect) {
        color.setStroke()
        
        let drawOrigin = NSPoint(x: center.x - radius, y: center.y - radius)
        let drawSize = NSSize(width: radius * 2, height: radius * 2)
        let drawRect = makeAbsoluteRect(NSRect(origin: drawOrigin, size: drawSize), inRect: rect)
        
        
        let path = NSBezierPath(ovalInRect: drawRect)
        path.lineWidth = 4.0
        path.stroke()
    }
    
    func containsPoint(point: NSPoint) -> Bool {
        return (distance(point, center) <= radius)
    }
    
    func generateImageCoordinates(rect: NSRect) -> [(Int, Int)] {
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
                ret.append(imageOriginX + x, imageOriginY + y)
            }
        }
        return ret
    }
    
    func generateImageDescription(rect: NSRect) -> String {
        // scale everything according to the maximum dimension
        let maxDim = max(rect.size.width, rect.size.height)
        
        // image integer coordinates
        let imageCenterX = Int(center.x * maxDim - rect.origin.x), imageCenterY = Int(center.y * maxDim - rect.origin.y), imageRadius = Int(maxDim * radius)
        
        return "Circle; center = (\(imageCenterX), \(imageCenterY)); radius = \(imageRadius)"
    }
}

struct AnnotationEllipse: Annotation {
    let id: Int
    var name = "ROI (ellipse)"
    var origin: NSPoint
    var size: NSSize
    var color: NSColor
    
    init(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor) {
        id = ++nextId
        origin = NSPoint(x: min(a.x, b.x), y: min(a.y, b.y))
        size = NSSize(width: max(a.x, b.x) - origin.x, height: max(a.y, b.y) - origin.y)
        color = c
    }
    
    func drawFilled(context: NSGraphicsContext, inRect rect: NSRect) {
        color.set()
        
        let drawRect = makeAbsoluteRect(NSRect(origin: origin, size: size), inRect: rect)
        let path = NSBezierPath(ovalInRect: drawRect)
        path.fill()
    }
    
    func drawOutline(context: NSGraphicsContext, inRect rect: NSRect) {
        color.setStroke()
        
        let drawRect = makeAbsoluteRect(NSRect(origin: origin, size: size), inRect: rect)
        let path = NSBezierPath(ovalInRect: drawRect)
        path.lineWidth = 4.0
        path.stroke()
    }
    
    func containsPoint(point: NSPoint) -> Bool {
        let hw = size.width / 2, hh = size.height / 2
        let center = NSPoint(x: origin.x + hw, y: origin.y + hh)
        let x = (point.x - center.x) / hw, y = (point.y - center.y) / hh
        return ((x * x) + (y * y)) <= 1 // sqrt( ) not needed
    }
    
    func generateImageCoordinates(rect: NSRect) -> [(Int, Int)] {
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
                ret.append(imageOriginX + x, imageOriginY + y)
            }
        }
        return ret
    }
    
    func generateImageDescription(rect: NSRect) -> String {
        // scale everything according to the maximum dimension
        let maxDim = max(rect.size.width, rect.size.height)
        
        // image integer coordinates
        let imageOriginX = Int(origin.x * maxDim - rect.origin.x), imageOriginY = Int(origin.y * maxDim - rect.origin.y)
        let imageSizeWidth = Int(size.width * maxDim), imageSizeHeight = Int(size.height * maxDim)
        
        return "Ellipse; origin = (\(imageOriginX), \(imageOriginY)); size = (\(imageSizeWidth), \(imageSizeHeight))"
    }
}

struct AnnotationRectangle: Annotation {
    let id: Int
    var name = "ROI (rect)"
    var origin: NSPoint
    var size: NSSize
    var color: NSColor
    
    init(startPoint a: CGPoint, endPoint b: CGPoint, color c: NSColor) {
        id = ++nextId
        origin = NSPoint(x: min(a.x, b.x), y: min(a.y, b.y))
        size = NSSize(width: max(a.x, b.x) - origin.x, height: max(a.y, b.y) - origin.y)
        color = c
    }
    
    func drawFilled(context: NSGraphicsContext, inRect rect: NSRect) {
        color.set()
        
        let drawRect = makeAbsoluteRect(NSRect(origin: origin, size: size), inRect: rect)
        NSRectFill(drawRect)
    }
    
    func drawOutline(context: NSGraphicsContext, inRect rect: NSRect) {
        color.set()
        
        let drawRect = makeAbsoluteRect(NSRect(origin: origin, size: size), inRect: rect)
        NSFrameRectWithWidth(drawRect, 4.0)
    }
    
    func containsPoint(point: NSPoint) -> Bool {
        let diff = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        return 0 <= diff.x && 0 <= diff.y && size.width >= diff.x && size.height >= diff.y
    }
    
    func generateImageCoordinates(rect: NSRect) -> [(Int, Int)] {
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
    
    func generateImageDescription(rect: NSRect) -> String {
        // scale everything according to the maximum dimension
        let maxDim = max(rect.size.width, rect.size.height)
        
        // image integer coordinates
        let imageOriginX = Int(origin.x * maxDim - rect.origin.x), imageOriginY = Int(origin.y * maxDim - rect.origin.y)
        let imageSizeWidth = Int(size.width * maxDim), imageSizeHeight = Int(size.height * maxDim)
        
        return "Rectangle; origin = (\(imageOriginX), \(imageOriginY)); size = (\(imageSizeWidth), \(imageSizeHeight))"
    }
}