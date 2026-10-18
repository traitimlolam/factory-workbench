TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = FakeCellular5GPrefs
FakeCellular5GPrefs_FILES = RootListController.m
FakeCellular5GPrefs_RESOURCE_FILES = Root.plist
FakeCellular5GPrefs_INSTALL_PATH = /Library/PreferenceBundles
FakeCellular5GPrefs_FRAMEWORKS = UIKit Foundation
FakeCellular5GPrefs_PRIVATE_FRAMEWORKS = Preferences
FakeCellular5GPrefs_CFLAGS = -fobjc-arc

$(THEOS_OBJ_DIR)/FakeCellular5GPrefs.bundle/FakeCellular5GPrefs.plist:
	$(ECHO_NOTHING)install -d $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences; \
	cp FakeCellular5GPrefs.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/FakeCellular5GPrefs.plist$(ECHO_END)

internal-stage:: $(THEOS_OBJ_DIR)/FakeCellular5GPrefs.bundle/FakeCellular5GPrefs.plist
	$(ECHO_NOTHING)install -d $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences; \
	cp FakeCellular5GPrefs.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/FakeCellular5GPrefs.plist$(ECHO_END)

include $(THEOS_MAKE_PATH)/bundle.mk
