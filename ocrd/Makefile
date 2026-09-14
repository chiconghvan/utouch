include $(THEOS)/makefiles/common.mk

TOOL_NAME = zxtouch-ocrd
zxtouch-ocrd_FILES = main.mm
zxtouch-ocrd_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-parameter
zxtouch-ocrd_CCFLAGS = -std=c++17
zxtouch-ocrd_FRAMEWORKS = Foundation UIKit Vision IOSurface QuartzCore CoreImage
zxtouch-ocrd_ARCHS = arm64 arm64e
zxtouch-ocrd_CODESIGN_FLAGS = -Socrd.entitlements

include $(THEOS_MAKE_PATH)/tool.mk
