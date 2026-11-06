#import <AVFoundation/AVFoundation.h>

// A single serialized renderer preserves each client's pixel format and timing.
@interface VCamFrames : NSObject
+ (instancetype)shared;
- (void)configureMode:(NSInteger)mode path:(NSString *)path zoom:(CGFloat)zoom
                    x:(CGFloat)x y:(CGFloat)y;
- (CMSampleBufferRef)copyReplacementForSample:(CMSampleBufferRef)sample CF_RETURNS_RETAINED;
@end
