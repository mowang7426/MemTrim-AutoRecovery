include ../MTARBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = MemTrimAutoRecoveryPrefs
MemTrimAutoRecoveryPrefs_FILES = MTARootListController.m
MemTrimAutoRecoveryPrefs_FRAMEWORKS = UIKit
MemTrimAutoRecoveryPrefs_PRIVATE_FRAMEWORKS = Preferences
MemTrimAutoRecoveryPrefs_LIBRARIES = roothide
MemTrimAutoRecoveryPrefs_INSTALL_PATH = /Library/PreferenceBundles
MemTrimAutoRecoveryPrefs_RESOURCE_DIRS = Resources
MemTrimAutoRecoveryPrefs_CFLAGS = -fobjc-arc -Wall -Wextra

include $(THEOS_MAKE_PATH)/bundle.mk
