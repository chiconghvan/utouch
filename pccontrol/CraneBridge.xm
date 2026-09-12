#include "CraneBridge.h"
#include "Common.h"
#include "Process.h"
#include "ExtTasks.h"
#include "libCrane/libCrane.h"
#include <dlfcn.h>
#include <roothide.h>

// ---------------------------------------------------------------- loader

static CraneManager *ZXCraneManager(NSError **error) {
    static Class cls = Nil;
    static BOOL probed = NO;
    static void *handle = NULL;
    if (!probed) {
        probed = YES;
        // Plain C strings: jbroot() has ObjC/C overload subtleties, and both
        // rootless (Dopamine) and roothide bootstraps live under /var/jb.
        // Crane installs its dylib next to the other opa334 libs.
        const char *candidates[] = {
            "/var/jb/usr/lib/libcrane.dylib",
            "/usr/lib/libcrane.dylib",
            NULL,
        };
        for (int i = 0; candidates[i]; i++) {
            handle = dlopen(candidates[i], RTLD_LAZY);
            if (handle) break;
        }
        cls = NSClassFromString(@"CraneManager");
    }
    if (!cls) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey:
                @"-1;;Crane not installed (requires paid Crane tweak, not Crane Lite).\r\n"}];
        return nil;
    }
    id mgr = nil;
    @try {
        // Cast through the vendored CraneManager interface so all selectors
        // resolve at compile time; the class itself is loaded dynamically.
        mgr = [(CraneManager *)cls sharedManager];
    } @catch (NSException *e) {
        NSLog(@"com.zjx.springboard: CraneManager sharedManager: %@", e.reason);
    }
    if (!mgr && error) {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: @"-1;;CraneManager unavailable.\r\n"}];
    }
    return mgr;
}

static NSError *ZXErr(NSString *msg) {
    return [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
        userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"-1;;%@\r\n", msg]}];
}

static id ZXPayload(UInt8 *eventData, NSError **error) {
    NSString *b64 = [[NSString stringWithUTF8String:(char *)eventData]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *d = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (!d) {
        if (error) *error = ZXErr(@"Invalid base64 JSON payload.");
        return nil;
    }
    NSError *jerr = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:&jerr];
    if (!obj) {
        if (error) *error = ZXErr(@"Invalid JSON payload.");
        return nil;
    }
    return obj;
}

static NSString *ZXReply(id obj) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil] ?: [@"null" dataUsingEncoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:@"0;;%@\r\n", [d base64EncodedStringWithOptions:0]];
}

// Resolve a container id-or-display-name to its identifier.
static NSString *ZXResolveContainer(CraneManager *mgr, NSString *bundleId, NSString *nameOrId) {
    NSArray *ids = @[];
    @try { ids = [mgr containerIdentifiersOfApplicationWithIdentifier:bundleId] ?: @[]; }
    @catch (NSException *e) { return nil; }
    for (NSString *cid in ids) {
        if ([cid isEqualToString:nameOrId]) return cid;
    }
    for (NSString *cid in ids) {
        NSString *disp = nil;
        @try { disp = [mgr displayNameForContainerWithIdentifier:cid ofApplicationWithIdentifier:bundleId shouldUseShortVersion:NO]; }
        @catch (NSException *e) {}
        if (disp && [disp isEqualToString:nameOrId]) return cid;
    }
    return nil;
}

static pid_t ZXKillBundle(NSString *bundleId) {
    // Best effort: terminate so file ops don't race a live app.
    // KVC on purpose (see ZXAppPid in ExtTasks.xm): no private selectors
    // at compile time; unknown keys throw and are caught below.
    @try {
        id ctrl = [%c(SBApplicationController) sharedInstance];
        id app = [ctrl respondsToSelector:@selector(applicationWithBundleIdentifier:)]
            ? [ctrl applicationWithBundleIdentifier:bundleId] : nil;
        id proc = [app valueForKey:@"process"];
        NSNumber *pidNum = [proc valueForKey:@"pid"];
        if ([pidNum respondsToSelector:@selector(intValue)]) {
            pid_t pid = (pid_t)[pidNum intValue];
            if (pid > 0) kill(pid, SIGKILL);
            return pid;
        }
    } @catch (NSException *e) {
        NSLog(@"com.zjx.springboard: crane kill failed: %@", e.reason);
    }
    return -1;
}

static uint64_t ZXDirSize(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) return 0;
    if (!isDir) {
        return [[fm attributesOfItemAtPath:path error:nil] fileSize];
    }
    uint64_t total = 0;
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:path];
    for (NSString *rel in en) {
        total += [[[fm attributesOfItemAtPath:[path stringByAppendingPathComponent:rel]
            error:nil] objectForKey:NSFileSize] unsignedLongLongValue];
    }
    return total;
}

static BOOL ZXRunTar(NSArray *args, NSError **error) {
    // tar through posix_spawn; args already shell-quoted by caller via single string.
    NSString *tar = nil;
    for (NSString *cand in @[jbroot(@"/bin/tar"), @"/var/jb/bin/tar", @"/bin/tar", @"/usr/bin/tar"]) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:cand]) { tar = cand; break; }
    }
    if (!tar) {
        if (error) *error = ZXErr(@"tar binary not found.");
        return NO;
    }
    NSMutableString *cmd = [NSMutableString stringWithFormat:@"'%@'", [tar stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
    for (NSString *a in args) {
        [cmd appendFormat:@" '%@'", [a stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
    }
    int rc = call_system([cmd UTF8String]);
    if (rc != 0 && error) *error = ZXErr([NSString stringWithFormat:@"tar exited with code %d.", rc]);
    return rc == 0;
}

// ---------------------------------------------------------------- entry

NSString *craneFromRawData(UInt8 *eventData, NSError **error) {
    NSDictionary *p = ZXPayload(eventData, error);
    if (![p isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) *error = ZXErr(@"Payload must be a JSON object.");
        return nil;
    }
    NSString *op = [p objectForKey:@"op"] ?: @"";
    CraneManager *mgr = ZXCraneManager(error);
    if (!mgr) return nil;

    @try {
        // ---- list ---------------------------------------------------
        if ([op isEqualToString:@"list"]) {
            NSString *bundleId = [p objectForKey:@"bundleId"];
            NSArray *apps = nil;
            if (bundleId.length) {
                apps = @[bundleId];
            } else {
                @try { apps = [mgr identfiersOfApplicationsThatHaveNonDefaultContainers] ?: @[]; }
                @catch (NSException *e) { apps = @[]; }
            }
            NSMutableArray *out = [NSMutableArray array];
            for (NSString *bid in apps) {
                NSArray *ids = @[];
                @try { ids = [mgr containerIdentifiersOfApplicationWithIdentifier:bid] ?: @[]; }
                @catch (NSException *e) { continue; }
                NSString *active = nil;
                @try { active = [mgr activeContainerIdentifierForApplicationWithIdentifier:bid]; }
                @catch (NSException *e) {}
                NSMutableArray *containers = [NSMutableArray array];
                for (NSString *cid in ids) {
                    NSString *name = cid;
                    @try {
                        NSString *d = [mgr displayNameForContainerWithIdentifier:cid
                            ofApplicationWithIdentifier:bid shouldUseShortVersion:NO];
                        if (d.length) name = d;
                    } @catch (NSException *e) {}
                    [containers addObject:@{@"id": cid, @"name": name,
                        @"active": @([cid isEqualToString:active ?: @""])}];
                }
                [out addObject:@{@"bundleId": bid, @"containers": containers}];
            }
            return ZXReply(out);
        }

        NSString *bundleId = [p objectForKey:@"bundleId"];
        if (![bundleId isKindOfClass:[NSString class]] || !bundleId.length) {
            if (error) *error = ZXErr(@"Missing bundleId.");
            return nil;
        }

        // ---- switch -------------------------------------------------
        if ([op isEqualToString:@"switch"]) {
            NSString *cid = ZXResolveContainer(mgr, bundleId, [p objectForKey:@"name"] ?: @"");
            if (!cid) {
                if (error) *error = ZXErr(@"Container not found.");
                return nil;
            }
            // Non-biometric variant: automation must not block on TouchID.
            [mgr setActiveContainerIdentifier:cid forApplicationWithIdentifier:bundleId];
            @try {
                [mgr flushCFPrefsdCacheForApplicationWithIdentifier:bundleId];
                [mgr reloadApplicationWithIdentifier:bundleId];
            } @catch (NSException *e) {
                NSLog(@"com.zjx.springboard: crane switch reload: %@", e.reason);
            }
            return ZXReply(@{@"ok": @YES, @"active": cid});
        }

        // ---- create -------------------------------------------------
        if ([op isEqualToString:@"create"]) {
            NSString *name = [p objectForKey:@"name"];
            if (![name isKindOfClass:[NSString class]] || !name.length) {
                if (error) *error = ZXErr(@"Missing name.");
                return nil;
            }
            NSString *cid = [mgr createNewContainerWithName:name forApplicationWithIdentifier:bundleId];
            if (!cid) {
                if (error) *error = ZXErr(@"Create failed (Crane Lite cannot create containers).");
                return nil;
            }
            return ZXReply(@{@"ok": @YES, @"id": cid});
        }

        // ---- delete -------------------------------------------------
        if ([op isEqualToString:@"delete"]) {
            NSString *cid = ZXResolveContainer(mgr, bundleId, [p objectForKey:@"name"] ?: @"");
            if (!cid) {
                if (error) *error = ZXErr(@"Container not found.");
                return nil;
            }
            [mgr deleteContainerWithIdentifier:cid forApplicationWithIdentifier:bundleId];
            return ZXReply(@{@"ok": @YES});
        }

        // ---- wipe ---------------------------------------------------
        if ([op isEqualToString:@"wipe"]) {
            NSString *cid = ZXResolveContainer(mgr, bundleId, [p objectForKey:@"name"] ?: @"");
            if (!cid) {
                if (error) *error = ZXErr(@"Container not found.");
                return nil;
            }
            ZXKillBundle(bundleId);
            // Repopulate skeleton so the container stays usable (fresh-install state).
            [mgr wipeContainerWithIdentifier:cid forApplicationWithIdentifier:bundleId shouldRepopulate:YES];
            return ZXReply(@{@"ok": @YES});
        }

        // ---- rename -------------------------------------------------
        if ([op isEqualToString:@"rename"]) {
            NSString *cid = ZXResolveContainer(mgr, bundleId, [p objectForKey:@"old"] ?: @"");
            NSString *newName = [p objectForKey:@"new"];
            if (!cid || ![newName isKindOfClass:[NSString class]] || !newName.length) {
                if (error) *error = ZXErr(@"Container not found or missing new name.");
                return nil;
            }
            // libCrane has no direct rename: patch the settings dict values
            // equal to the old display name. Keys are not documented upstream,
            // so match by value to stay version-tolerant.
            NSString *oldDisp = nil;
            @try {
                oldDisp = [mgr displayNameForContainerWithIdentifier:cid
                    ofApplicationWithIdentifier:bundleId shouldUseShortVersion:NO];
            } @catch (NSException *e) {}
            NSMutableDictionary *settings = [[mgr containerSettingsForContainerWithIdentifier:cid
                ofApplicationWithIdentifier:bundleId] mutableCopy] ?: [NSMutableDictionary dictionary];
            __block BOOL patched = NO;
            for (NSString *k in [settings allKeys]) {
                id v = [settings objectForKey:k];
                if ([v isKindOfClass:[NSString class]] &&
                        ([v isEqualToString:oldDisp ?: @""] || [v isEqualToString:[p objectForKey:@"old"]])) {
                    [settings setObject:newName forKey:k];
                    patched = YES;
                }
            }
            if (!patched) {
                // Fallback for settings schemas without an explicit name key.
                [settings setObject:newName forKey:@"containerName"];
            }
            [mgr setContainerSettings:settings forContainerWithIdentifier:cid
                ofApplicationWithIdentifier:bundleId];
            return ZXReply(@{@"ok": @YES});
        }

        // Container-scoped file ops share resolution + path lookup.
        NSString *cid = nil;
        {
            NSString *c = [p objectForKey:@"container"];
            if ([c isKindOfClass:[NSString class]] && c.length) {
                cid = ZXResolveContainer(mgr, bundleId, c);
                if (!cid) {
                    if (error) *error = ZXErr(@"Container not found.");
                    return nil;
                }
            } else {
                @try { cid = [mgr activeContainerIdentifierForApplicationWithIdentifier:bundleId]; }
                @catch (NSException *e) {}
                if (!cid) {
                    NSArray *ids = @[];
                    @try { ids = [mgr containerIdentifiersOfApplicationWithIdentifier:bundleId] ?: @[]; }
                    @catch (NSException *e) {}
                    cid = [ids firstObject];
                }
                if (!cid) {
                    if (error) *error = ZXErr(@"No container for app.");
                    return nil;
                }
            }
        }
        NSDictionary *paths = nil;
        @try { paths = [mgr pathsAssociatedToContainerWithIdentifier:cid ofApplicationWithIdentifier:bundleId]; }
        @catch (NSException *e) {}
        if (![paths isKindOfClass:[NSDictionary class]] || [paths count] == 0) {
            if (error) *error = ZXErr(@"No container paths reported by Crane.");
            return nil;
        }
        NSMutableArray *allPaths = [NSMutableArray array];
        for (id v in [paths allValues]) {
            if ([v isKindOfClass:[NSString class]]) [allPaths addObject:v];
            else if ([v isKindOfClass:[NSArray class]]) {
                for (id s in v) if ([s isKindOfClass:[NSString class]]) [allPaths addObject:s];
            }
        }

        // ---- clearData (safe: caches only, keeps login) -------------
        if ([op isEqualToString:@"clearData"]) {
            ZXKillBundle(bundleId);
            NSFileManager *fm = [NSFileManager defaultManager];
            int cleared = 0;
            for (NSString *base in allPaths) {
                for (NSString *sub in @[@"Library/Caches", @"tmp", @"Library/WebKit",
                        @"Library/SplashBoard", @"Library/Caches/WebKit"]) {
                    NSString *dir = [base stringByAppendingPathComponent:sub];
                    BOOL isDir = NO;
                    if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
                    for (NSString *child in [fm contentsOfDirectoryAtPath:dir error:nil]) {
                        if ([fm removeItemAtPath:[dir stringByAppendingPathComponent:child] error:nil]) cleared++;
                    }
                }
            }
            @try {
                [mgr flushCFPrefsdCacheForApplicationWithIdentifier:bundleId];
                [mgr reloadApplicationWithIdentifier:bundleId];
            } @catch (NSException *e) {}
            return ZXReply(@{@"ok": @YES, @"cleared": @(cleared)});
        }

        // ---- size ---------------------------------------------------
        if ([op isEqualToString:@"size"]) {
            __block uint64_t craneTotal = 0;
            dispatch_semaphore_t s = dispatch_semaphore_create(0);
            @try {
                [mgr sizeOccupiedByContainerWithIdentifier:cid ofApplicationWithIdentifier:bundleId
                    completionHandler:^(uint64_t size) {
                        craneTotal = size;
                        dispatch_semaphore_signal(s);
                    }];
                dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)));
            } @catch (NSException *e) {}
            uint64_t caches = 0, webkit = 0, other = 0;
            for (NSString *base in allPaths) {
                for (NSString *sub in @[@"Library/Caches", @"tmp", @"Library/SplashBoard"]) {
                    caches += ZXDirSize([base stringByAppendingPathComponent:sub]);
                }
                webkit += ZXDirSize([base stringByAppendingPathComponent:@"Library/WebKit"]);
                other += ZXDirSize([base stringByAppendingPathComponent:@"Library/Preferences"]);
            }
            uint64_t total = craneTotal ?: (caches + webkit + other);
            return ZXReply(@{@"total": @(total), @"caches": @(caches),
                @"webkit": @(webkit), @"preferences": @(other)});
        }

        // ---- backup -------------------------------------------------
        if ([op isEqualToString:@"backup"]) {
            NSString *prefix = [p objectForKey:@"name"];
            if (![prefix isKindOfClass:[NSString class]] || !prefix.length) prefix = bundleId;
            prefix = [[prefix lastPathComponent] stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            [fmt setDateFormat:@"yyyyMMdd_HHmmss"];
            NSString *fname = [NSString stringWithFormat:@"%@_%@.tar.gz",
                prefix, [fmt stringFromDate:[NSDate date]]];
            NSString *dir = [getDocumentRoot() stringByAppendingPathComponent:@"crane-backups"];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir
                withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *out = [dir stringByAppendingPathComponent:fname];
            NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-czf", out, nil];
            for (NSString *bp in allPaths) {
                // -C / + absolute path keeps tar deterministic for restore.
                [args addObject:@"-C"];
                [args addObject:@"/"];
                NSString *rel = [bp hasPrefix:@"/"] ? [bp substringFromIndex:1] : bp;
                [args addObject:rel];
            }
            if (!ZXRunTar(args, error)) return nil;
            return ZXReply(@{@"ok": @YES, @"path": out});
        }

        // ---- restore ------------------------------------------------
        if ([op isEqualToString:@"restore"]) {
            NSString *backup = [p objectForKey:@"path"];
            if (![backup isKindOfClass:[NSString class]] ||
                    ![[backup pathExtension] isEqualToString:@"gz"] ||
                    ![[NSFileManager defaultManager] fileExistsAtPath:backup]) {
                if (error) *error = ZXErr(@"Backup .tar.gz not found.");
                return nil;
            }
            ZXKillBundle(bundleId);
            if (!ZXRunTar(@[@"-xzf", backup, @"-C", @"/"], error)) return nil;
            @try {
                [mgr flushCFPrefsdCacheForApplicationWithIdentifier:bundleId];
                [mgr reloadApplicationWithIdentifier:bundleId];
            } @catch (NSException *e) {}
            return ZXReply(@{@"ok": @YES});
        }

        if (error) *error = ZXErr(@"Unknown op. Use list|switch|create|delete|wipe|rename|clearData|backup|restore|size.");
        return nil;
    } @catch (NSException *e) {
        NSLog(@"com.zjx.springboard: crane exception: %@", e.reason);
        if (error) *error = ZXErr([NSString stringWithFormat:@"Crane error: %@", e.reason ?: @"exception"]);
        return nil;
    }
}
