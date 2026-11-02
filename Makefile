include MTARBuild.mk
include $(THEOS)/makefiles/common.mk

TOOL_NAME = memtrim-autorecovery
memtrim-autorecovery_FILES = AutoRecovery/main.m
memtrim-autorecovery_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra
memtrim-autorecovery_FRAMEWORKS = Foundation CoreFoundation
memtrim-autorecovery_LIBRARIES = roothide
memtrim-autorecovery_INSTALL_PATH = /usr/libexec
memtrim-autorecovery_CODESIGN_FLAGS = -Sentitlements.plist

SUBPROJECTS += Prefs

include $(THEOS_MAKE_PATH)/tool.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
