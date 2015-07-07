//  ColorSwatchCell.swift
//  VideoCapture
//
//  Created by L. Nathan Perkins on 6/29/15.
//  Copyright © 2015

import Cocoa

/// A simple cell that displays a color.
class ColorSwatchCell: NSCell {
    override func drawWithFrame(cellFrame: NSRect, inView controlView: NSView) {
        super.drawWithFrame(cellFrame, inView: controlView)
        
        // Drawing code here.
        if let obj = self.objectValue where obj is NSColor {
            obj.set()
            NSRectFill(cellFrame)
        }
    }
}
