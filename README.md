# VCam English for ordinary Dopamine rootless

Target: iPhone 14, iOS 16.0.3, ordinary Dopamine rootless. Device testing is required.

Based on castielmartinezoj-ui/VCam, commit cfc6e8b78bacf6b5c0037a70df07571aa5dd6462.
Upstream repository: https://github.com/castielmartinezoj-ui/VCam
The upstream README states MIT licensing. Original contributors retain attribution; its README is included as README-upstream.md.

Changes: English controls and runtime logs; standard rootless paths and package architecture; ordinary ElleKit dependency; safe installation scripts; explicit QuartzCore and PhotosUI framework linkage. The unrelated bank-specific jailbreak-hiding module is excluded from this camera build. The settings subproject remains disabled.

Use the draggable camera button on SpringBoard to open the panel. Choose Photo from Library, adjust Zoom / Horizontal / Vertical, then Apply Image to Camera. Local video is read from /var/mobile/Media/Downloads/vcam_video.mp4. The upstream custom stream listens on localhost port 9876 and requires a compatible frame sender and forwarding arrangement.

This build retains upstream camera hooks. Preview, photo and recorded-file behavior require device testing; it does not guarantee all-app live frame substitution or microphone replacement. Only install one VCam variant at a time.

For an Apple-toolchain build, run the included GitHub Actions workflow on macos-15-intel. It checks rootless payload paths, Debian architecture and the arm64e ABI before uploading the deb.
