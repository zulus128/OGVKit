//
//  OGVVideoBuffer.m
//  OGVKit
//
//  Created by Brion on 11/5/13.
//  Copyright (c) 2013-2015 Brion Vibber. All rights reserved.
//

#import "OGVKit.h"

@implementation OGVVideoBuffer

- (instancetype)initWithFormat:(OGVVideoFormat *)format
                             Y:(OGVVideoPlane *)Y
                            Cb:(OGVVideoPlane *)Cb
                            Cr:(OGVVideoPlane *)Cr
                     timestamp:(float)timestamp
{
    self = [super init];
    if (self) {
        _format = format;
        _Y = Y;
        _Cb = Cb;
        _Cr = Cr;
        _timestamp = timestamp;
    }
    return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
    return [[OGVVideoBuffer alloc] initWithFormat:self.format
                                                Y:[self.Y copyWithZone:zone]
                                               Cb:[self.Cb copyWithZone:zone]
                                               Cr:[self.Cr copyWithZone:zone]
                                        timestamp:self.timestamp];
}


static void releasePixelBufferBacking(void *releaseRefCon, const void *dataPtr, size_t dataSize, size_t numberOfPlanes, const void * _Nullable planeAddresses[])
{
    CFTypeRef buf = (CFTypeRef)releaseRefCon;
    CFRelease(buf);
}

-(CMSampleBufferRef)copyAsSampleBuffer
{
    OGVVideoBuffer *buffer = self;
    
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

    CVImageBufferRef imageBuffer;
    NSDictionary *opts = @{
                           (NSString *)kCVPixelBufferExtendedPixelsLeftKey: @(buffer.format.pictureOffsetX),
                           (NSString *)kCVPixelBufferExtendedPixelsTopKey: @(buffer.format.pictureOffsetY),
                           (NSString *)kCVPixelBufferExtendedPixelsRightKey: @(buffer.format.frameWidth - buffer.format.pictureWidth - buffer.format.pictureOffsetX),
                           (NSString *)kCVPixelBufferExtendedPixelsBottomKey: @(buffer.format.frameHeight - buffer.format.pictureHeight - buffer.format.pictureOffsetY),
                           (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
                           };
    OSType ok = CVPixelBufferCreate(NULL, buffer.format.frameWidth, buffer.format.frameHeight, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, (__bridge CFDictionaryRef _Nullable)(opts), &imageBuffer);
    if (ok != kCVReturnSuccess) {
        NSLog(@"pixel buffer create FAILED %d", ok);
        return NULL;
    }
    
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    int lumaWidth = buffer.format.lumaWidth;
    int lumaHeight = buffer.format.lumaHeight;
    unsigned char *lumaIn = buffer.Y.data.bytes;
    unsigned char *lumaOut = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
    size_t lumaInStride = buffer.Y.stride;
    size_t lumaOutStride = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
    for (int y = 0; y < lumaHeight; y++) {
        for (int x = 0; x < lumaWidth; x++) {
            lumaOut[x] = lumaIn[x];
        }
        lumaIn += lumaInStride;
        lumaOut += lumaOutStride;
    }
    
    int chromaWidth = buffer.format.chromaWidth;
    int chromaHeight = buffer.format.chromaHeight;
    unsigned char *chromaCbIn = buffer.Cb.data.bytes;
    unsigned char *chromaCrIn = buffer.Cr.data.bytes;
    unsigned char *chromaOut = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1);
    size_t chromaCbInStride = buffer.Cb.stride;
    size_t chromaCrInStride = buffer.Cr.stride;
    size_t chromaOutStride = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1);
    for (int y = 0; y < chromaHeight; y++) {
        for (int x = 0; x < chromaWidth; x++) {
            chromaOut[x * 2] = chromaCbIn[x];
            chromaOut[x * 2 + 1] = chromaCrIn[x];
        }
        chromaCbIn += chromaCbInStride;
        chromaCrIn += chromaCrInStride;
        chromaOut += chromaOutStride;
    }
    
    
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    
    CMVideoFormatDescriptionRef formatDesc;
    ok = CMVideoFormatDescriptionCreateForImageBuffer(NULL, imageBuffer, &formatDesc);
    if (ok != 0) {
        NSLog(@"format desc FAILED %d", ok);
        return NULL;
    }
    
    CMSampleTimingInfo sampleTiming;
    sampleTiming.duration = CMTimeMake((1.0 / 60) * 1000, 1000);
    sampleTiming.presentationTimeStamp = CMTimeMake(buffer.timestamp * 1000, 1000);
    sampleTiming.decodeTimeStamp = kCMTimeInvalid;
    
    CMSampleBufferRef sampleBuffer;
    ok = CMSampleBufferCreateForImageBuffer(NULL, imageBuffer, YES, NULL, NULL, formatDesc, &sampleTiming, &sampleBuffer);
    if (ok != 0) {
        NSLog(@"sample buffer FAILED %d", ok);
        return NULL;
    }
    
    CFRelease(formatDesc);
    CFRelease(imageBuffer);

    CFTimeInterval delta = CFAbsoluteTimeGetCurrent() - start;
    NSLog(@"created CMSampleBuffer in %lf ms", delta * 1000.0);

    return sampleBuffer;
}
@end
