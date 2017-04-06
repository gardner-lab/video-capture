//  Common.swift
//  VideoCapture
//
//  Created by L. Nathan Perkins on 7/2/15.
//  Copyright © 2015

import Foundation

/// A logging function that only executes in debugging mode.
func DLog(_ message: String, function: String = #function) {
    #if DEBUG
    print("\(function): \(message)")
    #endif
}

func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let x = a.x - b.x, y = a.y - b.y
    return sqrt((x * x) + (y * y))
}

extension Int {
    func isPowerOfTwo() -> Bool {
        return (self != 0) && (self & (self - 1)) == 0
    }
}

extension Data {
    var hexString: String {
        let charA = UInt8(UnicodeScalar("a").value)
        let char0 = UInt8(UnicodeScalar("0").value)
        
        func itoh(_ value: UInt8) -> UInt8 {
            return (value > 9) ? (charA + value - 10) : (char0 + value)
        }
        
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: count * 2)
        
        for (i, byte) in self.enumerated() {
            ptr[i * 2] = itoh((byte >> 4) & 0xF)
            ptr[i * 2 + 1] = itoh(byte & 0xF)
        }
        
        return String(bytesNoCopy: ptr, length: count * 2, encoding: String.Encoding.utf8, freeWhenDone: true)!
    }
}
