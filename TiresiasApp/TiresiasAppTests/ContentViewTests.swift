//
//  ContentViewTests.swift
//  TiresiasAppTests
//
//  Created by Abhiram Tel on 09/01/26.
//

import XCTest
@testable import TiresiasApp

class ContentViewTests: XCTestCase {

    func testServerIPInitialization_withEnvironmentVariable() {
        // This test requires setting the environment variable "IP_ADDRESS" before running the test.
        // You can do this in your test scheme settings.
        let expectedIP = "10.84.104.88"
        ProcessInfo.processInfo.environment["IP_ADDRESS"] = expectedIP
        
        let contentView = ContentView()
        let serverIP = contentView.serverIP
        
        XCTAssertEqual(serverIP, expectedIP, "The server IP should be initialized from the environment variable.")
    }
    
    func testServerIPInitialization_withoutEnvironmentVariable() {
        ProcessInfo.processInfo.environment.removeValue(forKey: "IP_ADDRESS")
        
        let contentView = ContentView()
        let serverIP = contentView.serverIP
        
        let defaultIP = "127.0.0.1"
        XCTAssertEqual(serverIP, defaultIP, "The server IP should be initialized with the default value when the environment variable is not set.")
    }
}
