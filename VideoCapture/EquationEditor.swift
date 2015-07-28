//
//  EditableEquation.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 7/27/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Cocoa
import Foundation

class EquationField : NSTokenField
{
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        DLog("init")
    }
    
    override func draggingEntered(sender: NSDraggingInfo) -> NSDragOperation {
        // entered
        DLog("ENTERED")
        
        // must come from same window
        guard self.window == sender.draggingDestinationWindow() else {
            return super.draggingEntered(sender)
        }
        
        
        // has valid pasteboard data?
        let pb = sender.draggingPasteboard()
        if let _ = pb.dataForType(kPasteboardROI) {
            DLog("generic")
            return NSDragOperation.Generic
        }
        
        return super.draggingEntered(sender)
    }
    
    override func draggingUpdated(sender: NSDraggingInfo) -> NSDragOperation {
        DLog("UPDATED")
        
        // must come from same window
        guard self.window == sender.draggingDestinationWindow() else {
            return super.draggingUpdated(sender)
        }
        
        // has valid pasteboard data?
        let pb = sender.draggingPasteboard()
        if let _ = pb.dataForType(kPasteboardROI) {
            return NSDragOperation.Generic
        }
        
        return super.draggingUpdated(sender)
    }
    
    override func draggingExited(sender: NSDraggingInfo?) {
        DLog("EXITED")
        
        super.draggingExited(sender)
    }
    
    override func prepareForDragOperation(sender: NSDraggingInfo) -> Bool {
        DLog("PREPARE")
        
        return super.prepareForDragOperation(sender)
    }
    
    override func performDragOperation(sender: NSDraggingInfo) -> Bool {
        DLog("PERFORM")
        
        return super.performDragOperation(sender)
    }
    
    override func concludeDragOperation(sender: NSDraggingInfo?) {
        DLog("CONCLUDE")
        
        super.concludeDragOperation(sender)
    }
    
    /* draggingEnded: is implemented as of Mac OS 10.5 */
    override func draggingEnded(sender: NSDraggingInfo?) {
        DLog("ENDED")
        
        super.draggingEnded(sender)
    }
    
    override func updateDraggingItemsForDrag(sender: NSDraggingInfo?) {
        // super.updateDraggingItemsForDrag(sender)
        guard let drag = sender else {
            return
        }
        
        let classes: [AnyClass] = [NSPasteboardItem.self]
        let options: [String: AnyObject] = [NSPasteboardURLReadingContentsConformToTypesKey: [kPasteboardROI]]
        
        drag.enumerateDraggingItemsWithOptions(NSDraggingItemEnumerationOptions.ClearNonenumeratedImages, forView: self, classes: classes, searchOptions: options) {
            (item, idx, stop) in
            // TODO: update dragging image
            //DLog("\(item)")
        }
    }
}
