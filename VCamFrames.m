#import "VCamFrames.h"
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface VCamFrames () {
    dispatch_queue_t _queue;
    CIContext *_context;
    NSInteger _mode;
    NSString *_path;
    NSDate *_modified;
    CGFloat _zoom, _x, _y;
    CIImage *_still;
    AVAssetReader *_reader;
    AVAssetReaderTrackOutput *_output;
    AVAsset *_asset;
    AVAssetTrack *_track;
    CMSampleBufferRef _current, _next;
    CMTime _origin;
    double _duration, _lastTarget;
    CVPixelBufferPoolRef _pool;
    size_t _width, _height;
    OSType _format;
    NSUInteger _loggedFrames;
}
@end

@implementation VCamFrames
+ (instancetype)shared {
    static VCamFrames *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [VCamFrames new]; });
    return instance;
}
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.megaduo.vcam.frames", DISPATCH_QUEUE_SERIAL);
        _origin = kCMTimeInvalid;
        _lastTarget = -1;
        _zoom = 1;
    }
    return self;
}
- (void)clearReader {
    [_reader cancelReading];
    _reader = nil;
    _output = nil;
    if (_current) { CFRelease(_current); _current = NULL; }
    if (_next) { CFRelease(_next); _next = NULL; }
}
- (void)configureMode:(NSInteger)mode path:(NSString *)path zoom:(CGFloat)zoom
                    x:(CGFloat)x y:(CGFloat)y {
    NSString *newPath = [path copy] ?: @"";
    // File checks run on the control/UI timer, never once per captured frame.
    NSDate *modified = [[NSFileManager.defaultManager attributesOfItemAtPath:newPath error:nil]
                       objectForKey:NSFileModificationDate];
    dispatch_async(_queue, ^{
        BOOL changed = self->_mode != mode || ![self->_path isEqualToString:newPath] ||
                       !((!self->_modified && !modified) || [self->_modified isEqual:modified]);
        self->_zoom = isfinite(zoom) ? MIN(MAX(zoom, 0.2), 3.0) : 1;
        self->_x = isfinite(x) ? MIN(MAX(x, -0.9), 0.9) : 0;
        self->_y = isfinite(y) ? MIN(MAX(y, -0.9), 0.9) : 0;
        if (!changed) return;
        [self clearReader];
        self->_mode = mode;
        self->_path = newPath;
        self->_modified = modified;
        self->_still = nil;
        self->_asset = nil;
        self->_track = nil;
        self->_origin = kCMTimeInvalid;
        self->_lastTarget = -1;
        self->_loggedFrames = 0;
        NSURL *url = [NSURL fileURLWithPath:newPath];
        if (mode == 2 && modified) {
            self->_still = [CIImage imageWithContentsOfURL:url
                options:@{kCIImageApplyOrientationProperty: @YES}];
        } else if (mode == 1 && modified) {
            self->_asset = [AVURLAsset URLAssetWithURL:url options:nil];
            self->_track = [[self->_asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
            self->_duration = CMTimeGetSeconds(self->_asset.duration);
        }
        NSLog(@"[VCam] frame source mode=%ld readable=%d", (long)mode,
              mode == 2 ? self->_still != nil : self->_track != nil);
    });
}
- (BOOL)startReaderAt:(double)seconds {
    [self clearReader];
    if (!_asset || !_track) return NO;
    NSError *error = nil;
    _reader = [AVAssetReader assetReaderWithAsset:_asset error:&error];
    _output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:_track
        outputSettings:@{(NSString *)kCVPixelBufferPixelFormatTypeKey:
                            @(kCVPixelFormatType_32BGRA)}];
    _output.alwaysCopiesSampleData = NO;
    if (!_reader || ![_reader canAddOutput:_output]) { [self clearReader]; return NO; }
    [_reader addOutput:_output];
    if (seconds > 0 && isfinite(_duration) && _duration > seconds) {
        _reader.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(seconds, 600),
                                          CMTimeMakeWithSeconds(_duration - seconds, 600));
    }
    if (![_reader startReading]) {
        NSLog(@"[VCam] video reader failed: %@", _reader.error ?: error);
        [self clearReader];
        return NO;
    }
    _next = [_output copyNextSampleBuffer];
    return _next != NULL;
}
- (CIImage *)videoImageAt:(CMTime)time {
    if (!_track || !isfinite(_duration) || _duration <= 0) return nil;
    if (!CMTIME_IS_NUMERIC(time)) time = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
    if (!CMTIME_IS_NUMERIC(_origin)) _origin = time;
    double elapsed = CMTimeGetSeconds(CMTimeSubtract(time, _origin));
    if (!isfinite(elapsed) || elapsed < 0) { _origin = time; elapsed = 0; }
    double target = fmod(elapsed, _duration);
    // Seek after a loop or a pause rather than decoding an unbounded backlog.
    if (!_reader || target + 0.001 < _lastTarget || target - _lastTarget > 0.5) {
        if (![self startReaderAt:target]) return nil;
    }
    _lastTarget = target;
    for (NSUInteger count = 0; _next && count < 16; count++) {
        double pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(_next));
        if (_current && isfinite(pts) && pts > target) break;
        if (_current) CFRelease(_current);
        _current = _next;
        _next = [_output copyNextSampleBuffer];
    }
    if (!_current) return nil;
    CVPixelBufferRef pixels = CMSampleBufferGetImageBuffer(_current);
    if (!pixels) return nil;
    return [[CIImage imageWithCVPixelBuffer:pixels] imageByApplyingTransform:_track.preferredTransform];
}
- (CMSampleBufferRef)renderSample:(CMSampleBufferRef)sample CF_RETURNS_RETAINED {
    if (_mode == 0) return NULL;
    CVPixelBufferRef input = CMSampleBufferGetImageBuffer(sample);
    if (!input) return NULL;
    OSType format = CVPixelBufferGetPixelFormatType(input);
    if (format != kCVPixelFormatType_32BGRA &&
        format != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange &&
        format != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) return NULL;
    size_t width = CVPixelBufferGetWidth(input), height = CVPixelBufferGetHeight(input);
    if (!width || !height || width > 4096 || height > 4096) return NULL;
    CIImage *image = _mode == 2 ? _still : [self videoImageAt:CMSampleBufferGetPresentationTimeStamp(sample)];
    CGRect extent = image.extent;
    if (!image || CGRectIsEmpty(extent) || CGRectIsInfinite(extent)) return NULL;
    if (!_pool || _width != width || _height != height || _format != format) {
        if (_pool) { CVPixelBufferPoolRelease(_pool); _pool = NULL; }
        NSDictionary *attrs = @{(NSString *)kCVPixelBufferWidthKey: @(width),
            (NSString *)kCVPixelBufferHeightKey: @(height),
            (NSString *)kCVPixelBufferPixelFormatTypeKey: @(format),
            (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
            (NSString *)kCVPixelBufferMetalCompatibilityKey: @YES};
        if (CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)attrs, &_pool)
            != kCVReturnSuccess) return NULL;
        _width = width; _height = height; _format = format;
    }
    CVPixelBufferRef rendered = NULL;
    NSDictionary *limit = @{(NSString *)kCVPixelBufferPoolAllocationThresholdKey: @6};
    if (CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, _pool,
            (__bridge CFDictionaryRef)limit, &rendered) != kCVReturnSuccess) return NULL;
    CGRect bounds = CGRectMake(0, 0, width, height);
    CGFloat scale = MIN(width / extent.size.width, height / extent.size.height) * _zoom;
    image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x, -extent.origin.y)];
    image = [image imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(
        (width - extent.size.width * scale) / 2 + _x * width,
        (height - extent.size.height * scale) / 2 - _y * height)];
    CIImage *black = [[CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0 alpha:1]]
                     imageByCroppingToRect:bounds];
    image = [[image imageByCompositingOverImage:black] imageByCroppingToRect:bounds];
    if (!_context) _context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    [_context render:image toCVPixelBuffer:rendered bounds:bounds colorSpace:colorSpace];
    CGColorSpaceRelease(colorSpace);
    CFDictionaryRef attachments = CVBufferCopyAttachments(input, kCVAttachmentMode_ShouldPropagate);
    if (attachments) { CVBufferSetAttachments(rendered, attachments, kCVAttachmentMode_ShouldPropagate); CFRelease(attachments); }
    CMVideoFormatDescriptionRef description = NULL;
    CMSampleBufferRef result = NULL;
    CMSampleTimingInfo timing;
    if (CMSampleBufferGetSampleTimingInfo(sample, 0, &timing) != noErr) {
        timing = (CMSampleTimingInfo){CMSampleBufferGetDuration(sample),
                    CMSampleBufferGetPresentationTimeStamp(sample), kCMTimeInvalid};
    }
    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, rendered, &description) == noErr) {
        CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, rendered, description, &timing, &result);
        CFRelease(description);
    }
    CVPixelBufferRelease(rendered);
    if (result) {
        CFDictionaryRef copied = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sample, kCMAttachmentMode_ShouldPropagate);
        if (copied) { CMSetAttachments(result, copied, kCMAttachmentMode_ShouldPropagate); CFRelease(copied); }
        if (_loggedFrames++ == 0) NSLog(@"[VCam] replaced video frame %zux%zu format=%u", width, height, (unsigned)format);
    }
    return result;
}
- (CMSampleBufferRef)copyReplacementForSample:(CMSampleBufferRef)sample {
    if (!sample) return NULL;
    __block CMSampleBufferRef result = NULL;
    dispatch_sync(_queue, ^{ @autoreleasepool { result = [self renderSample:sample]; } });
    return result;
}
- (void)dealloc {
    [self clearReader];
    if (_pool) CVPixelBufferPoolRelease(_pool);
}
@end
