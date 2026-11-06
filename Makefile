THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCam
VCam_FILES = Tweak.xm MediaManager.m VCamFrames.m
VCam_CFLAGS = -fobjc-arc
VCam_CXXFLAGS = -fobjc-arc -std=c++17 -fno-modules
VCam_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo CoreImage QuartzCore MobileCoreServices PhotosUI

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += controls
include $(THEOS_MAKE_PATH)/aggregate.mk
