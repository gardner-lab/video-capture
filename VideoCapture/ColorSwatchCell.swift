//
//  ColorSwatchCell.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 6/29/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Cocoa

class ColorSwatchCell: NSCell {
    override func drawWithFrame(cellFrame: NSRect, inView controlView: NSView) {
        super.drawWithFrame(cellFrame, inView: controlView)
        
        // Drawing code here.
        if let obj = self.objectValue, let color = obj as? NSColor {
            color.set()
            NSRectFill(cellFrame)
        }
    }
}
