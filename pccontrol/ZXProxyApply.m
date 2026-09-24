#import "ZXProxyApply.h"
#import <Foundation/Foundation.h>
#include <dlfcn.h>

// Opaque SystemConfiguration type, forward-declared so this file needs
// neither the framework import (its headers are API_UNAVAILABLE(ios) in
// the SDK) nor a link against it: every symbol is resolved at runtime
// with dlopen/dlsym, exactly like the Settings app path this mirrors.
typedef const struct __SCPreferences *ZXSCPreferencesRef;

static NSString *ZXPAError(NSString *msg) {
    return [NSString stringWithFormat:@"-1;;%@\r\n", msg];
}

static NSArray *ZXPASplit(UInt8 *eventData) {
    NSString *s = [NSString stringWithUTF8String:(char *)eventData] ?: @"";
    return [s componentsSeparatedByString:@";;"];
}

// SystemConfiguration's SCPreferences symbols are API_UNAVAILABLE(ios) in the
// SDK (compile-time only — they exist on-device). dlsym on a CFStringRef
// global returns the address of the variable, hence the extra indirection.
static CFStringRef ZXPASCConst(void *handle, const char *sym) {
    void *addr = handle ? dlsym(handle, sym) : NULL;
    return addr ? *(CFStringRef *)addr : NULL;
}

NSString *ZXProxyApplyFromRawData(UInt8 *eventData, NSError **error) {
    // Payload: "host;;port" to set, "clear" to remove. Mirrors what Settings
    // writes: the proxy lives in the Wi-Fi network SERVICE's Proxies dict,
    // committed + applied through SCPreferences so configd picks it up live
    // (no interface bounce needed). Writing the Global dict instead — the
    // old Python fallback — is ignored for Wi-Fi traffic on iOS.
    //
    // The SCPreferences C API and its schema constants are marked
    // API_UNAVAILABLE(ios) in the SDK, so everything is resolved at runtime
    // (dlopen/dlsym); a missing symbol means the OS moved the API and is
    // reported instead of a false success.
    NSArray *parts = ZXPASplit(eventData);
    NSString *first = [parts count] > 0 ? [parts objectAtIndex:0] : @"";
    BOOL clear = [first isEqualToString:@"clear"];
    NSString *host = clear ? nil : first;
    int port = (int)([parts count] > 1 ? [[parts objectAtIndex:1] intValue] : 0);
    if (!clear && (host.length == 0 || port <= 0 || port > 65535)) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXPAError(@"Proxy format: host;;port (1-65535), or clear.")}];
        return nil;
    }

    typedef ZXSCPreferencesRef (*ZXSCPrefsCreateFn)(CFAllocatorRef, CFStringRef, CFStringRef);
    typedef Boolean (*ZXSCPrefsLockFn)(ZXSCPreferencesRef, Boolean);
    typedef Boolean (*ZXSCPrefsUnlockFn)(ZXSCPreferencesRef);
    typedef CFPropertyListRef (*ZXSCPrefsGetValueFn)(ZXSCPreferencesRef, CFStringRef);
    typedef CFPropertyListRef (*ZXSCPrefsPathGetValueFn)(ZXSCPreferencesRef, CFStringRef);
    typedef Boolean (*ZXSCPrefsSetValueFn)(ZXSCPreferencesRef, CFStringRef, CFPropertyListRef);
    typedef Boolean (*ZXSCPrefsCommitFn)(ZXSCPreferencesRef);
    typedef Boolean (*ZXSCPrefsApplyFn)(ZXSCPreferencesRef);
    typedef int (*ZXSCErrorFn)(void);

    void *sc = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_LAZY);
    ZXSCPrefsCreateFn pCreate = sc ? (ZXSCPrefsCreateFn)dlsym(sc, "SCPreferencesCreate") : NULL;
    ZXSCPrefsLockFn pLock = sc ? (ZXSCPrefsLockFn)dlsym(sc, "SCPreferencesLock") : NULL;
    ZXSCPrefsUnlockFn pUnlock = sc ? (ZXSCPrefsUnlockFn)dlsym(sc, "SCPreferencesUnlock") : NULL;
    ZXSCPrefsGetValueFn pGetValue = sc ? (ZXSCPrefsGetValueFn)dlsym(sc, "SCPreferencesGetValue") : NULL;
    ZXSCPrefsPathGetValueFn pPathGetValue = sc ? (ZXSCPrefsPathGetValueFn)dlsym(sc, "SCPreferencesPathGetValue") : NULL;
    ZXSCPrefsSetValueFn pSetValue = sc ? (ZXSCPrefsSetValueFn)dlsym(sc, "SCPreferencesSetValue") : NULL;
    ZXSCPrefsCommitFn pCommit = sc ? (ZXSCPrefsCommitFn)dlsym(sc, "SCPreferencesCommitChanges") : NULL;
    ZXSCPrefsApplyFn pApply = sc ? (ZXSCPrefsApplyFn)dlsym(sc, "SCPreferencesApplyChanges") : NULL;
    ZXSCErrorFn pError = sc ? (ZXSCErrorFn)dlsym(sc, "SCError") : NULL;
    CFStringRef kCurSet = ZXPASCConst(sc, "kSCPrefCurrentSet");
    CFStringRef kNetServices = ZXPASCConst(sc, "kSCPrefNetworkServices");
    CFStringRef kCompNetwork = ZXPASCConst(sc, "kSCCompNetwork");
    CFStringRef kCompService = ZXPASCConst(sc, "kSCCompService");
    CFStringRef kUserName = ZXPASCConst(sc, "kSCPropUserDefinedName");
    CFStringRef kProxies = ZXPASCConst(sc, "kSCEntNetProxies");
    CFStringRef kHTTPEnable = ZXPASCConst(sc, "kSCPropNetProxiesHTTPEnable");
    CFStringRef kHTTPProxy = ZXPASCConst(sc, "kSCPropNetProxiesHTTPProxy");
    CFStringRef kHTTPPort = ZXPASCConst(sc, "kSCPropNetProxiesHTTPPort");
    CFStringRef kHTTPSEnable = ZXPASCConst(sc, "kSCPropNetProxiesHTTPSEnable");
    CFStringRef kHTTPSProxy = ZXPASCConst(sc, "kSCPropNetProxiesHTTPSProxy");
    CFStringRef kHTTPSPort = ZXPASCConst(sc, "kSCPropNetProxiesHTTPSPort");
    CFStringRef kSOCKSEnable = ZXPASCConst(sc, "kSCPropNetProxiesSOCKSEnable");
    CFStringRef kSOCKSProxy = ZXPASCConst(sc, "kSCPropNetProxiesSOCKSProxy");
    CFStringRef kSOCKSPort = ZXPASCConst(sc, "kSCPropNetProxiesSOCKSPort");
    if (!pCreate || !pLock || !pUnlock || !pGetValue || !pPathGetValue ||
        !pSetValue || !pCommit || !pApply || !pError ||
        !kCurSet || !kNetServices || !kCompNetwork || !kCompService ||
        !kUserName || !kProxies || !kHTTPEnable || !kHTTPProxy || !kHTTPPort ||
        !kHTTPSEnable || !kHTTPSProxy || !kHTTPSPort || !kSOCKSEnable ||
        !kSOCKSProxy || !kSOCKSPort) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXPAError(@"Proxy API unavailable on this iOS (SystemConfiguration symbols missing).")}];
        return nil;
    }

    ZXSCPreferencesRef prefs = pCreate(NULL, CFSTR("zxtouch-proxy"), NULL);
    if (!prefs) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXPAError(@"Could not open system preferences.")}];
        return nil;
    }
    NSString *fail = nil;
    @try {
        if (!pLock(prefs, true)) fail = @"Could not lock system preferences.";
        NSDictionary *currentSet = nil;
        NSDictionary *services = nil;
        if (!fail) {
            CFStringRef curSetPath = (CFStringRef)pGetValue(prefs, kCurSet);
            currentSet = (__bridge NSDictionary *)pPathGetValue(prefs, curSetPath);
            services = (__bridge NSDictionary *)pGetValue(prefs, kNetServices);
            if (!currentSet || !services) fail = @"No current network set.";
        }
        NSMutableDictionary *nservices = nil;
        NSString *wifiKey = nil;
        if (!fail) {
            nservices = CFBridgingRelease(CFPropertyListCreateDeepCopy(
                NULL, (__bridge CFPropertyListRef)services,
                kCFPropertyListMutableContainersAndLeaves));
            NSDictionary *setServices = currentSet[(__bridge NSString *)kCompNetwork][(__bridge NSString *)kCompService];
            // Port of proxyswitcher-ng (PSNWiFiProxyHandler): a Wi-Fi service
            // is identified by its Interface (Hardware=AirPort or
            // Type=IEEE80211), not by UserDefinedName. The name is localised
            // and user-renamable, so matching "Wi-Fi" misses real devices.
            for (NSString *key in setServices) {
                NSDictionary *svc = services[key];
                NSDictionary *iface = svc ? svc[@"Interface"] : nil;
                if ([@"AirPort" isEqualToString:iface[@"Hardware"]] ||
                    [@"IEEE80211" isEqualToString:iface[@"Type"]]) {
                    wifiKey = key;
                    break;
                }
            }
            if (!wifiKey) {
                // Legacy fallback for prefs fixtures / older configs without
                // an Interface dict.
                for (NSString *key in setServices) {
                    NSDictionary *svc = services[key];
                    if (svc && [@"Wi-Fi" isEqualToString:svc[(__bridge NSString *)kUserName]]) {
                        wifiKey = key;
                        break;
                    }
                }
            }
            if (!wifiKey) fail = @"No Wi-Fi service in the current set.";
        }
        if (!fail) {
            NSMutableDictionary *proxies = nservices[wifiKey][(__bridge NSString *)kProxies];
            if (!proxies) {
                proxies = [NSMutableDictionary dictionary];
                nservices[wifiKey][(__bridge NSString *)kProxies] = proxies;
            }
            // Idempotent apply (proxyswitcher-ng shouldChangeProxyDict):
            // skip the commit+apply round-trip when the live state already
            // matches. Type-strict so a stale string port (older builds
            // wrote strings the stack ignores) forces a clean rewrite
            // instead of crashing on -isEqualToNumber:.
            NSString *sHTTPEnable = (__bridge NSString *)kHTTPEnable;
            NSString *sHTTPProxy = (__bridge NSString *)kHTTPProxy;
            NSString *sHTTPPort = (__bridge NSString *)kHTTPPort;
            NSString *sHTTPSEnable = (__bridge NSString *)kHTTPSEnable;
            NSString *sHTTPSProxy = (__bridge NSString *)kHTTPSProxy;
            NSString *sHTTPSPort = (__bridge NSString *)kHTTPSPort;
            NSString *sSOCKSProxy = (__bridge NSString *)kSOCKSProxy;
            BOOL alreadyApplied = NO;
            if (clear) {
                alreadyApplied = (proxies.count == 0);
            } else {
                id v;
                v = proxies[sHTTPEnable];
                BOOL httpOk = [v isKindOfClass:[NSNumber class]] && [(NSNumber *)v isEqualToNumber:@1];
                v = proxies[sHTTPProxy];
                httpOk = httpOk && [v isKindOfClass:[NSString class]] && [(NSString *)v isEqualToString:host];
                v = proxies[sHTTPPort];
                httpOk = httpOk && [v isKindOfClass:[NSNumber class]] && [(NSNumber *)v isEqualToNumber:@(port)];
                v = proxies[sHTTPSEnable];
                httpOk = httpOk && [v isKindOfClass:[NSNumber class]] && [(NSNumber *)v isEqualToNumber:@1];
                v = proxies[sHTTPSProxy];
                httpOk = httpOk && [v isKindOfClass:[NSString class]] && [(NSString *)v isEqualToString:host];
                v = proxies[sHTTPSPort];
                httpOk = httpOk && [v isKindOfClass:[NSNumber class]] && [(NSNumber *)v isEqualToNumber:@(port)];
                alreadyApplied = httpOk && (proxies[sSOCKSProxy] == nil);
            }
            if (alreadyApplied) {
                // Nothing to stage: unlock and report success.
            } else if (clear) {
                [proxies removeAllObjects];
                if (!pSetValue(prefs, kNetServices, (__bridge CFPropertyListRef)nservices)) fail = @"Could not stage proxy change.";
                else if (!pCommit(prefs)) fail = [NSString stringWithFormat:@"Commit failed: %d.", pError()];
                else if (!pApply(prefs)) fail = [NSString stringWithFormat:@"Apply failed: %d.", pError()];
            } else {
                proxies[sHTTPEnable] = @1;
                proxies[sHTTPProxy] = host;
                proxies[sHTTPPort] = @(port);
                proxies[sHTTPSEnable] = @1;
                proxies[sHTTPSProxy] = host;
                proxies[sHTTPSPort] = @(port);
                // HTTP mode must not coexist with SOCKS keys: drop them
                // entirely instead of leaving a stale proxy behind with
                // SOCKSEnable=0.
                [proxies removeObjectForKey:(__bridge NSString *)kSOCKSEnable];
                [proxies removeObjectForKey:sSOCKSProxy];
                [proxies removeObjectForKey:(__bridge NSString *)kSOCKSPort];
                if (!pSetValue(prefs, kNetServices, (__bridge CFPropertyListRef)nservices)) fail = @"Could not stage proxy change.";
                else if (!pCommit(prefs)) fail = [NSString stringWithFormat:@"Commit failed: %d.", pError()];
                else if (!pApply(prefs)) fail = [NSString stringWithFormat:@"Apply failed: %d.", pError()];
            }
        }
    } @catch (NSException *e) {
        fail = [@"Proxy change failed: " stringByAppendingString:e.reason ?: @"unknown"];
    }
    pUnlock(prefs);
    CFRelease(prefs);
    if (fail) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXPAError(fail)}];
        return nil;
    }
    return @"0\r\n";
}
