# VCam English — camera app compatibility build

Target: iPhone 14, iOS 16.0.3, ordinary Dopamine rootless.

This revision extends the English Castiel fork with standard preview-layer refresh for camera clients and a retained per-output AVCaptureVideoDataOutput delegate proxy. Rendering preserves the input dimensions, supported pixel format (BGRA / NV12 full or video range), capture timestamps, and propagated attachments. A serial renderer and a bounded pixel-buffer pool protect concurrent capture callbacks; video playback follows capture time and loops.

Third-party apps import their own photo or video through PHPicker into their own Library/Application Support/VCam directory. Open the camera inside the app, tap the floating camera button, and choose Photo or Video. Selected media and state are separate in each app. Desktop selections remain shared with the system Camera only. No new sandbox-extension service is required.

The floating window passes modal picker touches correctly, is shown while the client camera runs, and hides when the app enters the background. The standard preview registry uses weak references. Existing photo and recorded-file hooks remain from the Castiel fork.

WeChat and Today Watermark Camera are test targets, not verified supported applications. Apps using private capture/rendering pipelines may bypass these hooks; device testing is required. This does not change timestamps, location, watermark logic, or microphone audio. Keep only one VCam variant installed.

Based on castielmartinezoj-ui/VCam commit cfc6e8b78bacf6b5c0037a70df07571aa5dd6462; original README and attribution are included. The bank-specific hiding module is excluded. The source has no settings bundle. Build the included workflow on macOS with Apple's toolchain.
