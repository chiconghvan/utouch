include $(THEOS)/makefiles/common.mk

TOOL_NAME = zxtouch-dashboardd

zxtouch-dashboardd_FILES = main.m \
	../zxtouch/zxtouch/RemoteDashboardServer.m \
	../zxtouch/zxtouch/GCDWebServer/Core/GCDWebServerResponse.m \
	../zxtouch/zxtouch/GCDWebServer/Core/GCDWebServerRequest.m \
	../zxtouch/zxtouch/GCDWebServer/Core/GCDWebServerFunctions.m \
	../zxtouch/zxtouch/GCDWebServer/Core/GCDWebServer.m \
	../zxtouch/zxtouch/GCDWebServer/Core/GCDWebServerConnection.m \
	../zxtouch/zxtouch/GCDWebServer/Responses/GCDWebServerErrorResponse.m \
	../zxtouch/zxtouch/GCDWebServer/Responses/GCDWebServerFileResponse.m \
	../zxtouch/zxtouch/GCDWebServer/Responses/GCDWebServerDataResponse.m \
	../zxtouch/zxtouch/GCDWebServer/Responses/GCDWebServerStreamedResponse.m \
	../zxtouch/zxtouch/GCDWebServer/Requests/GCDWebServerURLEncodedFormRequest.m \
	../zxtouch/zxtouch/GCDWebServer/Requests/GCDWebServerMultiPartFormRequest.m \
	../zxtouch/zxtouch/GCDWebServer/Requests/GCDWebServerDataRequest.m \
	../zxtouch/zxtouch/GCDWebServer/Requests/GCDWebServerFileRequest.m
zxtouch-dashboardd_CFLAGS = -Wno-error -Wno-module-import-in-extern-c -fobjc-arc \
	-Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function \
	-Wno-format -Wno-return-type -Wno-incomplete-implementation \
	-Wno-unused-but-set-variable -Wno-macro-redefined -Wno-unicode-whitespace \
	-Wno-block-capture-autoreleasing -Wno-shadow-ivar -Wno-nonnull \
	-Wno-format-extra-args -DZX_DASHBOARD_SPRINGBOARD_SERVER=1 \
	-DZX_DASHBOARD_DAEMON=1 \
	-I../zxtouch/zxtouch \
	-I../zxtouch/zxtouch/GCDWebServer/Core \
	-I../zxtouch/zxtouch/GCDWebServer/Responses \
	-I../zxtouch/zxtouch/GCDWebServer/Requests
zxtouch-dashboardd_FRAMEWORKS = Foundation UIKit
zxtouch-dashboardd_ARCHS = arm64 arm64e
zxtouch-dashboardd_CODESIGN_FLAGS = -Sdashboardd.entitlements

include $(THEOS_MAKE_PATH)/tool.mk
