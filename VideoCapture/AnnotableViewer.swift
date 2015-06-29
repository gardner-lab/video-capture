//
//  AnnotableViewer.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 6/29/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Cocoa

protocol Annotation {
    var name: String { get set }
    var color: NSColor { get set }
    
    init(startPoint a: NSPoint, endPoint b: NSPoint, color c: NSColor)
    func drawFilled(context: NSGraphicsContext)
    func drawOutline(context: NSGraphicsContext)
    func containsPoint(point: NSPoint) -> Bool
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
    
    func drawFilled(context: NSGraphicsContext) {
        color.set()
        
        let path = NSBezierPath(ovalInRect: NSRect(origin: NSPoint(x: center.x - radius, y: center.y - radius), size: NSSize(width: radius * 2, height: radius * 2)))
        path.fill()
    }
    
    func drawOutline(context: NSGraphicsContext) {
        color.setStroke()
        
        let path = NSBezierPath(ovalInRect: NSRect(origin: NSPoint(x: center.x - radius, y: center.y - radius), size: NSSize(width: radius * 2, height: radius * 2)))
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
    
    func drawFilled(context: NSGraphicsContext) {
        color.set()
        
        let path = NSBezierPath(ovalInRect: NSRect(origin: origin, size: size))
        path.fill()
    }
    
    func drawOutline(context: NSGraphicsContext) {
        color.setStroke()
        
        let path = NSBezierPath(ovalInRect: NSRect(origin: origin, size: size))
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
    
    func drawFilled(context: NSGraphicsContext) {
        color.set()
        NSRectFill(NSRect(origin: origin, size: size))
    }
    
    func drawOutline(context: NSGraphicsContext) {
        color.set()
        NSFrameRectWithWidth(NSRect(origin: origin, size: size), 4.0)
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
            for annot in annotations {
                annot.drawOutline(nsContext)
            }
            if let annot = self.annotationInProgress {
                annot.drawOutline(nsContext)
            }
            //CGContextTranslateCTM(context, self.origin.x, self.origin.y)
        }
    }
    
    override func mouseDown(theEvent: NSEvent) {
        // call super
        super.mouseDown(theEvent)
        
        // location down
        locationDown = convertPoint(theEvent.locationInWindow, fromView: nil)
    }
    
    override func rightMouseUp(theEvent : NSEvent) {
        super.rightMouseUp(theEvent)
        
        // only single click
        if 1 != theEvent.clickCount {
            return
        }
        
        let locationCur = convertPoint(theEvent.locationInWindow, fromView: nil)
        
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
            let locationCur = convertPoint(theEvent.locationInWindow, fromView: nil)
            let type = shapes[nextShape]
            let annot = type.init(startPoint: locationDown!, endPoint: locationCur, color: colors[nextColor])
            annotationInProgress = annot
        }
    }
    
    override func mouseUp(theEvent: NSEvent) {
        super.mouseUp(theEvent)
        
        // has annotation
        if nil != locationDown {
            let locationCur = convertPoint(theEvent.locationInWindow, fromView: nil)
            
            // minimum distance
            if distance(locationCur, locationDown!) >= 10 {
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
