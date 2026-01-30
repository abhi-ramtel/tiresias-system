//
//  CameraManager.swift
//  TiresiasApp
//
//  Manages camera capture and frame processing
//

import AVFoundation
import UIKit

enum CameraZoomLevel: String, CaseIterable {
    case ultraWide = "0.5x"
    case wide = "1x"
    
    var displayName: String { rawValue }
    
    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide: return .builtInWideAngleCamera
        }
    }
}

class CameraManager: NSObject, ObservableObject {
    @Published var isStreaming = false
    @Published var currentFPS: Int = 0
    @Published var hasPermission = false
    @Published var currentZoom: CameraZoomLevel = .wide
    @Published var isUltraWideAvailable = false
    
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let processingQueue = DispatchQueue(label: "camera.processing.queue", qos: .userInteractive)
    
    // Current camera input
    private var currentInput: AVCaptureDeviceInput?
    
    // Frame rate tracking
    private var frameCount = 0
    private var lastFPSUpdate = Date()
    
    // Callback for sending frames
    var onFrameCaptured: ((Data) -> Void)?
    
    // Configuration
    private let targetFPS: Double = 30
    private let jpegQuality: CGFloat = 0.25  // Slightly higher for path detection
    
    // Performance optimization - reuse CIContext
    private lazy var ciContext: CIContext = {
        CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: false,
            .cacheIntermediates: false
        ])
    }()
    
    // Frame skipping for when path overlay is active
    private var skipCounter = 0
    private let skipEveryNFrames = 2  // Send every other frame when needed
    
    override init() {
        super.init()
        checkUltraWideAvailability()
        setupSession()
    }
    
    private func checkUltraWideAvailability() {
        let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        DispatchQueue.main.async {
            self.isUltraWideAvailable = ultraWide != nil
        }
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async {
                self.hasPermission = true
            }
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.hasPermission = granted
                    if granted {
                        self?.startSession()
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.hasPermission = false
            }
        }
    }
    
    // MARK: - Camera Switching
    
    func switchCamera(to zoom: CameraZoomLevel) {
        guard zoom != currentZoom else { return }
        
        // Check if ultra-wide is available
        if zoom == .ultraWide && !isUltraWideAvailable {
            print("⚠️ Ultra-wide camera not available on this device")
            return
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Get the target camera
            guard let newCamera = AVCaptureDevice.default(zoom.deviceType, for: .video, position: .back) else {
                print("❌ Camera not available: \(zoom.displayName)")
                return
            }
            
            // Create new input
            let newInput: AVCaptureDeviceInput
            do {
                newInput = try AVCaptureDeviceInput(device: newCamera)
            } catch {
                print("❌ Failed to create camera input: \(error)")
                return
            }
            
            // Reconfigure session
            self.session.beginConfiguration()
            
            // Remove current input
            if let currentInput = self.currentInput {
                self.session.removeInput(currentInput)
            }
            
            // Add new input
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput
                
                // Configure new camera
                self.configureCamera(newCamera)
                
                // Update video orientation
                if let connection = self.videoOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                }
                
                DispatchQueue.main.async {
                    self.currentZoom = zoom
                }
                print("✅ Switched to \(zoom.displayName) camera")
            } else {
                print("❌ Cannot add camera input")
            }
            
            self.session.commitConfiguration()
        }
    }
    
    private func configureCamera(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            
            // Set frame rate
            let targetFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            if let frameRateRange = camera.activeFormat.videoSupportedFrameRateRanges.first {
                if frameRateRange.minFrameDuration <= targetFrameDuration && targetFrameDuration <= frameRateRange.maxFrameDuration {
                    camera.activeVideoMinFrameDuration = targetFrameDuration
                    camera.activeVideoMaxFrameDuration = targetFrameDuration
                }
            }
            
            // Auto-focus and exposure
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            camera.unlockForConfiguration()
        } catch {
            print("⚠️ Could not configure camera: \(error)")
        }
    }
    
    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Don't reconfigure if already set up
            guard self.session.inputs.isEmpty else {
                print("⚠️ Session already configured")
                return
            }
            
            self.session.beginConfiguration()
            
            // Set preset before adding inputs
            if self.session.canSetSessionPreset(.hd1280x720) {
                self.session.sessionPreset = .hd1280x720
            } else {
                self.session.sessionPreset = .medium
            }
            
            // Setup camera input - start with wide angle (1x)
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("❌ No back camera found")
                self.session.commitConfiguration()
                return
            }
            
            // Create input
            let input: AVCaptureDeviceInput
            do {
                input = try AVCaptureDeviceInput(device: camera)
            } catch {
                print("❌ Failed to create camera input: \(error)")
                self.session.commitConfiguration()
                return
            }
            
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.currentInput = input
            } else {
                print("❌ Cannot add camera input")
                self.session.commitConfiguration()
                return
            }
            
            // Configure camera
            self.configureCamera(camera)
            
            // Setup video output
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)
            
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            } else {
                print("❌ Cannot add video output")
                self.session.commitConfiguration()
                return
            }
            
            // Set video orientation - must be done after adding output
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90  // Portrait orientation
                }
            }
            
            self.session.commitConfiguration()
            print("✅ Camera session configured successfully")
        }
    }
    
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.session.isRunning else {
                print("⚠️ Session already running")
                return
            }
            self.session.startRunning()
            print("🎥 Camera session started")
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.session.isRunning else {
                print("⚠️ Session not running")
                return
            }
            self.session.stopRunning()
            print("🛑 Camera session stopped")
        }
    }
    
    func startStreaming() {
        DispatchQueue.main.async {
            self.isStreaming = true
            self.frameCount = 0
            self.lastFPSUpdate = Date()
        }
        print("📡 Streaming started")
    }
    
    func stopStreaming() {
        DispatchQueue.main.async {
            self.isStreaming = false
            self.currentFPS = 0
        }
        print("📡 Streaming stopped")
    }
    
    private func updateFPS() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)
        
        if elapsed >= 1.0 {
            let fps = Int(Double(frameCount) / elapsed)
            DispatchQueue.main.async {
                self.currentFPS = fps
            }
            frameCount = 0
            lastFPSUpdate = now
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isStreaming else { return }
        
        // Skip frames to reduce load
        skipCounter += 1
        guard skipCounter % skipEveryNFrames == 0 else { return }
        
        // Ensure we're working with a valid buffer
        guard CMSampleBufferIsValid(sampleBuffer),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Lock the pixel buffer for reading
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
        }
        
        // Convert to JPEG using reused context
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        guard let jpegData = uiImage.jpegData(compressionQuality: jpegQuality) else {
            return
        }
        
        // Update FPS counter
        updateFPS()
        
        // Send frame via callback
        onFrameCaptured?(jpegData)
    }
}
