TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
include $(THEOS)/makefiles/common.mk

TWEAK_NAME := ConfirmRotate
ConfirmRotate_FILES := Tweak.x FactoryLicenseGate.c
ConfirmRotate_FRAMEWORKS := UIKit Foundation CoreFoundation CoreGraphics QuartzCore AudioToolbox CoreMotion
ConfirmRotate_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
