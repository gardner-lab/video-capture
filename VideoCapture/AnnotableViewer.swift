//
//  AnnotableViewer.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 6/29/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Cocoa

/// Note all points are relative [0. - 1., 0. - 1.] with an upper left origin
/// as this better matches the video signal.
protocol Annotation {
    var name: String { get set }
    var color: NSColor { get set }
    
    init(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor)
    func drawFilled(context: NSGraphicsContext, inRect rect: NSRect)
    func drawOutline(context: NSGraphicsContext, inRect rect: NSRect)
    func containsPoint(point: NSPoint) -> Bool
}

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
    var name = "ROI (circle)"
    var center: NSPoint
    var radius: CGFloat
    var color: NSColor
    
    init(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor) {
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
}

struct AnnotationEllipse: Annotation {
    var name = "ROI (ellipse)"
    var origin: NSPoint
    var size: NSSize
    var color: NSColor
    
    init(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor) {
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
        return (sqrt((x * x) + (y * y)) <= 1)
    }
}

struct AnnotationRectangle: Annotation {
    var name = "ROI (rect)"
    var origin: NSPoint
    var size: NSSize
    var color: NSColor
    
    init(startPoint a: CGPoint, endPoint b: CGPoint, color c: NSColor) {
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
}

protocol AnnotableViewerDelegate {
    func didChangeAnnotations(newAnnotations: [Annotation])
}

class AnnotableViewer: NSView {
    var delegate: AnnotableViewerDelegate?
    
    // origin
    internal var origin = CGPoint(x: 0.0, y: 0.0) {
        didSet {
            self.needsDisplay = true
        }
    }
    
    // drawn annotations
    internal var annotations: [Annotation] = [] {
        didSet {
            self.needsDisplay = true
        }
    }
    
    // current annotation
    private var annotationInProgress: Annotation? {
        didSet {
            self.needsDisplay = true
        }
    }
    
    // colors (advance after each draw)
    private var nextColor = 0
    lazy private var colors: [NSColor] = [NSColor.orangeColor(), NSColor.blueColor(), NSColor.greenColor(), NSColor.yellowColor(), NSColor.redColor(), NSColor.grayColor()]
    
    // shapes (advance on right click not contained within shape)
    private var nextShape = 0
    lazy private var shapes: [Annotation.Type] = [AnnotationCircle.self, AnnotationEllipse.self, AnnotationRectangle.self]
    
    // last click location
    private var locationDown: CGPoint?
    
    override func drawRect(dirtyRect: NSRect) {
        super.drawRect(dirtyRect)

        // draw annotations
        if let nsContext = NSGraphicsContext.currentContext() {
            let drawRect = NSRect(origin: CGPoint(x: 0.0, y: 0.0), size: self.frame.size)
            for annot in annotations {
                annot.drawOutline(nsContext, inRect: drawRect)
            }
            if let annot = self.annotationInProgress {
                annot.drawOutline(nsContext, inRect: drawRect)
            }
            //CGContextTranslateCTM(context, self.origin.x, self.origin.y)
        }
    }
    
    func getRelativePositionFromGlobalPoint(globalPoint: NSPoint) -> NSPoint {
        let localPoint = convertPoint(globalPoint, fromView: nil)
        return NSPoint(x: localPoint.x / self.frame.size.width, y: (self.frame.size.height - localPoint.y) / self.frame.height)
    }
    
    override func mouseDown(theEvent: NSEvent) {
        // call super
        super.mouseDown(theEvent)
        
        // location down
        locationDown = getRelativePositionFromGlobalPoint(theEvent.locationInWindow)
    }
    
    override func rightMouseUp(theEvent : NSEvent) {
        super.rightMouseUp(theEvent)
        
        // only single click
        if 1 != theEvent.clickCount {
            return
        }
        
        let locationCur = getRelativePositionFromGlobalPoint(theEvent.locationInWindow)
        
        for var i = annotations.count - 1; i >= 0; --i {
            if annotations[i].containsPoint(locationCur) {
                // remove annotation
                annotations.removeAtIndex(i)
                
                // call delegate
                delegate?.didChangeAnnotations(annotations)
                
                return
            }
        }
        
        // change annotation type
        if shapes.count <= ++nextShape {
            nextShape = 0
        }
    }
    
    override func mouseDragged(theEvent: NSEvent) {
        super.mouseDragged(theEvent)
        
        if nil != self.locationDown {
            let locationCur = getRelativePositionFromGlobalPoint(theEvent.locationInWindow)
            let type = shapes[nextShape]
            let annot = type.init(startPoint: locationDown!, endPoint: locationCur, color: colors[nextColor])
            annotationInProgress = annot
        }
    }
    
    override func mouseUp(theEvent: NSEvent) {
        super.mouseUp(theEvent)
        
        // has annotation
        if nil != locationDown {
            let locationCur = getRelativePositionFromGlobalPoint(theEvent.locationInWindow)
            
            // minimum distance
            if distance(locationCur, locationDown!) >= (10 / max(self.frame.size.width, self.frame.size.height)) {
                let type = self.shapes[nextShape]
                let annot = type.init(startPoint: locationDown!, endPoint: locationCur, color: colors[nextColor])
                annotations.append(annot)
                
                // call delegate
                delegate?.didChangeAnnotations(annotations)
                
                // rotate array
                if colors.count <= ++nextColor {
                    nextColor = 0
                }
            }
        }
        
        locationDown = nil
        annotationInProgress = nil
    }
}
