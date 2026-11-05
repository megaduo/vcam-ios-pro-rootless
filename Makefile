THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCam
VCam_FILES = Tweak.xm MediaManager.m
VCam_CFLAGS = -fobjc-arc
VCam_CXXFLAGS = -fobjc-arc -std=c++17
VCam_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo CoreImage QuartzCore MobileCoreServices

include $(THEOS_MAKE_PATH)/tweak.mk
