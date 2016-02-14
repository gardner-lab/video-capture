//
//  PreferencesViewController.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 2/10/16.
//  Copyright © 2016 GardnerLab. All rights reserved.
//

import Cocoa

class PreferencesViewController: NSViewController {
    @IBOutlet weak var userDefaultsController: NSUserDefaultsController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // set defaults
        userDefaultsController?.initialValues = Preferences.defaultPreferences
    }
    
}
