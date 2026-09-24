#ifndef EXT_TASKS_H
#define EXT_TASKS_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Phase 2 (IOSControl parity). Payloads use the existing ";;" protocol.
// JSON-bearing payloads are base64-encoded to avoid delimiter collisions.

// 30: "name[;;x,y,w,h]" -> "0;;<fullpath>"
NSString *screenshotFromRawData(UInt8 *eventData, NSError **error);

// 31: base64({"title":..., "options":[...]}) -> "0;;<index>"
NSString *dialogChoiceFromRawData(UInt8 *eventData, NSError **error);

// 32: "show;;base64json" | "update;;key;;value" | "hide" -> "0..."
NSString *overlayFromRawData(UInt8 *eventData, NSError **error);

// 33/34/35/36: app management
NSString *appKillFromRawData(UInt8 *eventData, NSError **error);   // "bundleId" -> "0"
NSString *appStateFromRawData(UInt8 *eventData, NSError **error);  // "bundleId" -> "0;;0|1|2" (not running|running|frontmost)
NSString *openURLFromRawData(UInt8 *eventData, NSError **error);   // "url" -> "0"
NSString *appClearFromRawData(UInt8 *eventData, NSError **error);  // "bundleId" -> "0;;<cleared dirs>"
// NOTE: appClear removes Caches/tmp/WebKit/SplashBoard only and keeps
// Preferences/Keychain/Cookies (safe clear, clearData-style). It does NOT
// wipe login data.

// 37: "name" (home|volumeUp|volumeDown|power) + "down|up" -> "0" (fire-and-forget)
NSString *keyPressFromRawData(UInt8 *eventData, NSError **error);

// 38: "" -> "0"
NSString *vibrateFromRawData(UInt8 *eventData, NSError **error);

// 39: "rrggbb;;tolerance;;count;;x,y,w,h;;skip" -> "0;;x1,y1;;x2,y2..."
NSString *colorMultiFromRawData(UInt8 *eventData, NSError **error);

// 40: base64([{"c":"rrggbb","dx":0,"dy":0},...]) + ";;tolerance;;x,y,w,h" -> "0;;x;;y"
NSString *colorPatternFromRawData(UInt8 *eventData, NSError **error);

// 41: "template;;threshold;;x,y,w,h[;;maxTry;;scale]" -> "0;;x;;y;;w;;h"
NSString *imageRegionFromRawData(UInt8 *eventData, NSError **error);

// 45: "template;;threshold[;;max]" -> "0;;x1,y1,w1,h1;;x2,y2,w2,h2..."
NSString *imageMultiFromRawData(UInt8 *eventData, NSError **error);

// 42/43/44: record event table (base64 JSON array) / file save / load
// 42 in: base64([...]) -> "0;;<played>"
// 43 in: "name;;base64([...])" -> "0"
// 44 in: "name" -> "0;;base64([...])"
NSString *recordPlayEventsFromRawData(UInt8 *eventData, NSError **error);
NSString *recordSaveFromRawData(UInt8 *eventData, NSError **error);
NSString *recordLoadFromRawData(UInt8 *eventData, NSError **error);

// 46: "" -> "0;;ok;;<version>"
NSString *pingFromRawData(UInt8 *eventData, NSError **error);

// 51: "0|1[;;delaySecs]" -> "0". Flips the cellular-data master switch via
// CoreTelephony (CTCellularDataPlanSetIsEnabled, resolved with dlsym so old
// iOS without the symbol still loads). When delaySecs > 0 the opposite state
// is re-applied on a daemon-side timer and the reply is still immediate.
NSString *cellularDataFromRawData(UInt8 *eventData, NSError **error);

// 52: "0|1[;;delaySecs]" -> "0". Flips airplane mode via AppSupport's
// RadiosPreferences (setAirplaneMode: + synchronize, class looked up at
// runtime so the tweak loads everywhere). The value is read back and a
// mismatch is reported as an error. delaySecs restores the opposite state
// on a daemon-side timer; the reply is still immediate.
NSString *airplaneModeFromRawData(UInt8 *eventData, NSError **error);

// 53: "host;;port" -> "0" (set), "clear" -> "0" (remove). Writes the proxy
// into the Wi-Fi network SERVICE's Proxies dict via SCPreferences
// (commit + apply so configd picks it up live). Global proxy keys are
// intentionally not used: iOS applies per-service proxies for Wi-Fi.
NSString *proxyFromRawData(UInt8 *eventData, NSError **error);

// Private SpringBoard class (forward declaration so the Logos %c lookup
// compiles cleanly; the call itself is respondsToSelector-guarded).
// NOTE: SBApplication already comes from Common.h — do not redeclare it.
// process/pid are read via KVC (valueForKey:) so no extra selectors needed.
@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (id)applicationWithBundleIdentifier:(NSString *)bundleId;
@end

#endif
