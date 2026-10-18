TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := FakeCellular5G
FakeCellular5G_FILES := Tweak.x FactoryLicenseGate.c
FakeCellular5G_FRAMEWORKS := UIKit Foundation CoreFoundation
FakeCellular5G_CFLAGS := -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
