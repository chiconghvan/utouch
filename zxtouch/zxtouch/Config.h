//
//  Config.h
//  zxtouch
//
//  Created by Jason on 2021/1/16.
//

#ifndef Config_h
#define Config_h

#define SCRIPTS_PATH @"/var/mobile/Library/ZXTouch/scripts/"
#define RUNTIME_OUTPUT_PATH @"/var/mobile/Library/ZXTouch/coreutils/ScriptRuntime/output"

// Dashboard crash/disconnect diagnostics. Written by the server code itself
// (not by launchd) so the SpringBoard-hosted fallback server can log too.
#define ZX_DASHBOARD_DEBUG_LOG_PATH @"/var/mobile/Library/ZXTouch/dashboard-debug.log"

// Daemon logs owned by launchd: the dashboard LaunchDaemon redirects its
// stdout/stderr to dashboardd.log and TrollVNC's to trollvnc.log. The server
// only reads them, and serves them through GET /api/logs/download.
#define ZX_DASHBOARDD_LOG_PATH @"/var/mobile/Library/ZXTouch/dashboardd.log"
#define ZX_TROLLVNC_LOG_PATH @"/var/mobile/Library/ZXTouch/trollvnc.log"

#define SPRINGBOARD_CONFIG_PATH @"/var/mobile/Library/ZXTouch/config/tweak/config.plist"

#define SCRIPT_PLAY_CONFIG_PATH @"/var/mobile/Library/ZXTouch/config/tweak/script_play_settings.plist"

#define TOUCH_INDICATOR_DEFAULT_ALPHA 0.7

// Script editor appearance. Stored in the SpringBoard config so the app and
// the dashboard read one value; the editor clamps to this range.
#define ZX_EDITOR_FONT_SIZE_KEY @"editor_font_size"
#define ZX_EDITOR_FONT_SIZE_DEFAULT 14.0
#define ZX_EDITOR_FONT_SIZE_MIN 10.0
#define ZX_EDITOR_FONT_SIZE_MAX 28.0
#define ZX_EDITOR_FONT_SIZE_CHANGED_NOTIFICATION @"ZXEditorFontSizeChangedNotification"

// One indent level in the script editors. Monaco is configured with the same
// width (tabSize in dashboard index.html), so both editors indent alike.
#define ZX_EDITOR_INDENT_WIDTH 2

// Activator is not used in this rootless build; define path to avoid compile errors
#define ACTIVATOR_CONFIG_PATH @"/var/mobile/Library/ZXTouch/config/tweak/activator_config.plist"

#endif /* Config_h */
