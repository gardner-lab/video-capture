//
//  ArduinoIOTests.swift
//  VideoCapture
//
//  Created by Nathan Perkins on 2/26/16.
//  Copyright © 2016 GardnerLab. All rights reserved.
//

import XCTest

@testable import VideoCapture

class ArduinoIOTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testPacketDescriptorNonEmpty() {
        let desc = DelimitedSerialPacketDescriptor(delimiter: "\r\n".data(using: String.Encoding.ascii)!, maximumPacketLength: 32, userInfo: nil, responseEvaluator: {
            (d: Data?) -> Bool in
            guard let data = d else {
                return false
            }
            return data.count > 0
        })
        
        let toTest: [(String, String?)] = [
            ("No\r\nFinal", nil),
            ("\r\nTesting\r\n", "Testing"),
            ("T\r", nil),
            ("\r\nMultiple\r\nStrings\r\nIn\r\nRow\r\n", "Row"),
            ("\r\n", nil),
            ("\r\n\r\n", "\r\n"),
            ("Blah\r\n", "Blah")
        ]
        
        for (stringIn, stringOut) in toTest {
            let dataIn = stringIn.data(using: String.Encoding.ascii)!
            let dataOut: Data? = stringOut?.data(using: String.Encoding.ascii)! ?? nil
            
            XCTAssertEqual(dataOut, desc.packetMatching(atEndOfBuffer: dataIn))
        }
    }
    
    func testPacketDescriptorEmpty() {
        let desc = DelimitedSerialPacketDescriptor(delimiter: "\r\n".data(using: String.Encoding.ascii)!, maximumPacketLength: 16, userInfo: nil, responseEvaluator: {
            (d: Data?) -> Bool in
            return d != nil
        })
        
        let toTest: [(String, String?)] = [
            ("\r\n\r", nil),
            ("\r\n", ""),
            ("\r\n\r\n", "")
        ]
        
        for (stringIn, stringOut) in toTest {
            let dataIn = stringIn.data(using: String.Encoding.ascii)!
            let dataOut: Data? = stringOut?.data(using: String.Encoding.ascii)! ?? nil
            
            XCTAssertEqual(dataOut, desc.packetMatching(atEndOfBuffer: dataIn))
        }
    }
}
