//
//  CameraManager.swift
//  TiresiasApp
//
//  Manages camera capture and frame processing
//

import AVFoundation
import UIKit

class CameraManager: NSObject, ObservableObject {
    @Published var isStreaming = false
    @Published var currentFPS: Int = 0
    @Published var hasPermission = false
    
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let processingQueue = DispatchQueue(label: "camera.processing.queue", qos: .userInteractive)
    
    // Frame rate tracking
    private var frameCount = 0
    private var lastFPSUpdate = Date()
    
    // Callback for sending frames
    var onFrameCaptured: ((Data) -> Void)?
    
    // Configuration
    private let targetFPS: Double = 30
    private let jpegQuality: CGFloat = 0.25  // Low quality for speed, sufficient for AI
    
    override init() {
        super.init()
        setupSession()
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
            
            // Setup camera input
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
            } else {
                print("❌ Cannot add camera input")
                self.session.commitConfiguration()
                return
            }
            
            // Configure camera for optimal frame rate
            do {
                try camera.lockForConfiguration()
                
                // Set frame rate if supported
                let targetFrameDuration = CMTime(value: 1, timescale: CMTimeScale(self.targetFPS))
                if let frameRateRange = camera.activeFormat.videoSupportedFrameRateRanges.first {
                    if frameRateRange.minFrameDuration <= targetFrameDuration && targetFrameDuration <= frameRateRange.maxFrameDuration {
                        camera.activeVideoMinFrameDuration = targetFrameDuration
                        camera.activeVideoMaxFrameDuration = targetFrameDuration
                    }
                }
                
                // Additional optimizations
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
        
        // Convert to JPEG
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
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
