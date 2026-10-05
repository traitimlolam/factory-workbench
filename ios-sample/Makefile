TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
include $(THEOS)/makefiles/common.mk

TWEAK_NAME := FactorySample
FactorySample_FILES := Tweak.xm Feature.xm FactoryLicenseGate.c
FactorySample_FRAMEWORKS := UIKit Foundation
FactorySample_CFLAGS := -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
