//
//  NavigationAgent.swift
//  TiresiasApp
//
//  Created by Rajsekar Balaji on 1/10/26.
//

import NaturalLanguage
import MapKit
import AVFoundation
import Speech
import CoreLocation
import Foundation
import Accelerate

final class NavigationAgent: NSObject, ObservableObject {
    // Core systems
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    private let synthesizer = AVSpeechSynthesizer()
    private let locationManager = CLLocationManager()
    
    private var silenceTimer: Timer?
    private let silenceThreshold: Float = 0.01
    private let silenceDelay: TimeInterval = 2.0

    override init() {
        super.init()
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    // Request microphone + speech permissions
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("Speech permission: authorized ✅")
                case .denied:
                    print("Speech permission: denied ❌")
                case .restricted:
                    print("Speech permission: restricted ❌")
                case .notDetermined:
                    print("Speech permission: not determined ❌")
                @unknown default:
                    print("Speech permission: unknown ❌")
                }
            }
        }
    }
    // Start listening
    func startListening() {
        guard recognitionTask == nil else {
            print("Recognition already in progress")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("Audio engine failed to start:", error)
            return
        }

        print("🎤 Listening...")

        recognitionTask = speechRecognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                print("Partial transcription:", result.bestTranscription.formattedString)

                if result.isFinal {
                    print("✅ Final transcription:", result.bestTranscription.formattedString)
                    self.stopListening()
                    self.handleUserText(result.bestTranscription.formattedString)
                }
            }

            if let error = error {
                print("Recognition error ❌:", error)
                self.stopListening()
            }
        }

        // Automatically stop after 5 sec to force finalization
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.audioEngine.isRunning {
                print("⏱️ Stopping after timeout")
                self.request?.endAudio() // THIS IS CRUCIAL
            }
        }
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionTask?.finish()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
    }
    
    // Speak text
    func speak(_ text: String) {
            DispatchQueue.main.async {
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = 0.5
                self.synthesizer.speak(utterance)
            }
        }
    
    // MARK: - Destination extraction using Apple NLP
    func extractDestination(from text: String) -> String {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text

        var bestCandidate = ""

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
            if tag == .placeName || tag == .organizationName {
                let name = String(text[tokenRange])
                bestCandidate += name + " "
            }
            return true
        }

        if !bestCandidate.isEmpty {
            return bestCandidate.trimmingCharacters(in: .whitespaces)
        }

        // Fallback — strip common command words
        let commandWords = ["take", "me", "to", "go", "navigate", "find", "get", "directions", "show"]
        let words = text.lowercased().split(separator: " ")
        let filtered = words.filter { !commandWords.contains(String($0)) }
        return filtered.joined(separator: " ")
    }
    
    // Handle the recognized text
    func handleUserText(_ text: String) {
        print("User:", text)
        let destination = extractDestination(from: text)
        print("Parsed destination:", destination)
        getDirections(to: destination)
    }
    
    // MARK: - MapKit
    func searchPlace(named name: String, completion: @escaping (MKMapItem?) -> Void) {
        guard let location = locationManager.location else {
            print("No GPS yet")
            completion(nil)
            return
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )

        MKLocalSearch(request: request).start { response, error in
            completion(response?.mapItems.first)
        }
    }

    func getDirections(to destination: String) {
        searchPlace(named: destination) { place in
            guard let place = place, let userLocation = self.locationManager.location else { return }

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
            request.destination = place
            request.transportType = .walking

            MKDirections(request: request).calculate { response, error in
                guard let route = response?.routes.first else { return }
                let steps = route.steps.map { $0.instructions }
                let spoken = steps.filter { !$0.isEmpty }.joined(separator: ". ")
                self.speak(spoken)
            }
        }
    }
}
