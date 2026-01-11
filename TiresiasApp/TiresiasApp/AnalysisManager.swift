//
//  AnalysisManager.swift
//  TiresiasApp
//
//  Polls the server for analysis results
//

import Foundation

struct AnalysisResponse: Decodable {
    let success: Bool?
    let summary: String?
    let warnings: [String]?
}

class AnalysisManager: ObservableObject {
    @Published var summary: String = ""
    @Published var warnings: [String] = []
    
    private var timer: Timer?
    private var isRequestInFlight = false
    private var serverIP: String = ""
    private var interval: TimeInterval = 1.0
    private let serverPort = 8000
    
    func start(serverIP: String, interval: TimeInterval) {
        let newInterval = max(0.5, interval)
        let shouldRestart = timer != nil && (serverIP != self.serverIP || newInterval != self.interval)
        self.serverIP = serverIP
        self.interval = newInterval
        
        if shouldRestart {
            stop()
        }
        if timer != nil { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { [weak self] _ in
            self?.fetchLatestAnalysis()
        }
        fetchLatestAnalysis()
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func fetchLatestAnalysis() {
        guard !isRequestInFlight else { return }
        isRequestInFlight = true
        
        let urlString = "http://\(serverIP):\(serverPort)/analyse/frame"
        guard let url = URL(string: urlString) else {
            isRequestInFlight = false
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            defer { self?.isRequestInFlight = false }
            guard let data = data else { return }
            let decoder = JSONDecoder()
            guard let response = try? decoder.decode(AnalysisResponse.self, from: data),
                  response.success == true else {
                return
            }
            
            DispatchQueue.main.async {
                self?.summary = response.summary ?? ""
                self?.warnings = response.warnings ?? []
            }
        }.resume()
    }
}
