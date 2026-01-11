//
//  CameraManager.swift
//  TiresiasApp
//
//  Manages camera capture and frame processing
//

import AVFoundation
import UIKit

struct DepthPacket {
    let width: Int
    let height: Int
    let data: Data
}

class CameraManager: NSObject, ObservableObject {
    @Published var isStreaming = false
    @Published var currentFPS: Int = 0
    @Published var hasPermission = false
    
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let processingQueue = DispatchQueue(label: "camera.processing.queue", qos: .userInteractive)
    
    // Frame rate tracking
    private var frameCount = 0
    private var lastFPSUpdate = Date()
    
    // Callback for sending frames
    var onFrameCaptured: ((Data, DepthPacket?) -> Void)?
    
    // Configuration
    private let targetFPS: Double = 30
    private let jpegQuality: CGFloat = 0.25  // Low quality for speed, sufficient for AI
    private let sendEveryNFrames = 2
    private var sendFrameCounter = 0
    private let depthSampleWidth = 160
    private let depthSampleHeight = 120
    private var depthEnabled = false
    private var lastDepthLog = Date()
    
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
            
            // Setup camera input (prefer LiDAR when available)
            let lidarCamera = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
            let camera = lidarCamera ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            guard let camera = camera else {
                print("❌ No back camera found")
                self.session.commitConfiguration()
                return
            }
            
            if lidarCamera != nil {
                print("✅ Using LiDAR depth camera")
            } else {
                print("ℹ️ LiDAR camera not available, using wide angle")
            }
            
            // Set preset before adding inputs
            if self.session.canSetSessionPreset(.inputPriority) {
                self.session.sessionPreset = .inputPriority
            } else if self.session.canSetSessionPreset(.hd1280x720) {
                self.session.sessionPreset = .hd1280x720
            } else {
                self.session.sessionPreset = .medium
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
                
                // Depth configuration (LiDAR devices)
                if let bestFormat = self.selectDepthCapableFormat(for: camera, targetFPS: self.targetFPS) {
                    camera.activeFormat = bestFormat
                }
                let depthFormats = camera.activeFormat.supportedDepthDataFormats
                if let depthFormat = depthFormats.first(where: {
                    CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
                }) {
                    camera.activeDepthDataFormat = depthFormat
                    self.depthEnabled = true
                }
                if !self.depthEnabled {
                    print("⚠️ Depth not enabled. Formats with depth: \(self.countDepthCapableFormats(for: camera))")
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
            if !self.depthEnabled {
                self.videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)
            }
            
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            } else {
                print("❌ Cannot add video output")
                self.session.commitConfiguration()
                return
            }
            
            if self.depthEnabled {
                self.depthOutput.isFilteringEnabled = true
                if self.session.canAddOutput(self.depthOutput) {
                    self.session.addOutput(self.depthOutput)
                } else {
                    print("⚠️ Cannot add depth output, disabling depth")
                    self.depthEnabled = false
                }
            }

            // Set video orientation - must be done after adding output(s)
            if let connection = self.videoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90  // Portrait orientation
            }
            if self.depthEnabled,
               let connection = self.depthOutput.connection(with: .depthData),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }

            if self.depthEnabled {
                self.synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [self.videoOutput, self.depthOutput])
                self.synchronizer?.setDelegate(self, queue: self.processingQueue)
            }
            
            self.session.commitConfiguration()
            print("ℹ️ Depth enabled: \(self.depthEnabled)")
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
            self.sendFrameCounter = 0
            self.lastFPSUpdate = Date()
        }
        print("ℹ️ Streaming depth enabled: \(depthEnabled)")
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

    private func shouldSendFrame() -> Bool {
        sendFrameCounter = (sendFrameCounter + 1) % sendEveryNFrames
        return sendFrameCounter == 0
    }

    private func sampleDepthMap(_ depthBuffer: CVPixelBuffer) -> DepthPacket? {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        let stride = bytesPerRow / MemoryLayout<Float32>.size
        let srcPtr = baseAddress.assumingMemoryBound(to: Float32.self)

        let targetW = depthSampleWidth
        let targetH = depthSampleHeight
        var out = [UInt16](repeating: 0, count: targetW * targetH)

        for y in 0..<targetH {
            let srcY = min(height - 1, Int(Float(y) * Float(height) / Float(targetH)))
            let rowPtr = srcPtr.advanced(by: srcY * stride)
            for x in 0..<targetW {
                let srcX = min(width - 1, Int(Float(x) * Float(width) / Float(targetW)))
                let meters = rowPtr[srcX]
                if meters.isFinite && meters > 0 {
                    let mm = min(Int(meters * 1000.0), Int(UInt16.max))
                    out[y * targetW + x] = UInt16(mm)
                }
            }
        }

        let data = out.withUnsafeBytes { Data($0) }
        return DepthPacket(width: targetW, height: targetH, data: data)
    }

    private func logDepthStatus(_ message: String) {
        let now = Date()
        if now.timeIntervalSince(lastDepthLog) >= 2.0 {
            print(message)
            lastDepthLog = now
        }
    }

    private func selectDepthCapableFormat(for device: AVCaptureDevice, targetFPS: Double) -> AVCaptureDevice.Format? {
        var bestFormat: AVCaptureDevice.Format?
        var bestArea = 0

        for format in device.formats {
            let depthFormats = format.supportedDepthDataFormats
            if depthFormats.isEmpty { continue }

            let ranges = format.videoSupportedFrameRateRanges
            let canHitFPS = ranges.contains { $0.minFrameRate <= targetFPS && targetFPS <= $0.maxFrameRate }
            if !canHitFPS { continue }

            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let area = Int(dims.width * dims.height)
            if area > bestArea {
                bestArea = area
                bestFormat = format
            }
        }

        return bestFormat
    }

    private func countDepthCapableFormats(for device: AVCaptureDevice) -> Int {
        var count = 0
        for format in device.formats {
            if !format.supportedDepthDataFormats.isEmpty {
                count += 1
            }
        }
        return count
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isStreaming else { return }
        guard shouldSendFrame() else { return }
        
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
        
        // Update FPS counter (sent frames)
        updateFPS()
        
        // Send frame via callback
        onFrameCaptured?(jpegData, nil)
    }
}

// MARK: - AVCaptureDataOutputSynchronizerDelegate

extension CameraManager: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard isStreaming else { return }
        guard shouldSendFrame() else { return }

        guard let syncedVideo = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
              !syncedVideo.sampleBufferWasDropped else {
            return
        }
        guard let syncedDepth = synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData else {
            logDepthStatus("⚠️ No synchronized depth data")
            return
        }
        if syncedDepth.depthDataWasDropped {
            logDepthStatus("⚠️ Depth data dropped")
            return
        }

        let sampleBuffer = syncedVideo.sampleBuffer
        guard CMSampleBufferIsValid(sampleBuffer),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: jpegQuality) else {
            return
        }

        var depthPacket: DepthPacket? = nil
        let depthData = syncedDepth.depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        depthPacket = sampleDepthMap(depthData.depthDataMap)
        if depthPacket == nil {
            logDepthStatus("⚠️ Depth map sampling produced no data")
        }

        updateFPS()
        onFrameCaptured?(jpegData, depthPacket)
    }
}
