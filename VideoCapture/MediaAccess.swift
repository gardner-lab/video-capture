//
//  MediaAccess.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 3/26/19.
//  Copyright © 2019 GardnerLab. All rights reserved.
//

import Foundation
import AVFoundation

func checkMediaAccess(_ access: [AVMediaType], onSuccess: @escaping () -> (), onFailure: @escaping () -> ()) {
    // enforce media access
    if #available(OSX 10.14, *) {
        // no access levels required? success
        if access.count == 0 {
            onSuccess()
            return
        }
        
        var accessSubset = access
        let accessCurrent = accessSubset.removeFirst()
        
        // check permissions
        switch AVCaptureDevice.authorizationStatus(for: accessCurrent) {
        case .notDetermined:
            // prompt for access
            AVCaptureDevice.requestAccess(for: accessCurrent) { (granted: Bool) in
                if granted {
                    checkMediaAccess(accessSubset, onSuccess: onSuccess, onFailure: onFailure)
                }
                else {
                    onFailure()
                }
            }
            
        case .authorized:
            // check for remaining
            checkMediaAccess(accessSubset, onSuccess: onSuccess, onFailure: onFailure)
            
        case .denied, .restricted:
            // call failure and stop
            onFailure()
            
        @unknown default:
            fatalError("Unknown authorization status.")
        }
    }
    else {
        onSuccess()
    }
}
