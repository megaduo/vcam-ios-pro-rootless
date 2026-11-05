# VCam for ordinary Dopamine rootless

Target: iPhone 14, iOS 16.0.3, ordinary Dopamine rootless.

This source is derived from https://github.com/mdmvenezuela/vcam-ios-pro (main, ddac86e8303b731275c711e9479c738ca127e5ca). The upstream README states MIT licensing; upstream authors retain attribution.

Changes:

- Standard Theos rootless build; package architecture iphoneos-arm64.
- Universal arm64 plus current iOS arm64e ABI, built using Apple's macOS toolchain.
- Installation scripts use /var/jb and do not restart SpringBoard during package transactions.
- Correct Objective-C gesture action calling conventions.
- Attach the floating window to an active UIWindowScene and let touches outside the button reach the app.
- Replace the NSObject-wide callback hook with a capture-output delegate proxy.
- Serialize video-reader access, preserve input capture timestamps and clear stale readers when reloading media.

Build with the included GitHub Actions workflow. Its artifact is named VCam-Dopamine-rootless. The workflow rejects packages with the wrong Debian architecture, missing /var/jb payload, or an incompatible arm64e slice.

Install the resulting deb using your rootless package manager, respring, and reopen the target app. Select a video from that app's floating camera menu. Selection and enabled state are local to that app process.

Limitations: device testing is required. This implementation substitutes AVCaptureVideoDataOutput delegate frames; it does not implement camera preview, still-photo, or microphone replacement. The settings subproject remains disabled as in upstream. The existing album picker depends on the host app's photo-library permissions and privacy configuration. Do not assume every camera app is supported.
