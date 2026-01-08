// ios/TiresiasFrameProcessor.swift
import VisionCamera
import Foundation
import UIKit

@objc(TiresiasFrameProcessorPlugin)
public class TiresiasFrameProcessorPlugin: FrameProcessorPlugin {
  
  public override init(proxy: VisionCameraProxyHolder, options: [AnyHashable : Any]! = [:]) {
    super.init(proxy: proxy, options: options)
    // Initialize connection immediately when camera loads
    SocketManager.shared.connect()
  }

  public override func callback(_ frame: Frame, withArguments arguments: [AnyHashable : Any]?) -> Any? {
    guard let buffer = frame.buffer else { return nil }
    
    // 1. Context Control (Throttle FPS if needed here)
    // For now, we send every frame.
    
    // 2. Convert CMSampleBuffer to UIImage -> JPEG Data
    // Note: This is computationally expensive. In Phase 3, we optimize this
    // by accessing the raw YUV buffer, but for Phase 2, this is easiest.
    guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }
    let ciImage = CIImage(cvPixelBuffer: imageBuffer)
    let context = CIContext()
    
    // Resize for speed (720p is often too big for raw inference, try 640x480)
    // For now, we just compress.
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
    let uiImage = UIImage(cgImage: cgImage)
    
    // 3. Compress to JPEG (0.6 quality is a good balance)
      // New (Lightning Optimized)
      // 0.25 quality is roughly "Low Quality" JPEG but enough for AI detection.
    if let jpegData = uiImage.jpegData(compressionQuality: 0.25) {
//    if let jpegData = uiImage.jpegData(compressionQuality: 0.5) {
        // 4. Send to Mac
        SocketManager.shared.sendFrame(jpegData)
    }

    return nil
  }
}
