//
//  Regex.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 7/27/15.
//  Copyright © 2015 GardnerLab. All rights reserved.
//

import Foundation

/// [Inspiration](https://gist.github.com/SuperMarioBean/38a5255fc1b14fb74739)
struct Regex {
    let pattern: String
    let options: NSRegularExpressionOptions!
    
    private var matcher: NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: self.pattern, options: self.options)
        }
        catch {
            return NSRegularExpression()
        }
    }
    
    init(pattern: String, options: NSRegularExpressionOptions = .CaseInsensitive) {
        self.pattern = pattern
        self.options = options
    }
    
    func match(string: String, options: NSMatchingOptions = NSMatchingOptions(rawValue: 0)) -> Bool {
        return self.matcher.numberOfMatchesInString(string, options: options, range: NSMakeRange(0, string.utf16.count)) != 0
    }
}