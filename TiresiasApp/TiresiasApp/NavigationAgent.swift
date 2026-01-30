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
    
    // Callback for real-time navigation
    private var destinationCallback: ((String) -> Void)?
    
    // Flag to prevent recording our own speech
    private var isListeningActive = false

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
    
    // Start listening with callback for real-time navigation
    func startListeningWithCallback(_ callback: @escaping (String) -> Void) {
        destinationCallback = callback
        startListening()
    }
    
    // Start listening
    func startListening() {
        // Stop any existing session
        stopListening()
        
        isListeningActive = true
        
        // CRITICAL: Configure audio session FIRST
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("✅ Audio session configured for recording")
        } catch {
            print("❌ Audio session setup failed:", error)
            isListeningActive = false
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        
        // Get the native format from the input node - must be done AFTER audio session is active
        let nativeFormat = inputNode.inputFormat(forBus: 0)
        
        // Use native format if valid, otherwise create a standard recording format
        let recordingFormat: AVAudioFormat
        if nativeFormat.sampleRate > 0 {
            recordingFormat = nativeFormat
            print("✅ Using native format: \(nativeFormat.sampleRate) Hz")
        } else {
            // Fallback to standard recording format
            guard let fallbackFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
                print("❌ Could not create fallback audio format")
                isListeningActive = false
                return
            }
            recordingFormat = fallbackFormat
            print("⚠️ Using fallback format: 44100 Hz")
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("❌ Audio engine failed to start:", error)
            stopListening()
            return
        }

        print("🎤 Listening... (speak now)")
        // Don't speak while listening - it will record the TTS!
        // Use haptic feedback instead
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                print("Partial transcription:", text)

                if result.isFinal {
                    print("✅ Final transcription:", text)
                    self.stopListening()
                    self.handleUserText(text)
                }
            }

            if let error = error {
                print("❌ Recognition error:", error)
                self.stopListening()
            }
        }

        // Automatically stop after 5 sec to force finalization
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            if self.audioEngine.isRunning {
                print("⏱️ Stopping after timeout")
                self.request?.endAudio()
            }
        }
    }

    func stopListening() {
        isListeningActive = false
        
        request?.endAudio()
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        
        // Reset audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("⚠️ Audio session reset failed:", error)
        }
    }
    
    // Speak text (only when not listening)
    func speak(_ text: String) {
        // Don't speak if we're actively listening - it will record our own voice!
        guard !isListeningActive else {
            print("⚠️ Skipping TTS while listening")
            return
        }
        
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
        let commandWords = ["take", "me", "to", "go", "navigate", "find", "get", "directions", "show", "the", "a", "an"]
        let words = text.lowercased().split(separator: " ")
        let filtered = words.filter { !commandWords.contains(String($0)) }
        return filtered.joined(separator: " ")
    }
    
    // Handle the recognized text
    func handleUserText(_ text: String) {
        print("User said:", text)
        let destination = extractDestination(from: text)
        print("Parsed destination:", destination)
        
        // If callback is set, use it for real-time navigation
        if let callback = destinationCallback {
            destinationCallback = nil // Clear callback
            callback(destination)
        } else {
            // Fallback: just speak directions once
            getDirections(to: destination)
        }
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
        print("🗺️ Getting directions to: \(destination)")
        speak("Finding directions to \(destination)")
        
        searchPlace(named: destination) { [weak self] place in
            guard let self = self else { return }
            
            guard let place = place else {
                print("❌ Place not found: \(destination)")
                self.speak("Could not find \(destination)")
                return
            }
            
            guard let userLocation = self.locationManager.location else {
                print("❌ No user location available")
                self.speak("Cannot get your current location")
                return
            }
            
            print("✅ Found place: \(place.name ?? destination)")

            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
            request.destination = place
            request.transportType = .walking

            MKDirections(request: request).calculate { [weak self] response, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Directions error: \(error)")
                    self.speak("Could not calculate route")
                    return
                }
                
                guard let route = response?.routes.first else {
                    print("❌ No routes found")
                    self.speak("No walking route available")
                    return
                }
                
                let steps = route.steps.map { $0.instructions }
                let validSteps = steps.filter { !$0.isEmpty }
                
                print("✅ Got \(validSteps.count) navigation steps")
                
                if validSteps.isEmpty {
                    self.speak("The destination is very close. Walk straight ahead.")
                } else {
                    let spoken = validSteps.joined(separator: ". ")
                    print("📢 Speaking: \(spoken)")
                    self.speak(spoken)
                }
            }
        }
    }
}
