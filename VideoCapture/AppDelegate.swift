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
    
    lazy var version: String = {
        if let dict = Bundle.main.infoDictionary {
            let version: String, build: String
            
            // get version number
            if let v = dict["CFBundleShortVersionString"], let vas = v as? String {
                version = vas
            }
            else {
                version = "?.?.?"
            }
            
            // get build
            if let v = dict["CFBundleVersion"], let vas = v as? String {
                build = vas
            }
            else {
                build = "??"
            }
            
            return "\(version) (\(build))"
        }
        
        return "Unknown"
    }()
    
    let started = Date()
    
    private var usedDevices = [String]()
    private let crashReporter = PLCrashReporter()
    
    // MANAGE LIST OF IN USE DEVICES

    func startUsingDevice(_ deviceID: String) {
        usedDevices.append(deviceID)
    }
    
    func stopUsingDevice(_ deviceID: String) {
        usedDevices = usedDevices.filter { $0 != deviceID }
    }
    
    func isUsingDevice(_ deviceID: String) -> Bool {
        return usedDevices.contains(deviceID)
    }
    
    // CRASH REPORTING
    
    private func processCrashReport(_ crashReport: PLCrashReport) {
        // get string
        let crashReportText = PLCrashReportTextFormatter.stringValue(for: crashReport, with: PLCrashReportTextFormatiOS)
        
        let alert = NSAlert()
        alert.alertStyle = NSAlert.Style.informational
        alert.messageText = "Crash Report"
        alert.informativeText = "The application appears to have crashed during the last use. To help us improve the app and ensure reliable performance, it would help if you could share information anonymous information about the machine and the circumstances of the crash.\n\nIf this computer is connected to the internet, this can be automatically transmitted. Otherwise, we can save the report to a file, which you can send."
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Save...")
        alert.addButton(withTitle: "Cancel")
        
        let resp = alert.runModal()
        
        switch resp {
        case NSApplication.ModalResponse.alertFirstButtonReturn: // Send
            DLog("CRASH: send")
            
            // make request
            let url = URL(string: "https://www.nathanntg.com/gardner/videocapture/crash.php")!
            let req = NSMutableURLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = crashReportText?.data(using: String.Encoding.utf8)
            
            NSURLConnection.sendAsynchronousRequest(req as URLRequest, queue: OperationQueue.main) {
                (resp, dat, err) -> Void in
                if nil == err {
                    DLog("CRASH: logged")
                }
                else {
                    DLog("CRASH: failed \(err!)")
                }
            }
            
        case NSApplication.ModalResponse.alertSecondButtonReturn: // Save
            let panel = NSSavePanel()
            panel.title = "Save Crash Report"
            
            // get prefix
            panel.nameFieldStringValue = "CrashReport.crash"
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.begin {
                (result: Int) -> Void in
                if NSFileHandlingPanelOKButton == result {
                    if let url = panel.url {
                        // remove existing
                        do {
                            try FileManager.default.removeItem(at: url)
                        }
                        catch {}
                        
                        // write
                        do {
                            try crashReportText?.write(to: url, atomically: true, encoding: String.Encoding.utf8)
                        }
                        catch {}
                    }
                }
            }
            
        default: break
        }
    }
    
    private func handleCrashReport() {
        let crashData: Data
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
        let crashData: Data
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

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // has pending report?
        if crashReporter.hasPendingCrashReport() {
            handleCrashReport()
        }
        
        // simulate crash for testing
        //simulateCrashReport()
        
        // enable crash reporting
        do {
            try crashReporter.enableAndReturnError()
        }
        catch {
            DLog("CRASH: Unable to enable crash reporting \(error)")
        }
        
        // register preference defaults
        Preferences.registerDefaults()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}

