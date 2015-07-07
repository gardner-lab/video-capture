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

enum AnnotableTool {
    case ShapeCircle
    case ShapeEllipse
    case ShapeRectangle
    case Delete
    
    func getType() -> Annotation.Type? {
        switch self {
        case ShapeCircle: return AnnotationCircle.self
        case ShapeEllipse: return AnnotationEllipse.self
        case ShapeRectangle: return AnnotationRectangle.self
        default: return nil
        }
    }
}

class AnnotableViewer: NSView {
    var delegate: AnnotableViewerDelegate?
    
    @IBOutlet var view: NSView?
    @IBOutlet var segmentedSelector: NSSegmentedControl?
    
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
            locationDown = nil
            annotationInProgress = nil
            segmentedSelector?.enabled = enabled
        }
    }
    
    // current tool
    var tool = AnnotableTool.ShapeEllipse {
        didSet {
            if oldValue != tool {
                if nil != locationDown {
                    locationDown = nil
                }
                if nil != annotationInProgress {
                    annotationInProgress = nil
                }
            }
        }
    }
    
    // colors (advance after each draw)
    private var nextColor = 0
    lazy private var colors: [NSColor] = [NSColor.orangeColor(), NSColor.blueColor(), NSColor.greenColor(), NSColor.yellowColor(), NSColor.redColor(), NSColor.grayColor()]
    
    // last click location
    private var locationDown: CGPoint?

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        let className = self.className, nibName = className.componentsSeparatedByString(".").last!
        if NSBundle.mainBundle().loadNibNamed(nibName, owner: self, topLevelObjects: nil) {
            DLog("\(frame)")
            if let v = view {
                v.frame = frame
                addSubview(v)
            }
        }
    }
    
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
    
    override func mouseDragged(theEvent: NSEvent) {
        super.mouseDragged(theEvent)
        
        // not editable
        if !enabled {
            return
        }
        
        if nil != self.locationDown {
            if let type = tool.getType() {
                let locationCur = getRelativePositionFromGlobalPoint(theEvent.locationInWindow)
                    
                let annot = type.init(startPoint: locationDown!, endPoint: locationCur, color: colors[nextColor])
                annotationInProgress = annot
            }
        }
    }
    
    override func mouseUp(theEvent: NSEvent) {
        super.mouseUp(theEvent)
        
        // not editable
        if !enabled {
            return
        }
        
        // single click
        if 1 == theEvent.clickCount {
            // is delete tool?
            if tool == .Delete {
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
            }
            
            locationDown = nil
            annotationInProgress = nil
            
            return
        }
        
        // has annotation
        if nil != locationDown {
            if let type = tool.getType() {
                let locationCur = getRelativePositionFromGlobalPoint(theEvent.locationInWindow)
                
                // minimum distance
                if distance(locationCur, locationDown!) >= (10 / max(self.frame.size.width, self.frame.size.height)) {
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
        }
        
        locationDown = nil
        annotationInProgress = nil
    }
    
    override func rightMouseUp(theEvent: NSEvent) {
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
    }
    
    @IBAction func selectTool(sender: AnyObject?) {
        if let s = sender, let seg = s as? NSSegmentedControl {
            let tools = [AnnotableTool.ShapeCircle, AnnotableTool.ShapeEllipse, AnnotableTool.ShapeRectangle, AnnotableTool.Delete]
            let id = seg.selectedSegment
            if 0 <= id && id < tools.count {
                tool = tools[id]
            }
        }
    }
}
