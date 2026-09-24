#ifndef ZXPROXYAPPLY_H
#define ZXPROXYAPPLY_H

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Wi-Fi proxy set/clear (TASK_SETPROXY payload: "host;;port" or "clear").
// Runs the SCPreferences commit+apply path from proxyswitcher-ng. MUST run
// as root (SCPreferencesLock needs system-preferences write access), i.e.
// inside zxtouchb via sudo — never in the SpringBoard tweak (mobile).
// Returns @"0\r\n" on success, nil + NSError (message already in the
// "-1;;reason\r\n" client format) on failure. Never throws.
NSString *ZXProxyApplyFromRawData(UInt8 *eventData, NSError **error);

#ifdef __cplusplus
}
#endif

#endif
