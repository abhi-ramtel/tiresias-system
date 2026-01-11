//
//  CameraManager.swift
//  TiresiasApp
//
//  Manages camera capture and frame processing
//

import AVFoundation
import UIKit
import Vision
import CoreML

enum DepthMode: String, CaseIterable {
    case off
    case lidar
    case monocular
}

struct DepthPacket {
    let width: Int
    let height: Int
    let data: Data
}

struct DepthMap {
    let width: Int
    let height: Int
    let values: [Float]
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
    var onDepthUpdated: ((DepthMap) -> Void)?
    
    // Configuration
    private var targetFPS: Double = 15
    private var jpegQuality: CGFloat = 0.15
    private var frameSendStride = 1
    private var sendFrameCounter = 0
    private var depthMode: DepthMode = .off
    private var depthStride = 2
    private var sendDepthCounter = 0
    private var depthEnabled = false
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var currentDevice: AVCaptureDevice?
    private var monocularEstimator = MonocularDepthEstimator()
    
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
            
            guard self.session.inputs.isEmpty else {
                print("⚠️ Session already configured")
                return
            }
            
            self.session.beginConfiguration()
            
            if self.session.canSetSessionPreset(.inputPriority) {
                self.session.sessionPreset = .inputPriority
            } else if self.session.canSetSessionPreset(.hd1280x720) {
                self.session.sessionPreset = .hd1280x720
            } else {
                self.session.sessionPreset = .medium
            }
            
            let lidarCamera = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
            let camera = lidarCamera ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            guard let camera = camera else {
                print("❌ No back camera found")
                self.session.commitConfiguration()
                return
            }
            self.currentDevice = camera
            
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
            
            do {
                try camera.lockForConfiguration()
                let targetFrameDuration = CMTime(value: 1, timescale: CMTimeScale(self.targetFPS))
                if let frameRateRange = camera.activeFormat.videoSupportedFrameRateRanges.first {
                    if frameRateRange.minFrameDuration <= targetFrameDuration && targetFrameDuration <= frameRateRange.maxFrameDuration {
                        camera.activeVideoMinFrameDuration = targetFrameDuration
                        camera.activeVideoMaxFrameDuration = targetFrameDuration
                    }
                }
                
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
            
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            } else {
                print("❌ Cannot add video output")
                self.session.commitConfiguration()
                return
            }
            
            if let connection = self.videoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }

            if lidarCamera != nil {
                let depthFormats = camera.activeFormat.supportedDepthDataFormats
                if let depthFormat = depthFormats.first(where: {
                    CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
                }) {
                    do {
                        try camera.lockForConfiguration()
                        camera.activeDepthDataFormat = depthFormat
                        camera.unlockForConfiguration()
                        self.depthEnabled = true
                    } catch {
                        print("⚠️ Could not enable depth format: \(error)")
                    }
                }
            }

            if !self.depthEnabled {
                self.videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)
            }

            if self.depthEnabled {
                self.depthOutput.isFilteringEnabled = true
                if self.session.canAddOutput(self.depthOutput) {
                    self.session.addOutput(self.depthOutput)
                } else {
                    self.depthEnabled = false
                }
            }

            if self.depthEnabled,
               let connection = self.depthOutput.connection(with: .depthData),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }

            if self.depthEnabled {
                self.synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [self.videoOutput, self.depthOutput])
                self.synchronizer?.setDelegate(self, queue: self.processingQueue)
                self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
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
            self.sendFrameCounter = 0
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
    
    private func shouldSendFrame() -> Bool {
        sendFrameCounter = (sendFrameCounter + 1) % max(1, frameSendStride)
        return sendFrameCounter == 0
    }

    private func shouldSendDepth() -> Bool {
        sendDepthCounter = (sendDepthCounter + 1) % max(1, depthStride)
        return sendDepthCounter == 0
    }
    
    func applySettings(targetFPS: Double, preset: AVCaptureSession.Preset, jpegQuality: CGFloat, frameStride: Int, depthMode: DepthMode, depthStride: Int) {
        let clampedFPS = max(5, min(targetFPS, 30))
        let clampedQuality = max(0.1, min(jpegQuality, 0.7))
        let clampedFrameStride = max(1, frameStride)
        let clampedDepthStride = max(1, depthStride)
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.targetFPS = clampedFPS
            self.jpegQuality = clampedQuality
            self.frameSendStride = clampedFrameStride
            self.depthMode = depthMode
            self.depthStride = clampedDepthStride
            
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(preset) {
                self.session.sessionPreset = preset
            }
            
            if let camera = self.currentDevice {
                do {
                    try camera.lockForConfiguration()
                    let targetFrameDuration = CMTime(value: 1, timescale: CMTimeScale(self.targetFPS))
                    if let range = camera.activeFormat.videoSupportedFrameRateRanges.first,
                       range.minFrameDuration <= targetFrameDuration && targetFrameDuration <= range.maxFrameDuration {
                        camera.activeVideoMinFrameDuration = targetFrameDuration
                        camera.activeVideoMaxFrameDuration = targetFrameDuration
                    }
                    camera.unlockForConfiguration()
                } catch {
                    print("⚠️ Could not update camera settings: \(error)")
                }
            }
            self.session.commitConfiguration()
        }
    }

    static func supportsLiDARDepth() -> Bool {
        return AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil
    }

    static func supportsMonocularDepth() -> Bool {
        return Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc") != nil
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isStreaming else { return }
        guard shouldSendFrame() else { return }
        
        guard CMSampleBufferIsValid(sampleBuffer),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: jpegQuality) else {
            return
        }
        
        updateFPS()
        onFrameCaptured?(jpegData, nil)

        if depthMode == .monocular, shouldSendDepth() {
            monocularEstimator.estimateDepth(from: imageBuffer) { [weak self] depthMap in
                guard let self = self, let depthMap = depthMap else { return }
                self.onDepthUpdated?(depthMap)
            }
        }
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

        let sampleBuffer = syncedVideo.sampleBuffer
        guard CMSampleBufferIsValid(sampleBuffer),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: jpegQuality) else {
            return
        }

        var depthPacket: DepthPacket? = nil
        if depthMode == .lidar, depthEnabled, shouldSendDepth() {
            if let syncedDepth = synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData,
               !syncedDepth.depthDataWasDropped {
                let depthData = syncedDepth.depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
                depthPacket = sampleDepthPacket(depthData.depthDataMap)
                if let depthMap = sampleDepthMap(depthData.depthDataMap) {
                    onDepthUpdated?(depthMap)
                }
            }
        } else if depthMode == .monocular, shouldSendDepth() {
            monocularEstimator.estimateDepth(from: imageBuffer) { [weak self] depthMap in
                guard let self = self, let depthMap = depthMap else { return }
                self.onDepthUpdated?(depthMap)
            }
        }

        updateFPS()
        onFrameCaptured?(jpegData, depthPacket)
    }
}

private extension CameraManager {
    func sampleDepthPacket(_ depthBuffer: CVPixelBuffer) -> DepthPacket? {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        let stride = bytesPerRow / MemoryLayout<Float32>.size
        let srcPtr = baseAddress.assumingMemoryBound(to: Float32.self)

        let targetW = 128
        let targetH = 96
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

    func sampleDepthMap(_ depthBuffer: CVPixelBuffer) -> DepthMap? {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        let stride = bytesPerRow / MemoryLayout<Float32>.size
        let srcPtr = baseAddress.assumingMemoryBound(to: Float32.self)

        var values = [Float](repeating: 0, count: width * height)
        var minV: Float = .greatestFiniteMagnitude
        var maxV: Float = 0
        for y in 0..<height {
            let rowPtr = srcPtr.advanced(by: y * stride)
            for x in 0..<width {
                let meters = rowPtr[x]
                let idx = y * width + x
                if meters.isFinite && meters > 0 {
                    values[idx] = meters
                    minV = min(minV, meters)
                    maxV = max(maxV, meters)
                }
            }
        }
        if minV == .greatestFiniteMagnitude || maxV <= minV {
            return nil
        }
        let range = maxV - minV
        let normalized = values.map { $0 > 0 ? (1.0 - (($0 - minV) / range)) : 0 }
        return DepthMap(width: width, height: height, values: normalized)
    }
}

private class MonocularDepthEstimator {
    private let model: VNCoreMLModel?
    private let request: VNCoreMLRequest?
    private let queue = DispatchQueue(label: "depth.monocular.queue", qos: .userInitiated)
    private var isBusy = false

    init() {
        if let url = Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc"),
           let mlModel = try? MLModel(contentsOf: url),
           let vnModel = try? VNCoreMLModel(for: mlModel) {
            self.model = vnModel
            let req = VNCoreMLRequest(model: vnModel)
            req.imageCropAndScaleOption = .scaleFill
            self.request = req
        } else {
            self.model = nil
            self.request = nil
        }
    }

    func estimateDepth(from pixelBuffer: CVPixelBuffer, completion: @escaping (DepthMap?) -> Void) {
        guard let request = request else {
            completion(nil)
            return
        }
        guard !isBusy else {
            completion(nil)
            return
        }
        isBusy = true
        queue.async { [weak self] in
            defer {
                self?.isBusy = false
            }
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                completion(nil)
                return
            }
            if let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
               let multiArray = observation.featureValue.multiArrayValue {
                completion(DepthMap.from(multiArray: multiArray))
                return
            }
            if let observation = request.results?.first as? VNPixelBufferObservation {
                completion(DepthMap.from(pixelBuffer: observation.pixelBuffer))
                return
            }
            completion(nil)
        }
    }
}

private extension DepthMap {
    static func from(multiArray: MLMultiArray) -> DepthMap? {
        let shape = multiArray.shape.map { $0.intValue }
        let stride = multiArray.strides.map { $0.intValue }
        let width: Int
        let height: Int
        if shape.count == 2 {
            height = shape[0]
            width = shape[1]
        } else if shape.count == 3 {
            height = shape[1]
            width = shape[2]
        } else {
            return nil
        }

        var values = [Float](repeating: 0, count: width * height)
        var minV: Float = .greatestFiniteMagnitude
        var maxV: Float = -.greatestFiniteMagnitude

        for y in 0..<height {
            for x in 0..<width {
                let index: Int
                if shape.count == 2 {
                    index = y * stride[0] + x * stride[1]
                } else {
                    index = 0 * stride[0] + y * stride[1] + x * stride[2]
                }
                let value = multiArray[index].floatValue
                let idx = y * width + x
                values[idx] = value
                minV = min(minV, value)
                maxV = max(maxV, value)
            }
        }

        if maxV <= minV {
            return nil
        }
        let range = maxV - minV
        let normalized = values.map { 1.0 - (($0 - minV) / range) }
        return DepthMap(width: width, height: height, values: normalized)
    }

    static func from(pixelBuffer: CVPixelBuffer) -> DepthMap? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let stride = bytesPerRow / MemoryLayout<Float32>.size
        let srcPtr = baseAddress.assumingMemoryBound(to: Float32.self)

        var values = [Float](repeating: 0, count: width * height)
        var minV: Float = .greatestFiniteMagnitude
        var maxV: Float = -.greatestFiniteMagnitude

        for y in 0..<height {
            let rowPtr = srcPtr.advanced(by: y * stride)
            for x in 0..<width {
                let value = rowPtr[x]
                let idx = y * width + x
                values[idx] = value
                minV = min(minV, value)
                maxV = max(maxV, value)
            }
        }

        if maxV <= minV {
            return nil
        }
        let range = maxV - minV
        let normalized = values.map { 1.0 - (($0 - minV) / range) }
        return DepthMap(width: width, height: height, values: normalized)
    }
}
