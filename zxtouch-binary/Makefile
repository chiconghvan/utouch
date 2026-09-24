include $(THEOS)/makefiles/common.mk

TOOL_NAME = zxtouchb
zxtouchb_ARCHS = arm64 arm64e

zxtouchb_FILES = main.mm ../pccontrol/ZXProxyApply.m
zxtouchb_CFLAGS = -fobjc-arc -Wno-error -Wno-module-import-in-extern-c -O2 -DNDEBUG \
	-Wno-unused-variable -Wno-return-type
zxtouchb_FRAMEWORKS = Foundation
zxtouchb_CODESIGN_FLAGS = -Szxtouchb.entitlements

include $(THEOS_MAKE_PATH)/tool.mk
