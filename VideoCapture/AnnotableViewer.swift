//  AnnotableViewer.swift
//  VideoCapture
//
//  Created by L. Nathan Perkins on 6/29/15.
//  Copyright © 2015

import Cocoa

// counter for IDs for annotations
var nextId = 1

protocol AnnotableViewerDelegate: class {
    func didChangeAnnotations(_ newAnnotations: [Annotation])
}

/// Used for tracking the currently selected annotation tool.
enum AnnotableTool {
    case shapeCircle
    case shapeEllipse
    case shapeRectangle
    case delete
    
    func getType() -> Annotation.Type? {
        switch self {
        case .shapeCircle: return AnnotationCircle.self
        case .shapeEllipse: return AnnotationEllipse.self
        case .shapeRectangle: return AnnotationRectangle.self
        default: return nil
        }
    }
}

private func getColors() -> [NSColor] {
    let ret = [NSColor.orange, NSColor.blue, NSColor.green, NSColor.yellow, NSColor.red, NSColor.gray]
    let space = NSColorSpace.genericRGB
    return ret.map {
        return $0.usingColorSpace(space)!
    }
}

class AnnotableViewer: NSView {
    weak var delegate: AnnotableViewerDelegate?
    
    @IBOutlet var view: NSView?
    @IBOutlet var segmentedSelector: NSSegmentedControl?
    
    // drawn annotations
    internal var annotations: [Annotation] = [] {
        didSet {
            flagForDisplay()
        }
    }
    
    // current annotation
    private var annotationInProgress: Annotation? {
        didSet {
            // both nil? nothing to do
            if oldValue == nil && annotationInProgress == nil { return }
            
            flagForDisplay()
        }
    }
    
    var isEnabled: Bool = true {
        didSet {
            // actually changed?
            guard oldValue != isEnabled else { return }
            
            locationDown = nil
            annotationInProgress = nil
            segmentedSelector?.isEnabled = isEnabled
        }
    }
    
    // current tool
    var tool = AnnotableTool.shapeEllipse {
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
    lazy private var colors: [NSColor] = getColors()
    
    // last click location
    private var locationDown: CGPoint?

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        let className = self.className, nibName = className.components(separatedBy: ".").last!
        if Bundle.main.loadNibNamed(nibName, owner: self, topLevelObjects: nil) {
            if let v = view {
                v.frame = frame
                addSubview(v)
            }
        }
    }
    
    func flagForDisplay() {
        if Thread.isMainThread {
            needsDisplay = true
        }
        else {
            DispatchQueue.main.async {
                self.needsDisplay = true
            }
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // draw annotations
        if let nsContext = NSGraphicsContext.current() {
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
    func getRelativePositionFromGlobalPoint(_ globalPoint: NSPoint) -> NSPoint {
        let localPoint = convert(globalPoint, from: nil)
        return NSPoint(x: localPoint.x / self.frame.size.width, y: (self.frame.size.height - localPoint.y) / self.frame.height)
    }
    
    override func mouseDown(with theEvent: NSEvent) {
        // call super
        super.mouseDown(with: theEvent)
        
        if !isEnabled {
            return
        }
        
        // location down
        locationDown = getRelativePositionFromGlobalPoint(theEvent.locationInWindow)
    }
    
    override func mouseDragged(with theEvent: NSEvent) {
        super.mouseDragged(with: theEvent)
        
        // not editable
        if !isEnabled {
            return
        }
        
        if nil != self.locationDown {
            if let type = tool.getType() {
                let locationCur = getRelativePositionFromGlobalPoint(theEvent.locationInWindow)
                    
                let annot = type.create(startPoint: locationDown!, endPoint: locationCur, color: colors[nextColor])
                annotationInProgress = annot
            }
        }
    }
    
    override func mouseUp(with theEvent: NSEvent) {
        super.mouseUp(with: theEvent)
        
        // not editable
        if !isEnabled {
            return
        }
        
        // single click
        if 1 == theEvent.clickCount {
            // is delete tool?
            if tool == .delete {
                let locationCur = getRelativePositionFromGlobalPoint(theEvent.locationInWindow)
                
                for i in stride(from: (annotations.count - 1), through: 0, by: -1) {
                    if annotations[i].containsPoint(locationCur) {
                        // remove annotation
                        annotations.remove(at: i)
                        
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
                if distance(locationDown!, locationCur) >= (10 / max(self.frame.size.width, self.frame.size.height)) {
                    let annot = type.create(startPoint: locationDown!, endPoint: locationCur, color: colors[nextColor])
                    annotations.append(annot)
                    
                    // call delegate
                    delegate?.didChangeAnnotations(annotations)
                    
                    // rotate array
                    nextColor += 1
                    if colors.count <= nextColor {
                        nextColor = 0
                    }
                }
            }
        }
        
        locationDown = nil
        annotationInProgress = nil
    }
    
    override func rightMouseUp(with theEvent: NSEvent) {
        super.rightMouseUp(with: theEvent)
        
        // not editable
        if !isEnabled {
            return
        }
        
        // only single click
        if 1 != theEvent.clickCount {
            return
        }
        
        let locationCur = getRelativePositionFromGlobalPoint(theEvent.locationInWindow)
        
        for i in stride(from: (annotations.count - 1), through: 0, by: -1) {
            if annotations[i].containsPoint(locationCur) {
                // remove annotation
                annotations.remove(at: i)
                
                // call delegate
                delegate?.didChangeAnnotations(annotations)
                
                return
            }
        }
    }
    
    @IBAction func selectTool(_ sender: AnyObject?) {
        if let s = sender, let seg = s as? NSSegmentedControl {
            let tools = [AnnotableTool.shapeCircle, AnnotableTool.shapeEllipse, AnnotableTool.shapeRectangle, AnnotableTool.delete]
            let id = seg.selectedSegment
            if 0 <= id && id < tools.count {
                tool = tools[id]
            }
        }
    }
}
