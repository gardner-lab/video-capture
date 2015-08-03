//  AppDelegate.swift
//  VideoCapture
//
//  Created by L. Nathan Perkins on 6/28/15.
//  Copyright © 2015

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    private func handleCrashReport() {
        let crashReporter = PLCrashReporter.sharedReporter()
        let crashData: NSData
        
        // load crash data
        do {
            crashData = try crashReporter.loadPendingCrashReportDataAndReturnError()
        }
        catch {
            DLog("CRASH: Unable to load crash log \(error)")
            crashReporter.purgePendingCrashReport()
            return
        }
        
        // TODO: send crash data
        
        crashReporter.purgePendingCrashReport()
    }

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        let crashReporter = PLCrashReporter.sharedReporter()
        
        // has pending report?
        if crashReporter.hasPendingCrashReport() {
            self.handleCrashReport()
        }
        
        // enable crash reporting
        do {
            try crashReporter.enableCrashReporterAndReturnError()
        }
        catch {
            DLog("CRASH: Unable to enable crash reporting \(error)")
        }
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }


}

