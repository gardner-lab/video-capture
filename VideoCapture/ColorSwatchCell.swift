//  ColorSwatchCell.swift
//  VideoCapture
//
//  Created by L. Nathan Perkins on 6/29/15.
//  Copyright © 2015

import Cocoa

/// A simple cell that displays a color.
class ColorSwatchCell: NSCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.draw(withFrame: cellFrame, in: controlView)
        
        // Drawing code here.
        if let obj = self.objectValue, let color = obj as? NSColor {
            color.set()
            cellFrame.fill()
        }
    }
}
