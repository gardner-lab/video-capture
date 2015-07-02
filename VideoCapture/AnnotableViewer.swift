//
//  AnnotableViewer.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 6/29/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Cocoa

// counter for IDs for annotations
var nextId = 1

private func distance(a: CGPoint, _ b: CGPoint) -> CGFloat {
    let x = a.x - b.x, y = a.y - b.y
    return sqrt((x * x) + (y * y))
}

protocol AnnotableViewerDelegate {
    func didChangeAnnotations(newAnnotations: [Annotation])
}

class AnnotableViewer: NSView {
    var delegate: AnnotableViewerDelegate?
    
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
    
    var enabled: Bool = true {
        didSet {
            self.locationDown = nil
            self.annotationInProgress = nil
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
        }
    }
    
    /// Convert the coordinates of a click from Mac LLO pixel coordinates to a sacle independent, uper left
    /// origin coordinate space [0, 1], [0, 1]
    func getRelativePositionFromGlobalPoint(globalPoint: NSPoint) -> NSPoint {
        let localPoint = convertPoint(globalPoint, fromView: nil)
        return NSPoint(x: localPoint.x / self.frame.size.width, y: (self.frame.size.height - localPoint.y) / self.frame.height)
    }
    
    override func mouseDown(theEvent: NSEvent) {
        // call super
        super.mouseDown(theEvent)
        
        if !enabled {
            return
        }
        
        // location down
        locationDown = getRelativePositionFromGlobalPoint(theEvent.locationInWindow)
    }
    
    override func rightMouseUp(theEvent : NSEvent) {
        super.rightMouseUp(theEvent)
        
        // not editable
        if !enabled {
            return
        }
        
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
        
        // not editable
        if !enabled {
            return
        }
        
        if nil != self.locationDown {
            let locationCur = getRelativePositionFromGlobalPoint(theEvent.locationInWindow)
            let type = shapes[nextShape]
            let annot = type.init(startPoint: locationDown!, endPoint: locationCur, color: colors[nextColor])
            annotationInProgress = annot
        }
    }
    
    override func mouseUp(theEvent: NSEvent) {
        super.mouseUp(theEvent)
        
        // not editable
        if !enabled {
            return
        }
        
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
