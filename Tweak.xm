#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <substrate.h>
#import <objc/runtime.h>
#import "MediaManager.h"

// ============================================================================
// MARK: - 全局状态
// ============================================================================

static BOOL g_vcamEnabled = NO;
static UIWindow *g_overlayWindow = nil;
static UIButton *g_floatButton = nil;
// ============================================================================
// MARK: - 悬浮按钮 UI
// ============================================================================

@interface VCamOverlayWindow : UIWindow
@end
@implementation VCamOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end

@interface VCamFloatButton : UIButton
@property (nonatomic, assign) CGPoint initialCenter;
@end

@implementation VCamFloatButton
@end

static void setupFloatButton(void);
static void handlePanGesture(UIPanGestureRecognizer *gesture);
static void handleTapGesture(UITapGestureRecognizer *gesture);
// Objective-C IMPs receive self and _cmd before the gesture argument.
static void handlePanAction(id receiver, SEL selector, UIPanGestureRecognizer *gesture) {
    handlePanGesture(gesture);
}
static void handleTapAction(id receiver, SEL selector, UITapGestureRecognizer *gesture) {
    handleTapGesture(gesture);
}
static void setupFloatButton() {
    if (g_floatButton) return;
    UIWindowScene *activeScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            activeScene = (UIWindowScene *)scene;
            break;
        }
    }
    if (!activeScene) return;

    CGFloat btnSize = 50;
    CGRect screen = [UIScreen mainScreen].bounds;

    g_floatButton = [VCamFloatButton buttonWithType:UIButtonTypeSystem];
    g_floatButton.frame = CGRectMake(screen.size.width - btnSize - 15, 100, btnSize, btnSize);
    g_floatButton.layer.cornerRadius = btnSize / 2.0;
    g_floatButton.layer.shadowColor = [UIColor blackColor].CGColor;
    g_floatButton.layer.shadowOffset = CGSizeMake(0, 2);
    g_floatButton.layer.shadowOpacity = 0.3;
    g_floatButton.layer.shadowRadius = 4;
    g_floatButton.backgroundColor = g_vcamEnabled
        ? [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9]
        : [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:0.9];

    [g_floatButton setTitle:@"📷" forState:UIControlStateNormal];
    g_floatButton.titleLabel.font = [UIFont systemFontOfSize:24];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:g_floatButton action:@selector(handlePan:)];
    [g_floatButton addGestureRecognizer:pan];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:g_floatButton action:@selector(handleTap:)];
    [g_floatButton addGestureRecognizer:tap];

    g_overlayWindow = [[VCamOverlayWindow alloc] initWithWindowScene:activeScene];
    g_overlayWindow.frame = screen;
    g_overlayWindow.windowLevel = UIWindowLevelAlert + 100;
    g_overlayWindow.hidden = NO;
    g_overlayWindow.backgroundColor = [UIColor clearColor];

    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    [rootVC.view addSubview:g_floatButton];
    g_overlayWindow.rootViewController = rootVC;

    // Register selectors on the button class
    class_addMethod([g_floatButton class], @selector(handlePan:),
                    (IMP)handlePanAction, "v@:@");
    class_addMethod([g_floatButton class], @selector(handleTap:),
                    (IMP)handleTapAction, "v@:@");
}
static void handlePanGesture(UIPanGestureRecognizer *gesture) {
    UIView *btn = gesture.view;
    CGPoint translation = [gesture translationInView:btn.superview];
    btn.center = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:btn.superview];

    if (gesture.state == UIGestureRecognizerStateEnded) {
        CGRect screen = [UIScreen mainScreen].bounds;
        CGFloat x = btn.center.x < screen.size.width / 2 ? 35 : screen.size.width - 35;
        [UIView animateWithDuration:0.2 animations:^{
            btn.center = CGPointMake(x, btn.center.y);
        }];
    }
}
static UIViewController *findTopViewController(void) {
    UIViewController *topVC = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *w in scene.windows) {
                if (w.isKeyWindow) {
                    topVC = w.rootViewController;
                    break;
                }
            }
        }
    }
    while (topVC && topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}
@interface VCamImagePickerControllerDelegate : NSObject <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@end

@implementation VCamImagePickerControllerDelegate
- (void)imagePickerController:(UIImagePickerController *)picker
        didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];

    NSURL *url = info[UIImagePickerControllerMediaURL];
    if (!url) return;

    NSURL *tempURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
        stringByAppendingPathComponent:@"vcam_input.mp4"]];
    [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    NSError *copyError = nil;
    if (![[NSFileManager defaultManager] copyItemAtURL:url toURL:tempURL error:&copyError]) {
        NSLog(@"[VCam] Could not import video: %@", copyError);
        return;
    }

    [[MediaManager sharedManager] loadMediaFromURL:tempURL];
    g_vcamEnabled = YES;
    [[MediaManager sharedManager] start];
    if (g_floatButton) {
        g_floatButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9];
    }
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end

static VCamImagePickerControllerDelegate *g_pickerDelegate = nil;
static void handleTapGesture(UITapGestureRecognizer *gesture) {
    UIViewController *topVC = findTopViewController();
    if (!topVC) return;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"VCam"
        message:g_vcamEnabled ? @"虚拟相机已启用" : @"虚拟相机已关闭"
        preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"选择视频"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum]) {
            return;
        }
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypeSavedPhotosAlbum;
        picker.mediaTypes = @[@"public.movie"];
        picker.delegate = g_pickerDelegate;
        [topVC presentViewController:picker animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:g_vcamEnabled ? @"关闭虚拟相机" : @"开启虚拟相机"
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        g_vcamEnabled = !g_vcamEnabled;
        if (g_floatButton) {
            g_floatButton.backgroundColor = g_vcamEnabled
                ? [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9]
                : [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:0.9];
        }
        if (g_vcamEnabled) {
            [[MediaManager sharedManager] start];
        } else {
            [[MediaManager sharedManager] stop];
        }
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = gesture.view;
        alert.popoverPresentationController.sourceRect = gesture.view.bounds;
    }
    [topVC presentViewController:alert animated:YES completion:nil];
}
// ============================================================================
// MARK: - Hook AVCaptureSession / Video Output
// ============================================================================

// Keep each capture output's delegate alive through a separate proxy.
// Hooking NSObject cannot intercept methods overridden by concrete app delegates.
@interface VCamCaptureDelegateProxy : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak) id<AVCaptureVideoDataOutputSampleBufferDelegate> target;
@end
@implementation VCamCaptureDelegateProxy
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.target respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector {
    id target = self.target;
    return [target respondsToSelector:selector] ? target : [super forwardingTargetForSelector:selector];
}
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
    fromConnection:(AVCaptureConnection *)connection {
    id<AVCaptureVideoDataOutputSampleBufferDelegate> target = self.target;
    if (![target respondsToSelector:_cmd]) return;
    CMSampleBufferRef fake = NULL;
    if (g_vcamEnabled && MediaManager.sharedManager.isRunning) {
        fake = [MediaManager.sharedManager nextVideoFrame];
    }
    CMSampleBufferRef retimed = NULL;
    if (fake) {
        CMSampleTimingInfo timing = {
            CMSampleBufferGetDuration(sampleBuffer),
            CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            kCMTimeInvalid
        };
        CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault, fake, 1, &timing, &retimed);
    }
    [target captureOutput:output didOutputSampleBuffer:(retimed ?: (fake ?: sampleBuffer))
           fromConnection:connection];
    if (retimed) CFRelease(retimed);
    if (fake) CFRelease(fake);
}
@end
static char kVCamDelegateProxyKey;

%group VCamHooks

%hook AVCaptureSession
- (void)startRunning { %orig; }
- (void)stopRunning { %orig; }
%end
%hook AVCaptureVideoDataOutput
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                          queue:(dispatch_queue_t)queue {
    if (!delegate) {
        %orig(nil, queue);
        objc_setAssociatedObject(self, &kVCamDelegateProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if ([(id)delegate isKindOfClass:[VCamCaptureDelegateProxy class]]) {
        %orig(delegate, queue);
        return;
    }
    VCamCaptureDelegateProxy *proxy = [[VCamCaptureDelegateProxy alloc] init];
    proxy.target = delegate;
    objc_setAssociatedObject(self, &kVCamDelegateProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(proxy, queue);
}
%end
%hook AVCapturePhotoOutput
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings
                        delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    %orig;
}
%end

%hook AVCaptureVideoPreviewLayer
- (void)setSession:(AVCaptureSession *)session {
    %orig;
}
%end

%end // VCamHooks group

// ============================================================================
// MARK: - Constructor
// ============================================================================
%ctor {
    @autoreleasepool {
        g_pickerDelegate = [[VCamImagePickerControllerDelegate alloc] init];

        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:@"com.apple.springboard"]) {
            %init(VCamHooks);
        }

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                setupFloatButton();
            }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                @autoreleasepool {
                    setupFloatButton();
                }
            });
    }
}

