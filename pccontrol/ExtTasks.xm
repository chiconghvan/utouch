#include "ExtTasks.h"
#include "Screen.h"
#include "ColorPicker.h"
#include "TemplateMatch.h"
#include "Process.h"
#include "Common.h"
#include "SocketServer.h"
#include "Touch.h"
#include <dlfcn.h>
#import <AudioToolbox/AudioToolbox.h>
#import <UIKit/UIKit.h>
#import <SystemConfiguration/SystemConfiguration.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wavailability"
#pragma clang diagnostic ignored "-Wattributes"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include "headers/IOHIDEvent.h"
#include "headers/IOHIDEventSystemClient.h"
#pragma clang diagnostic pop

// ---------------------------------------------------------------- helpers

static NSString *ZXExtError(NSString *msg) {
    return [NSString stringWithFormat:@"-1;;%@\r\n", msg];
}

static NSArray *ZXSplit(UInt8 *eventData) {
    NSString *s = [NSString stringWithUTF8String:(char *)eventData] ?: @"";
    return [s componentsSeparatedByString:@";;"];
}

// SystemConfiguration's SCPreferences symbols are API_UNAVAILABLE(ios) in the
// SDK (compile-time only — they exist on-device). dlsym on a CFStringRef
// global returns the address of the variable, hence the extra indirection.
static CFStringRef ZXSCConst(void *handle, const char *sym) {
    void *addr = handle ? dlsym(handle, sym) : NULL;
    return addr ? *(CFStringRef *)addr : NULL;
}

static id ZXJSONFromB64(NSString *b64, NSError **error) {
    NSData *d = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (!d) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Invalid base64 JSON payload.")}];
        return nil;
    }
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:error];
    if (!obj && error && *error) {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Invalid JSON payload.")}];
    }
    return obj;
}

static NSString *ZXB64(id obj) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    return [d base64EncodedStringWithOptions:0] ?: @"";
}

static CGRect ZXRectFromString(NSString *s, CGRect fallback) {
    NSArray *p = [s componentsSeparatedByString:@","];
    if ([p count] != 4) return fallback;
    return CGRectMake([p[0] floatValue], [p[1] floatValue], [p[2] floatValue], [p[3] floatValue]);
}

static NSString *ZXDocRoot(void) {
    @try { return getDocumentRoot(); }
    @catch (NSException *e) { return @"/var/mobile/Library/ZXTouch"; }
}

// ---------------------------------------------------------------- 30 screenshot

NSString *screenshotFromRawData(UInt8 *eventData, NSError **error) {
    NSArray *parts = ZXSplit(eventData);
    if ([parts count] < 1 || [[parts objectAtIndex:0] length] == 0) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Screenshot format: name[;;x,y,w,h].")}];
        return nil;
    }
    NSString *name = [parts objectAtIndex:0];
    if ([[name pathExtension] length] == 0) name = [name stringByAppendingPathExtension:@"jpg"];
    NSString *dir = [ZXDocRoot() stringByAppendingPathComponent:@"images"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir stringByAppendingPathComponent:[name lastPathComponent]];

    UIImage *img = [Screen screenShotUIImage];
    if (!img) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Screenshot is nil.")}];
        return nil;
    }
    if ([parts count] >= 2 && [[parts objectAtIndex:1] length] > 0) {
        CGRect region = ZXRectFromString([parts objectAtIndex:1], CGRectZero);
        CGImageRef cropped = CGImageCreateWithImageInRect([img CGImage], region);
        if (cropped) {
            img = [UIImage imageWithCGImage:cropped scale:[img scale] orientation:[img imageOrientation]];
            CGImageRelease(cropped);
        }
    }
    NSString *extension = name.pathExtension.lowercaseString;
    NSData *imageData = [extension isEqualToString:@"png"]
        ? UIImagePNGRepresentation(img)
        : UIImageJPEGRepresentation(img, 0.9);
    if (!imageData || ![imageData writeToFile:path atomically:YES]) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Cannot write screenshot file.")}];
        return nil;
    }
    return [NSString stringWithFormat:@"0;;%@\r\n", path];
}

// ---------------------------------------------------------------- 31 dialog choice

NSString *dialogChoiceFromRawData(UInt8 *eventData, NSError **error) {
    NSString *b64 = [ZXSplit(eventData) firstObject] ?: @"";
    NSDictionary *payload = ZXJSONFromB64(b64, error);
    if (!payload) return nil;
    NSString *title = [payload objectForKey:@"title"] ?: @"Choose";
    NSArray *options = [payload objectForKey:@"options"];
    if (![options isKindOfClass:[NSArray class]] || [options count] == 0) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"dialogChoice needs non-empty options array.")}];
        return nil;
    }
    __block NSInteger picked = -1;
    __block BOOL finished = NO;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
        UIWindow *win = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                              : [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        win.windowLevel = UIWindowLevelAlert + 4;
        UIViewController *rvc = [[UIViewController alloc] init];
        rvc.view.backgroundColor = [UIColor clearColor];
        win.rootViewController = rvc;
        [win makeKeyAndVisible];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
            message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [options enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSString *label = [obj isKindOfClass:[NSString class]] ? obj : [obj description];
            [alert addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *a) {
                    if (!finished) { finished = YES; picked = (NSInteger)idx; }
                    win.hidden = YES;
                    dispatch_semaphore_signal(sema);
                }]];
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel
            handler:^(UIAlertAction *a) {
                if (!finished) { finished = YES; picked = -1; }
                win.hidden = YES;
                dispatch_semaphore_signal(sema);
            }]];
        [rvc presentViewController:alert animated:YES completion:nil];
    });
    if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_SEC))) != 0) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Choice dialog timed out.")}];
        return nil;
    }
    if (picked < 0) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"User cancelled choice dialog.")}];
        return nil;
    }
    return [NSString stringWithFormat:@"0;;%ld\r\n", (long)picked];
}

// ---------------------------------------------------------------- 32 overlay

static UIWindow *_overlayWindow = nil;
static UILabel *_overlayLabel = nil;
static NSMutableDictionary *_overlayData = nil;

static void ZXOverlayRender(void) {
    if (!_overlayLabel) return;
    NSMutableString *text = [NSMutableString string];
    for (NSString *k in _overlayData) {
        [text appendFormat:@"%@: %@\n", k, [_overlayData objectForKey:k]];
    }
    _overlayLabel.text = text;
}

NSString *overlayFromRawData(UInt8 *eventData, NSError **error) {
    NSArray *parts = ZXSplit(eventData);
    NSString *op = [parts count] > 0 ? [parts objectAtIndex:0] : @"";
    __block NSString *result = @"0\r\n";
    dispatch_sync(dispatch_get_main_queue(), ^{
        if ([op isEqualToString:@"hide"]) {
            _overlayWindow.hidden = YES;
            _overlayWindow = nil; _overlayLabel = nil; _overlayData = nil;
        } else if ([op isEqualToString:@"update"] && [parts count] >= 3) {
            if (!_overlayData) _overlayData = [NSMutableDictionary dictionary];
            [_overlayData setObject:[parts objectAtIndex:2] forKey:[parts objectAtIndex:1]];
            ZXOverlayRender();
        } else if ([op isEqualToString:@"show"]) {
            NSDictionary *dict = nil;
            if ([parts count] >= 2 && [[parts objectAtIndex:1] length] > 0) {
                NSError *jerr = nil;
                dict = ZXJSONFromB64([parts objectAtIndex:1], &jerr);
                if (![dict isKindOfClass:[NSDictionary class]]) dict = nil;
            }
            _overlayData = dict ? [dict mutableCopy] : [NSMutableDictionary dictionary];
            if (!_overlayWindow) {
                UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
                _overlayWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                                       : [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
                _overlayWindow.windowLevel = UIWindowLevelStatusBar + 1;
                _overlayWindow.userInteractionEnabled = NO; // never block touches
                _overlayWindow.backgroundColor = [UIColor clearColor];
                _overlayLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 40, 300, 400)];
                _overlayLabel.numberOfLines = 0;
                _overlayLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
                _overlayLabel.textColor = [UIColor whiteColor];
                _overlayLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
                _overlayLabel.layer.cornerRadius = 8;
                _overlayLabel.clipsToBounds = YES;
                [_overlayWindow addSubview:_overlayLabel];
            }
            ZXOverlayRender();
            _overlayWindow.hidden = NO;
        } else {
            result = nil;
        }
    });
    if (!result && error) {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Overlay format: show[;;base64json] | update;;key;;value | hide.")}];
    }
    return result;
}

// ---------------------------------------------------------------- app helpers

static id ZXAppObject(NSString *bundleId) {
    @try {
        id ctrl = [%c(SBApplicationController) sharedInstance];
        if ([ctrl respondsToSelector:@selector(applicationWithBundleIdentifier:)]) {
            return [ctrl applicationWithBundleIdentifier:bundleId];
        }
    } @catch (NSException *e) {
        NSLog(@"com.zjx.springboard: app lookup failed: %@", e.reason);
    }
    return nil;
}

static pid_t ZXAppPid(NSString *bundleId) {
    // KVC on purpose: no private selectors are referenced at compile time,
    // so this is robust across iOS versions (unknown keys throw → -1).
    id app = ZXAppObject(bundleId);
    @try {
        id proc = [app valueForKey:@"process"];
        NSNumber *pidNum = [proc valueForKey:@"pid"];
        if ([pidNum respondsToSelector:@selector(intValue)]) {
            return (pid_t)[pidNum intValue];
        }
    } @catch (NSException *e) {
        NSLog(@"com.zjx.springboard: pid lookup failed: %@", e.reason);
    }
    return -1;
}

NSString *appKillFromRawData(UInt8 *eventData, NSError **error) {
    NSString *bundleId = [[NSString stringWithUTF8String:(char *)eventData]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    pid_t pid = ZXAppPid(bundleId);
    if (pid <= 0) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"App is not running or pid unavailable.")}];
        return nil;
    }
    if (kill(pid, SIGKILL) != 0) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"kill() failed.")}];
        return nil;
    }
    return @"0\r\n";
}

NSString *appStateFromRawData(UInt8 *eventData, NSError **error) {
    NSString *bundleId = [[NSString stringWithUTF8String:(char *)eventData]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    @try {
        id front = getFrontMostApplication();
        NSString *frontId = nil;
        if ([front respondsToSelector:@selector(displayIdentifier)]) frontId = [front displayIdentifier];
        else if ([front respondsToSelector:@selector(bundleIdentifier)]) frontId = [front bundleIdentifier];
        if (frontId && [frontId isEqualToString:bundleId]) return @"0;;2\r\n";
    } @catch (NSException *e) {}
    pid_t pid = ZXAppPid(bundleId);
    if (pid > 0) return @"0;;1\r\n";
    if (ZXAppObject(bundleId)) {
        // Installed but no live process we can see.
        return @"0;;0\r\n";
    }
    if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
        userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Unknown bundle identifier.")}];
    return nil;
}

NSString *openURLFromRawData(UInt8 *eventData, NSError **error) {
    NSString *urlStr = [[NSString stringWithUTF8String:(char *)eventData]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Invalid URL.")}];
        return nil;
    }
    __block BOOL ok = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        @try {
            UIApplication *app = [UIApplication sharedApplication];
            if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
                dispatch_semaphore_t s = dispatch_semaphore_create(0);
                [app openURL:url options:@{} completionHandler:^(BOOL success) {
                    ok = success;
                    dispatch_semaphore_signal(s);
                }];
                dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)));
            } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                ok = [app openURL:url];
#pragma clang diagnostic pop
            }
        } @catch (NSException *e) {
            NSLog(@"com.zjx.springboard: openURL failed: %@", e.reason);
        }
    });
    if (!ok && error) {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"System refused to open URL.")}];
        return nil;
    }
    return @"0\r\n";
}

// Container UUID lookup without private frameworks: scan mobile containers
// for the metadata plist matching the bundle id.
static NSString *ZXContainerUUID(NSString *bundleId) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = @"/var/mobile/Containers/Data/Application";
    for (NSString *uuid in [fm contentsOfDirectoryAtPath:base error:nil]) {
        NSString *meta = [[base stringByAppendingPathComponent:uuid]
            stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
        NSDictionary *md = [NSDictionary dictionaryWithContentsOfFile:meta];
        if ([[md objectForKey:@"MCMMetadataIdentifier"] isEqualToString:bundleId]) return uuid;
    }
    return nil;
}

NSString *appClearFromRawData(UInt8 *eventData, NSError **error) {
    NSString *bundleId = [[NSString stringWithUTF8String:(char *)eventData]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // Best effort: stop the app first so files are not rewritten mid-wipe.
    pid_t pid = ZXAppPid(bundleId);
    if (pid > 0) kill(pid, SIGKILL);
    NSString *uuid = ZXContainerUUID(bundleId);
    if (!uuid) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"App container not found.")}];
        return nil;
    }
    // SAFE clear only: caches/tmp/WebKit/SplashBoard. Preferences, Keychain
    // and Cookies are intentionally preserved (clearData-style, no logout).
    NSArray *subpaths = @[@"Library/Caches", @"tmp",
        @"Library/WebKit", @"Library/SplashBoard", @"Library/Caches/WebKit"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = [@"/var/mobile/Containers/Data/Application" stringByAppendingPathComponent:uuid];
    int cleared = 0;
    for (NSString *sub in subpaths) {
        NSString *p = [root stringByAppendingPathComponent:sub];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:p isDirectory:&isDir]) {
            NSError *e = nil;
            if (isDir) {
                for (NSString *child in [fm contentsOfDirectoryAtPath:p error:nil]) {
                    if ([fm removeItemAtPath:[p stringByAppendingPathComponent:child] error:&e]) cleared++;
                }
            } else if ([fm removeItemAtPath:p error:&e]) {
                cleared++;
            }
        }
    }
    return [NSString stringWithFormat:@"0;;%d\r\n", cleared];
}

// ---------------------------------------------------------------- 37 keypress

// buttonMask bit mapping (experimental — calibrate on device if needed):
// bit0 home, bit1 volume-up, bit2 volume-down, bit3 power.
static uint32_t ZXButtonMask(NSString *name) {
    NSString *n = [[name lowercaseString] stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([n isEqualToString:@"home"]) return 1 << 0;
    if ([n isEqualToString:@"volumeup"] || [n isEqualToString:@"volume_up"]) return 1 << 1;
    if ([n isEqualToString:@"volumedown"] || [n isEqualToString:@"volume_down"]) return 1 << 2;
    if ([n isEqualToString:@"power"] || [n isEqualToString:@"lock"]) return 1 << 3;
    return 0;
}

NSString *keyPressFromRawData(UInt8 *eventData, NSError **error) {
    NSArray *parts = ZXSplit(eventData);
    if ([parts count] < 2) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Key format: name;;down|up (home|volumeUp|volumeDown|power).")}];
        return nil;
    }
    uint32_t mask = ZXButtonMask([parts objectAtIndex:0]);
    if (mask == 0) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Unknown key name.")}];
        return nil;
    }
    BOOL down = [[[parts objectAtIndex:1] lowercaseString] hasPrefix:@"down"];
    // Home is served reliably via SpringBoard foreground (same visible effect).
    if (mask == (1 << 0) && down) {
        bringAppForeground(@"com.apple.springboard");
        return @"0\r\n";
    }
    uint64_t ts = mach_absolute_time();
    IOHIDEventRef ev = IOHIDEventCreateButtonEvent(kCFAllocatorDefault, ts, down ? mask : 0, 0);
    if (!ev) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Cannot create button event.")}];
        return nil;
    }
    static IOHIDEventSystemClientRef client = NULL;
    if (!client) client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    IOHIDEventSystemClientDispatchEvent(client, ev);
    CFRelease(ev);
    return @"0\r\n";
}

// ---------------------------------------------------------------- 38 vibrate

NSString *vibrateFromRawData(UInt8 *eventData, NSError **error) {
    (void)eventData; (void)error;
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    return @"0\r\n";
}

// ---------------------------------------------------------------- 39 color multi

NSString *colorMultiFromRawData(UInt8 *eventData, NSError **error) {
    // "rrggbb;;tolerance;;count;;x,y,w,h;;skip"
    NSArray *parts = ZXSplit(eventData);
    if ([parts count] < 5) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"ColorMulti format: rrggbb;;tolerance;;count;;x,y,w,h;;skip.")}];
        return nil;
    }
    NSString *hex = [parts objectAtIndex:0];
    unsigned rgb = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&rgb];
    int tr = (rgb >> 16) & 0xFF, tg = (rgb >> 8) & 0xFF, tb = rgb & 0xFF;
    int tol = [[parts objectAtIndex:1] intValue];
    int want = MAX(1, [[parts objectAtIndex:2] intValue]);
    CGRect region = ZXRectFromString([parts objectAtIndex:3], CGRectZero);
    int skip = MAX(0, [[parts objectAtIndex:4] intValue]);
    if (CGRectIsEmpty(region)) {
        region = CGRectMake(0, 0, [Screen getScreenWidth], [Screen getScreenHeight]);
    }

    CGImageRef screen = [Screen createScreenShotCGImageRef];
    if (!screen) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Screenshot is nil.")}];
        return nil;
    }
    int w = (int)region.size.width, h = (int)region.size.height;
    CGImageRef crop = CGImageCreateWithImageInRect(screen, region);
    CGImageRelease(screen);
    if (!crop) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Cannot crop screenshot.")}];
        return nil;
    }
    int rowBytes = w * 4;
    unsigned char *buf = (unsigned char *)malloc(rowBytes * h);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, w, h, 8, rowBytes, cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), crop);
    CGImageRelease(crop);
    CGContextRelease(ctx);

    NSMutableString *out = [NSMutableString stringWithString:@"0"];
    int found = 0, step = skip + 1;
    for (int yy = 0; yy < h && found < want; yy += step) {
        for (int xx = 0; xx < w && found < want; xx += step) {
            int base = (yy * w + xx) * 4;
            int r = buf[base], g = buf[base + 1], b = buf[base + 2];
            if (abs(r - tr) <= tol && abs(g - tg) <= tol && abs(b - tb) <= tol) {
                [out appendFormat:@";;%d,%d", (int)region.origin.x + xx, (int)region.origin.y + yy];
                found++;
                // skip ahead to avoid reporting the same blob repeatedly
                xx += 4;
            }
        }
    }
    free(buf);
    if (found == 0) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"-1;;-1 color not found.")}];
        return nil;
    }
    [out appendString:@"\r\n"];
    return out;
}

// ---------------------------------------------------------------- 40 color pattern

NSString *colorPatternFromRawData(UInt8 *eventData, NSError **error) {
    // base64([{"c":"rrggbb","dx":0,"dy":0},...]) + ";;tolerance[;;x,y,w,h]"
    NSArray *parts = ZXSplit(eventData);
    NSArray *pattern = ZXJSONFromB64([parts firstObject] ?: @"", error);
    if (![pattern isKindOfClass:[NSArray class]] || [pattern count] == 0) return nil;
    int tol = [parts count] > 1 ? [[parts objectAtIndex:1] intValue] : 10;
    CGRect region = [parts count] > 2
        ? ZXRectFromString([parts objectAtIndex:2], CGRectZero) : CGRectZero;
    if (CGRectIsEmpty(region)) {
        region = CGRectMake(0, 0, [Screen getScreenWidth], [Screen getScreenHeight]);
    }
    NSDictionary *anchor = [pattern objectAtIndex:0];
    NSString *hex = [anchor objectForKey:@"c"] ?: @"";
    unsigned rgb = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&rgb];
    // Anchor via existing single-point searcher (tested code path).
    CGImageRef screen = [Screen createScreenShotCGImageRef];
    if (!screen) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Screenshot is nil.")}];
        return nil;
    }
    int tr = (rgb >> 16) & 0xFF, tg = (rgb >> 8) & 0xFF, tb = rgb & 0xFF;
    NSString *single = [ColorPicker searchRGBFromCGImageRef:screen region:region
        redMin:MAX(0, tr - tol) redMax:MIN(255, tr + tol)
        greenMin:MAX(0, tg - tol) greenMax:MIN(255, tg + tol)
        blueMin:MAX(0, tb - tol) blueMax:MIN(255, tb + tol) skip:2];
    NSArray *sp = [single componentsSeparatedByString:@";;"];
    CGImageRelease(screen);
    if ([sp count] < 2 || [[sp objectAtIndex:0] isEqualToString:@"-1"]) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"-1;;-1 pattern anchor not found.")}];
        return nil;
    }
    int ax = [[sp objectAtIndex:0] intValue], ay = [[sp objectAtIndex:1] intValue];
    // Verify offsets against fresh single-pixel reads.
    CGImageRef screen2 = [Screen createScreenShotCGImageRef];
    for (NSUInteger i = 1; i < [pattern count]; i++) {
        NSDictionary *p = [pattern objectAtIndex:i];
        unsigned prgb = 0;
        [[NSScanner scannerWithString:([p objectForKey:@"c"] ?: @"")] scanHexInt:&prgb];
        int er = (prgb >> 16) & 0xFF, eg = (prgb >> 8) & 0xFF, eb = prgb & 0xFF;
        NSDictionary *got = [ColorPicker colorAtPositionFromCGImage:screen2
            x:ax + [[p objectForKey:@"dx"] intValue]
            andY:ay + [[p objectForKey:@"dy"] intValue]];
        int gr = [[got objectForKey:@"red"] intValue];
        int gg = [[got objectForKey:@"green"] intValue];
        int gb = [[got objectForKey:@"blue"] intValue];
        if (abs(gr - er) > tol || abs(gg - eg) > tol || abs(gb - eb) > tol) {
            CGImageRelease(screen2);
            if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"-1;;-1 pattern mismatch.")}];
            return nil;
        }
    }
    CGImageRelease(screen2);
    return [NSString stringWithFormat:@"0;;%d;;%d\r\n", ax, ay];
}

// ---------------------------------------------------------------- 41/45 image region & multi

static CGRect ZXMatchOnImage(CGImageRef screen, NSString *templatePath,
        float threshold, int maxTry, float scale, CGRect region, float *outScore, NSError **error) {
    TemplateMatch *m = [[TemplateMatch alloc] init];
    [m setAcceptableValue:threshold];
    [m setMaxTryTimes:maxTry];
    [m setScaleRation:scale];
    CGImageRef target = screen;
    CGImageRef crop = NULL;
    if (!CGRectIsEmpty(region) && !CGRectIsNull(region)) {
        crop = CGImageCreateWithImageInRect(screen, region);
        if (crop) target = crop;
    }
    CGRect r = [m templateMatchWithCGImage:target templatePath:templatePath error:error];
    if (outScore) *outScore = [m lastScore];
    if (crop) CGImageRelease(crop);
    if (!CGRectIsEmpty(region) && !CGRectIsNull(region) && !CGRectIsEmpty(r)) {
        r.origin.x += region.origin.x;
        r.origin.y += region.origin.y;
    }
    return r;
}

NSString *imageRegionFromRawData(UInt8 *eventData, NSError **error) {
    // "template;;threshold;;x,y,w,h[;;maxTry;;scale]"
    NSArray *parts = ZXSplit(eventData);
    if ([parts count] < 3) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"ImageRegion format: template;;threshold;;x,y,w,h[;;maxTry;;scale].")}];
        return nil;
    }
    NSString *tpl = [parts objectAtIndex:0];
    float thr = [[parts objectAtIndex:1] floatValue];
    CGRect region = ZXRectFromString([parts objectAtIndex:2], CGRectZero);
    int maxTry = [parts count] > 3 ? [[parts objectAtIndex:3] intValue] : 2;
    float scale = [parts count] > 4 ? [[parts objectAtIndex:4] floatValue] : 0.8;
    float confidence = -1.0f;
    if (![[NSFileManager defaultManager] fileExistsAtPath:tpl]) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Template image not found.")}];
        return nil;
    }
    CGImageRef screen = [Screen createScreenShotCGImageRef];
    if (!screen) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Screenshot is nil.")}];
        return nil;
    }
    CGRect r = ZXMatchOnImage(screen, tpl, thr, maxTry, scale, region, &confidence, error);
    CGImageRelease(screen);
    if (error && *error) return nil;
    if (CGRectIsEmpty(r)) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"-1;;no match in region.")}];
        return nil;
    }
    // Trailing confidence is additive: old clients read fields 0-3 and ignore it.
    return [NSString stringWithFormat:@"0;;%.2f;;%.2f;;%.2f;;%.2f;;%.3f\r\n",
        r.origin.x, r.origin.y, r.size.width, r.size.height, confidence];
}

NSString *imageMultiFromRawData(UInt8 *eventData, NSError **error) {
    // "template;;threshold[;;max]" — tile full screen, dedupe by template size.
    NSArray *parts = ZXSplit(eventData);
    if ([parts count] < 1 || [[parts objectAtIndex:0] length] == 0) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"ImageMulti format: template;;threshold[;;max].")}];
        return nil;
    }
    NSString *tpl = [parts objectAtIndex:0];
    float thr = [parts count] > 1 ? [[parts objectAtIndex:1] floatValue] : 0.8;
    int maxN = [parts count] > 2 ? MAX(1, [[parts objectAtIndex:2] intValue]) : 5;
    UIImage *timg = [UIImage imageWithContentsOfFile:tpl];
    if (!timg) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Template image not found.")}];
        return nil;
    }
    CGFloat tw = [timg size].width, th = [timg size].height;
    CGFloat sw = [Screen getScreenWidth], sh = [Screen getScreenHeight];
    CGImageRef screen = [Screen createScreenShotCGImageRef];
    if (!screen) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Screenshot is nil.")}];
        return nil;
    }
    NSMutableArray *hits = [NSMutableArray array];
    NSMutableArray *scores = [NSMutableArray array];
    // 2x2 overlapping tiles keep per-match cost bounded.
    for (int ty = 0; ty < 2 && [hits count] < maxN; ty++) {
        for (int tx = 0; tx < 2 && [hits count] < maxN; tx++) {
            CGRect tile = CGRectMake(tx * sw / 2 - tw / 2, ty * sh / 2 - th / 2,
                                     sw / 2 + tw, sh / 2 + th);
            tile = CGRectIntersection(tile, CGRectMake(0, 0, sw, sh));
            if (CGRectIsEmpty(tile) || CGRectIsNull(tile)) continue;
            NSError *e = nil;
            float confidence = -1.0f;
            CGRect r = ZXMatchOnImage(screen, tpl, thr, 1, 0.8, tile, &confidence, &e);
            if (e || CGRectIsEmpty(r)) continue;
            BOOL dup = NO;
            for (NSValue *v in hits) {
                CGRect h = [v CGRectValue];
                if (fabs(h.origin.x - r.origin.x) < tw && fabs(h.origin.y - r.origin.y) < th) {
                    dup = YES; break;
                }
            }
            if (!dup) {
                [hits addObject:[NSValue valueWithCGRect:r]];
                [scores addObject:@(confidence)];
            }
        }
    }
    CGImageRelease(screen);
    if ([hits count] == 0) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"-1;;no match.")}];
        return nil;
    }
    NSMutableString *out = [NSMutableString stringWithString:@"0"];
    for (NSUInteger i = 0; i < [hits count]; i++) {
        CGRect r = [[hits objectAtIndex:i] CGRectValue];
        float confidence = [[scores objectAtIndex:i] floatValue];
        // Trailing per-hit confidence is additive: old clients split 4 fields
        // and fail closed into the single-match fallback instead of misreading.
        [out appendFormat:@";;%.2f,%.2f,%.2f,%.2f,%.3f",
            r.origin.x, r.origin.y, r.size.width, r.size.height, confidence];
    }
    [out appendString:@"\r\n"];
    return out;
}

// ---------------------------------------------------------------- 42/43/44 record events

static NSString *ZXRecordDir(void) {
    NSString *dir = [ZXDocRoot() stringByAppendingPathComponent:@"scripts/recordings"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
        withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

// Native replay of an event table (same schema as prelude.recordPlay).
// Runs on the socket thread (like .raw replay); fire-and-forget, no reply
// channel needed beyond the final ack.
static int ZXPlayEventTable(NSArray *events, float speed) {
    // performTouchFromRawData: Touch.h ("1<type><ff><xxxxx><yyyyy>" wire format)
    int played = 0;
    for (id ev in events) {
        if (![ev isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *e = ev;
        NSString *kind = [e objectForKey:@"type"];
        if (!kind) kind = [e objectForKey:@"action"];
        if (!kind) kind = @"tap";
        kind = [kind lowercaseString];
        if ([kind isEqualToString:@"sleep"] || [kind isEqualToString:@"delay"] || [kind isEqualToString:@"wait"]) {
            NSNumber *delayNum = [e objectForKey:@"delay"];
            if (!delayNum) delayNum = [e objectForKey:@"seconds"];
            if (!delayNum) delayNum = @0.5;
            float d = [delayNum floatValue] / MAX(speed, 0.01);
            usleep((useconds_t)(d * 1000000));
            played++;
        } else if ([kind isEqualToString:@"swipe"]) {
            // Expand swipe into down/move/up touch frames.
            float x1 = [[e objectForKey:@"x1"] floatValue], y1 = [[e objectForKey:@"y1"] floatValue];
            float x2 = [[e objectForKey:@"x2"] floatValue], y2 = [[e objectForKey:@"y2"] floatValue];
            float dur = [[e objectForKey:@"duration"] ?: @0.5 floatValue];
            int steps = MAX(2, (int)(dur / 0.02));
            NSString *down = [NSString stringWithFormat:@"11%02d%05d%05d", 1, (int)(x1 * 10), (int)(y1 * 10)];
            performTouchFromRawData((UInt8 *)[down UTF8String]);
            for (int i = 1; i <= steps; i++) {
                float t = (float)i / steps;
                NSString *mv = [NSString stringWithFormat:@"12%02d%05d%05d", 1,
                    (int)((x1 + (x2 - x1) * t) * 10), (int)((y1 + (y2 - y1) * t) * 10)];
                performTouchFromRawData((UInt8 *)[mv UTF8String]);
                usleep((useconds_t)(dur / steps * 1000000));
            }
            NSString *up = [NSString stringWithFormat:@"10%02d%05d%05d", 1, (int)(x2 * 10), (int)(y2 * 10)];
            performTouchFromRawData((UInt8 *)[up UTF8String]);
            played++;
        } else {
            // tap/down/move/up: "1<type><ff><xxxxx><yyyyy>" (TOUCH_DATA_LEN wire format)
            int t = 1, finger = 1;
            NSString *k = kind;
            if ([k isEqualToString:@"down"]) t = 1;
            else if ([k isEqualToString:@"move"]) t = 2;
            else if ([k isEqualToString:@"up"]) t = 0;
            else t = 1; // "tap"/"touch" handled as down below
            NSNumber *fingerNum = [e objectForKey:@"finger"];
            if (!fingerNum) fingerNum = [e objectForKey:@"finger_index"];
            if (!fingerNum) fingerNum = @1;
            finger = [fingerNum intValue];
            float x = [[e objectForKey:@"x"] floatValue], y = [[e objectForKey:@"y"] floatValue];
            if ([k isEqualToString:@"tap"] || [k isEqualToString:@"touch"]) {
                NSString *d = [NSString stringWithFormat:@"11%02d%05d%05d", finger, (int)(x * 10), (int)(y * 10)];
                performTouchFromRawData((UInt8 *)[d UTF8String]);
                usleep(50000);
                NSString *u = [NSString stringWithFormat:@"10%02d%05d%05d", finger, (int)(x * 10), (int)(y * 10)];
                performTouchFromRawData((UInt8 *)[u UTF8String]);
            } else {
                NSString *s = [NSString stringWithFormat:@"1%d%02d%05d%05d", t, finger, (int)(x * 10), (int)(y * 10)];
                performTouchFromRawData((UInt8 *)[s UTF8String]);
            }
            played++;
            float delay = [[e objectForKey:@"delay"] floatValue];
            if (delay > 0) usleep((useconds_t)(delay / MAX(speed, 0.01) * 1000000));
        }
    }
    return played;
}

NSString *recordPlayEventsFromRawData(UInt8 *eventData, NSError **error) {
    NSString *b64 = [ZXSplit(eventData) firstObject] ?: @"";
    NSArray *events = ZXJSONFromB64(b64, error);
    if (![events isKindOfClass:[NSArray class]]) {
        if (error && !*error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"recordPlay needs a JSON array.")}];
        return nil;
    }
    int n = ZXPlayEventTable(events, 1.0);
    return [NSString stringWithFormat:@"0;;%d\r\n", n];
}

NSString *recordSaveFromRawData(UInt8 *eventData, NSError **error) {
    NSArray *parts = ZXSplit(eventData);
    if ([parts count] < 2) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"recordSave format: name;;base64(events).")}];
        return nil;
    }
    NSString *name = [[parts objectAtIndex:0] lastPathComponent];
    if ([[name pathExtension] length] == 0) name = [name stringByAppendingPathExtension:@"json"];
    NSArray *events = ZXJSONFromB64([parts objectAtIndex:1], error);
    if (![events isKindOfClass:[NSArray class]]) return nil;
    NSString *path = [ZXRecordDir() stringByAppendingPathComponent:name];
    NSData *d = [NSJSONSerialization dataWithJSONObject:events options:0 error:error];
    if (!d) return nil;
    if (![d writeToFile:path atomically:YES]) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Cannot write recording file.")}];
        return nil;
    }
    return @"0\r\n";
}

NSString *recordLoadFromRawData(UInt8 *eventData, NSError **error) {
    NSString *name = [[[NSString stringWithUTF8String:(char *)eventData]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lastPathComponent];
    if ([[name pathExtension] length] == 0) name = [name stringByAppendingPathExtension:@"json"];
    NSString *path = [ZXRecordDir() stringByAppendingPathComponent:name];
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Recording not found.")}];
        return nil;
    }
    return [NSString stringWithFormat:@"0;;%@\r\n", [d base64EncodedStringWithOptions:0]];
}

// ---------------------------------------------------------------- 46 ping

NSString *pingFromRawData(UInt8 *eventData, NSError **error) {
    (void)eventData; (void)error;
    return @"0;;ok;;zxtouch\r\n";
}

// ---------------------------------------------------------------- 51 cellular data

NSString *cellularDataFromRawData(UInt8 *eventData, NSError **error) {
    // Payload: "0|1[;;delaySecs]". Uses the same private API the Settings app
    // toggles through (CTCellularDataPlanSetIsEnabled). Resolved with dlsym so
    // the tweak still loads on iOS versions without the symbol, in which case
    // the caller falls back to the plist method. Needs the
    // com.apple.CommCenter.fine-grained entitlement on the host process
    // (present since iOS 8.3); without it CommCenter ignores the request.
    NSArray *parts = ZXSplit(eventData);
    BOOL wantOn = [[parts firstObject] intValue] ? YES : NO;
    double delay = [parts count] > 1 ? [[parts objectAtIndex:1] doubleValue] : 0;

    static void (*setEnabled)(BOOL) = NULL;
    static BOOL lookedUp = NO;
    if (!lookedUp) {
        lookedUp = YES;
        void *ct = dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY);
        if (ct) setEnabled = (void (*)(BOOL))dlsym(ct, "CTCellularDataPlanSetIsEnabled");
    }
    if (!setEnabled) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Cellular API unavailable on this iOS (CTCellularDataPlanSetIsEnabled missing).")}];
        return nil;
    }
    @try {
        setEnabled(wantOn);
    } @catch (NSException *e) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError([@"Cellular toggle failed: " stringByAppendingString:e.reason ?: @"unknown"])}];
        return nil;
    }
    if (delay > 0) {
        // Restore the opposite state without blocking the reply: the Python
        // side returns immediately, like the plist path's shell timer.
        BOOL restore = !wantOn;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @try { setEnabled(restore); } @catch (NSException *e) {}
        });
    }
    return @"0\r\n";
}

// ---------------------------------------------------------------- 52 airplane mode

NSString *airplaneModeFromRawData(UInt8 *eventData, NSError **error) {
    // Payload: "0|1[;;delaySecs]". Same API the Control Center toggle goes
    // through (RadiosPreferences in AppSupport). The class is looked up at
    // runtime so the tweak loads on every iOS; writing com.apple.radios.plist
    // needs the SystemConfiguration write entitlements, which SpringBoard
    // (the tweak host) holds. The value is read back — a mismatch means the
    // write was ignored and is reported instead of a false success.
    NSArray *parts = ZXSplit(eventData);
    BOOL wantOn = [[parts firstObject] intValue] ? YES : NO;
    double delay = [parts count] > 1 ? [[parts objectAtIndex:1] doubleValue] : 0;

    Class cls = NSClassFromString(@"RadiosPreferences");
    if (!cls) {
        NSBundle *b = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/AppSupport.framework"];
        @try { [b load]; } @catch (NSException *e) {}
        cls = NSClassFromString(@"RadiosPreferences");
    }
    if (!cls) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Airplane API unavailable on this iOS (RadiosPreferences missing).")}];
        return nil;
    }
    RadiosPreferences *prefs = nil;
    @try {
        prefs = [[cls alloc] init];
        if (![prefs respondsToSelector:@selector(setAirplaneMode:)] ||
            ![prefs respondsToSelector:@selector(airplaneMode)]) {
            if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Airplane API changed on this iOS (selectors missing).")}];
            return nil;
        }
        [prefs setAirplaneMode:wantOn];
        [prefs synchronize];
        // Give the prefs daemon a moment to settle, then verify.
        [NSThread sleepForTimeInterval:0.5];
        BOOL actual = [prefs airplaneMode] ? YES : NO;
        if (actual != wantOn) {
            if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Airplane toggle ignored by the system (missing entitlement?).")}];
            return nil;
        }
    } @catch (NSException *e) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError([@"Airplane toggle failed: " stringByAppendingString:e.reason ?: @"unknown"])}];
        return nil;
    }
    if (delay > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                @try {
                    RadiosPreferences *rp = [[NSClassFromString(@"RadiosPreferences") alloc] init];
                    [rp setAirplaneMode:!wantOn];
                    [rp synchronize];
                } @catch (NSException *e) {}
            }
        });
    }
    return @"0\r\n";
}

// ---------------------------------------------------------------- 53 proxy

NSString *proxyFromRawData(UInt8 *eventData, NSError **error) {
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
    NSArray *parts = ZXSplit(eventData);
    NSString *first = [parts count] > 0 ? [parts objectAtIndex:0] : @"";
    BOOL clear = [first isEqualToString:@"clear"];
    NSString *host = clear ? nil : first;
    int port = (int)([parts count] > 1 ? [[parts objectAtIndex:1] intValue] : 0);
    if (!clear && (host.length == 0 || port <= 0 || port > 65535)) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Proxy format: host;;port (1-65535), or clear.")}];
        return nil;
    }

    typedef SCPreferencesRef (*ZXSCPrefsCreateFn)(CFAllocatorRef, CFStringRef, CFStringRef);
    typedef Boolean (*ZXSCPrefsLockFn)(SCPreferencesRef, Boolean);
    typedef Boolean (*ZXSCPrefsUnlockFn)(SCPreferencesRef);
    typedef CFPropertyListRef (*ZXSCPrefsGetValueFn)(SCPreferencesRef, CFStringRef);
    typedef CFPropertyListRef (*ZXSCPrefsPathGetValueFn)(SCPreferencesRef, CFStringRef);
    typedef Boolean (*ZXSCPrefsSetValueFn)(SCPreferencesRef, CFStringRef, CFPropertyListRef);
    typedef Boolean (*ZXSCPrefsCommitFn)(SCPreferencesRef);
    typedef Boolean (*ZXSCPrefsApplyFn)(SCPreferencesRef);
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
    CFStringRef kCurSet = ZXSCConst(sc, "kSCPrefCurrentSet");
    CFStringRef kNetServices = ZXSCConst(sc, "kSCPrefNetworkServices");
    CFStringRef kCompNetwork = ZXSCConst(sc, "kSCCompNetwork");
    CFStringRef kCompService = ZXSCConst(sc, "kSCCompService");
    CFStringRef kUserName = ZXSCConst(sc, "kSCPropUserDefinedName");
    CFStringRef kProxies = ZXSCConst(sc, "kSCEntNetProxies");
    CFStringRef kHTTPEnable = ZXSCConst(sc, "kSCPropNetProxiesHTTPEnable");
    CFStringRef kHTTPProxy = ZXSCConst(sc, "kSCPropNetProxiesHTTPProxy");
    CFStringRef kHTTPPort = ZXSCConst(sc, "kSCPropNetProxiesHTTPPort");
    CFStringRef kHTTPSEnable = ZXSCConst(sc, "kSCPropNetProxiesHTTPSEnable");
    CFStringRef kHTTPSProxy = ZXSCConst(sc, "kSCPropNetProxiesHTTPSProxy");
    CFStringRef kHTTPSPort = ZXSCConst(sc, "kSCPropNetProxiesHTTPSPort");
    CFStringRef kSOCKSEnable = ZXSCConst(sc, "kSCPropNetProxiesSOCKSEnable");
    CFStringRef kSOCKSProxy = ZXSCConst(sc, "kSCPropNetProxiesSOCKSProxy");
    CFStringRef kSOCKSPort = ZXSCConst(sc, "kSCPropNetProxiesSOCKSPort");
    if (!pCreate || !pLock || !pUnlock || !pGetValue || !pPathGetValue ||
        !pSetValue || !pCommit || !pApply || !pError ||
        !kCurSet || !kNetServices || !kCompNetwork || !kCompService ||
        !kUserName || !kProxies || !kHTTPEnable || !kHTTPProxy || !kHTTPPort ||
        !kHTTPSEnable || !kHTTPSProxy || !kHTTPSPort || !kSOCKSEnable ||
        !kSOCKSProxy || !kSOCKSPort) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Proxy API unavailable on this iOS (SystemConfiguration symbols missing).")}];
        return nil;
    }

    SCPreferencesRef prefs = pCreate(NULL, CFSTR("zxtouch-proxy"), NULL);
    if (!prefs) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(@"Could not open system preferences.")}];
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
            userInfo:@{NSLocalizedDescriptionKey: ZXExtError(fail)}];
        return nil;
    }
    return @"0\r\n";
}
