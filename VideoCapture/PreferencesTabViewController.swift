//
//  PreferencesTabViewController.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 2/14/16.
//  Copyright © 2016 GardnerLab. All rights reserved.
//

import Cocoa

class PreferencesTabViewController: NSTabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // add icons
        tabViewItems[0].image = NSImage(named: "Arduino")
        tabViewItems[1].image = NSImage(named: "Video")
    }
}


