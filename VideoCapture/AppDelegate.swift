//  AppDelegate.swift
//  VideoCapture
//
//  Created by L. Nathan Perkins on 6/28/15.
//  Copyright © 2015

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    // get instance
    class var instance: AppDelegate {
        get {
            return NSApp.delegate as! AppDelegate
        }
    }
    
    private var usedDevices = [String]()
    private let crashReporter = PLCrashReporter()
    
    // MANAGE LIST OF IN USE DEVICES

    func startUsingDevice(deviceID: String) {
        usedDevices.append(deviceID)
    }
    
    func stopUsingDevice(deviceID: String) {
        usedDevices = usedDevices.filter { $0 != deviceID }
    }
    
    func isUsingDevice(deviceID: String) -> Bool {
        return usedDevices.contains(deviceID)
    }
    
    // CRASH REPORTING
    
    private func processCrashReport(crashReport: PLCrashReport) {
        // get string
        let crashReportText = PLCrashReportTextFormatter.stringValueForCrashReport(crashReport, withTextFormat: PLCrashReportTextFormatiOS)
        
        let alert = NSAlert()
        alert.alertStyle = NSAlertStyle.InformationalAlertStyle
        alert.messageText = "Crash Report"
        alert.informativeText = "The application appears to have crashed during the last use. To help us improve the app and ensure reliable performance, it would help if you could share information anonymous information about the machine and the circumstances of the crash.\n\nIf this computer is connected to the internet, this can be automatically transmitted. Otherwise, we can save the report to a file, which you can send."
        alert.addButtonWithTitle("Send")
        alert.addButtonWithTitle("Save...")
        alert.addButtonWithTitle("Cancel")
        
        let resp = alert.runModal()
        
        switch resp {
        case NSAlertFirstButtonReturn: // Send
            DLog("CRASH: send")
            
            // make request
            let url = NSURL(string: "https://www.nathanntg.com/gardner/videocapture/crash.php")!
            let req = NSMutableURLRequest(URL: url)
            req.HTTPMethod = "POST"
            req.HTTPBody = crashReportText.dataUsingEncoding(NSUTF8StringEncoding)
            
            NSURLConnection.sendAsynchronousRequest(req, queue: NSOperationQueue.mainQueue()) {
                (resp, dat, err) -> Void in
                if nil == err {
                    DLog("CRASH: logged")
                }
                else {
                    DLog("CRASH: failed \(err)")
                }
            }
            
        case NSAlertSecondButtonReturn: // Save
            let panel = NSSavePanel()
            panel.title = "Save Crash Report"
            
            // get prefix
            panel.nameFieldStringValue = "CrashReport.crash"
            panel.canCreateDirectories = true
            panel.extensionHidden = false
            panel.beginWithCompletionHandler {
                (result: Int) -> Void in
                if NSFileHandlingPanelOKButton == result {
                    if let url = panel.URL {
                        // remove existing
                        do {
                            try NSFileManager.defaultManager().removeItemAtURL(url)
                        }
                        catch {}
                        
                        // write
                        do {
                            try crashReportText.writeToURL(url, atomically: true, encoding: NSUTF8StringEncoding)
                        }
                        catch {}
                    }
                }
            }
            
        default: break
        }
    }
    
    private func handleCrashReport() {
        let crashData: NSData
        let crashReport: PLCrashReport
        
        // load crash data
        do {
            crashData = try crashReporter.loadPendingCrashReportDataAndReturnError()
            crashReport = try PLCrashReport(data: crashData)
        }
        catch {
            DLog("CRASH: Unable to load or parse crash log \(error)")
            crashReporter.purgePendingCrashReport()
            return
        }
        
        // process
        processCrashReport(crashReport)
        
        // purge
        crashReporter.purgePendingCrashReport()
    }
    
    private func simulateCrashReport() {
        let crashData: NSData
        let crashReport: PLCrashReport
        
        // load crash data
        do {
            crashData = try crashReporter.generateLiveReportAndReturnError()
            crashReport = try PLCrashReport(data: crashData)
        }
        catch {
            DLog("CRASH: Unable to load or parse crash log \(error)")
            crashReporter.purgePendingCrashReport()
            return
        }
        
        processCrashReport(crashReport)
    }

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // has pending report?
        if crashReporter.hasPendingCrashReport() {
            handleCrashReport()
        }
        
        // simulate crash for testing
        //simulateCrashReport()
        
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

