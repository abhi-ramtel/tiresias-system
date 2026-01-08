//
//  TiresiasFrameProcessor.m
//  
//
//  Created by Abhi Ramtel on 1/7/26.
//

// ios/TiresiasFrameProcessor.m
#import <Foundation/Foundation.h>
#import <VisionCamera/FrameProcessorPlugin.h>
#import <VisionCamera/FrameProcessorPluginRegistry.h>

// Register the Swift plugin so React Native can find it
VISION_EXPORT_SWIFT_FRAME_PROCESSOR(TiresiasFrameProcessorPlugin, tiresias_stream)
