#if ZX_DASHBOARD_SPRINGBOARD_SERVER
#import "../../pccontrol/RemoteDashboardServer.h"
#import <sys/socket.h>
#import <sys/time.h>
#import <unistd.h>
#else
#import "RemoteDashboardServer.h"
#endif

#import <arpa/inet.h>
#import <ifaddrs.h>
#import <notify.h>

#import "Config.h"
#if !ZX_DASHBOARD_SPRINGBOARD_SERVER
#import "Socket.h"
#endif
#import "GCDWebServer.h"
#import "GCDWebServerDataRequest.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerFileResponse.h"
#import "GCDWebServerMultiPartFormRequest.h"

static NSString *const ZXDashboardConfigPath = @"/var/mobile/Library/ZXTouch/config/tweak/remote_dashboard.plist";
static NSString *const ZXDashboardEnabledKey = @"enabled";
static NSString *const ZXDashboardTokenKey = @"token";
static const char *ZXDashboardConfigurationNotification = "com.zjx.zxtouch.remote-dashboard-changed";
static const unsigned long long ZXDashboardMaximumAssetSize = 25ULL * 1024ULL * 1024ULL;
static const NSUInteger ZXDashboardMaximumLogLength = 256 * 1024;
static const NSUInteger ZXEditorMaximumCodeLength = 256 * 1024;

static NSString *ZXDashboardIPAddress(void)
{
    struct ifaddrs *interfaces = NULL;
    NSString *address = nil;
    if (getifaddrs(&interfaces) != 0) return nil;

    for (struct ifaddrs *entry = interfaces; entry != NULL; entry = entry->ifa_next) {
        if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET) continue;
        NSString *name = [NSString stringWithUTF8String:entry->ifa_name];
        if (![name isEqualToString:@"en0"] && ![name isEqualToString:@"en1"]) continue;

        char host[INET_ADDRSTRLEN] = {0};
        struct sockaddr_in *ipv4 = (struct sockaddr_in *)entry->ifa_addr;
        if (inet_ntop(AF_INET, &ipv4->sin_addr, host, sizeof(host))) {
            address = [NSString stringWithUTF8String:host];
            break;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

#if ZX_DASHBOARD_SPRINGBOARD_SERVER

@interface ZXRemoteDashboardServer : NSObject
@property(nonatomic, strong) GCDWebServer *server;
@property(nonatomic, copy) NSString *token;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic, copy) NSString *lastAction;
@end

@implementation ZXRemoteDashboardServer

- (instancetype)initWithToken:(NSString *)token
{
    self = [super init];
    if (self) {
        _token = [token copy];
        _lastAction = @"Ready";
    }
    return self;
}

- (BOOL)requestIsAuthorized:(GCDWebServerRequest *)request
{
    // Open LAN dashboard: no pairing token required (ip:8080 works directly).
    // WLAN-only exposure is the safeguard; do not port-forward this port.
    (void)request;
    return YES;
}

- (GCDWebServerDataResponse *)jsonResponse:(NSDictionary *)payload status:(NSInteger)status
{
    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:payload];
    response.statusCode = status;
    return response;
}

- (GCDWebServerDataResponse *)unauthorizedResponse
{
    return [self jsonResponse:@{ @"ok": @NO, @"error": @"Invalid pairing token." } status:403];
}

- (NSString *)bundlePathForRelativePath:(NSString *)relativePath
{
    if (![relativePath isKindOfClass:[NSString class]] || ![relativePath.pathExtension.lowercaseString isEqualToString:@"bdl"]) {
        return nil;
    }

    NSString *root = [SCRIPTS_PATH stringByStandardizingPath];
    NSString *candidate = [[root stringByAppendingPathComponent:relativePath] stringByStandardizingPath];
    NSString *rootPrefix = [root stringByAppendingString:@"/"];
    BOOL isDirectory = NO;
    if (![candidate hasPrefix:rootPrefix] || ![[NSFileManager defaultManager] fileExistsAtPath:candidate isDirectory:&isDirectory] || !isDirectory) {
        return nil;
    }
    return candidate;
}

- (NSArray<NSDictionary *> *)scripts
{
    NSMutableArray<NSDictionary *> *scripts = [NSMutableArray array];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:SCRIPTS_PATH];
    NSString *relativePath = nil;

    while ((relativePath = [enumerator nextObject])) {
        if (![relativePath.pathExtension.lowercaseString isEqualToString:@"bdl"]) continue;
        NSString *bundlePath = [SCRIPTS_PATH stringByAppendingPathComponent:relativePath];
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:bundlePath isDirectory:&isDirectory] || !isDirectory) continue;

        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"info.plist"]];
        NSString *entry = [info[@"Entry"] isKindOfClass:[NSString class]] ? info[@"Entry"] : @"";
        [scripts addObject:@{
            @"path": relativePath,
            @"name": relativePath.lastPathComponent.stringByDeletingPathExtension,
            @"entry": entry,
            @"type": entry.pathExtension.lowercaseString ?: @""
        }];
        [enumerator skipDescendants];
    }
    return [scripts sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
}

- (NSString *)sendSocketCommand:(NSString *)command expectsReply:(BOOL)expectsReply
{
    int socketHandle = socket(AF_INET, SOCK_STREAM, 0);
    if (socketHandle < 0) {
        self.lastError = @"Unable to create a local ZXTouch connection.";
        return @"-1;;ZXTouch service is unavailable.";
    }
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(6000);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    struct timeval timeout = {2, 0};
    setsockopt(socketHandle, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(socketHandle, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    if (connect(socketHandle, (struct sockaddr *)&address, sizeof(address)) != 0) {
        self.lastError = @"Unable to connect to the local ZXTouch service.";
        close(socketHandle);
        return @"-1;;ZXTouch service is unavailable.";
    }
    const char *message = command.UTF8String;
    if (send(socketHandle, message, strlen(message), 0) < 0) {
        self.lastError = @"Unable to send a command to the local ZXTouch service.";
        close(socketHandle);
        return @"-1;;ZXTouch service is unavailable.";
    }
    char buffer[4096] = {0};
    ssize_t length = expectsReply ? recv(socketHandle, buffer, sizeof(buffer) - 1, 0) : 1;
    close(socketHandle);
    NSString *result = expectsReply && length > 0 ? [NSString stringWithUTF8String:buffer] : (expectsReply ? @"" : @"0");
    if (result.length == 0 || [result hasPrefix:@"-1"]) {
        self.lastError = result.length ? result : @"The local ZXTouch service did not return a response.";
    } else {
        self.lastError = @"";
    }
    return result ?: @"";
}

- (NSString *)payloadFromSocketReply:(NSString *)reply
{
    NSString *trimmed = [reply stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [trimmed hasPrefix:@"0;;"] ? [trimmed substringFromIndex:3] : trimmed;
}

- (NSDictionary *)status
{
    NSString *rawSize = [self sendSocketCommand:@"251" expectsReply:YES];
    NSString *rawOrientation = [self sendSocketCommand:@"252" expectsReply:YES];
    NSString *rawBattery = [self sendSocketCommand:@"2531" expectsReply:YES];
    NSString *rawRuntime = [self sendSocketCommand:@"2532" expectsReply:YES];
    // Task 25 (device info) + subtask 30 = name;;systemName;;systemVersion;;model;;vendorID.
    // Model (uname.machine, e.g. iPhone12,8 / iPhone14,6) drives the
    // physical-Home vs swipe-Home detection in the dashboard (Pure-VNC plan).
    NSString *rawDeviceInfo = [self sendSocketCommand:@"2530" expectsReply:YES];
    NSString *size = [self payloadFromSocketReply:rawSize];
    NSString *orientation = [self payloadFromSocketReply:rawOrientation];
    NSString *battery = [self payloadFromSocketReply:rawBattery];
    NSString *runtime = [self payloadFromSocketReply:rawRuntime];
    NSString *deviceInfo = [self payloadFromSocketReply:rawDeviceInfo];
    NSArray *sizeParts = [size componentsSeparatedByString:@";;"];
    NSArray *batteryParts = [battery componentsSeparatedByString:@";;"];
    NSArray *runtimeParts = [runtime componentsSeparatedByString:@";;"];
    NSArray *deviceParts = [deviceInfo componentsSeparatedByString:@";;"];
    return @{
        @"running": @(self.server.running),
        @"serviceOnline": @([rawSize hasPrefix:@"0"]),
        @"port": @(self.server.port),
        @"screen": @{ @"width": sizeParts.count > 0 ? sizeParts[0] : @"", @"height": sizeParts.count > 1 ? sizeParts[1] : @"" },
        @"orientation": orientation ?: @"",
        @"battery": batteryParts.count > 1 ? batteryParts[1] : @"",
        @"foregroundApp": runtimeParts.count > 0 ? runtimeParts[0] : @"",
        @"scriptPlaying": runtimeParts.count > 1 ? @([runtimeParts[1] boolValue]) : @NO,
        @"recording": runtimeParts.count > 2 ? @([runtimeParts[2] boolValue]) : @NO,
        @"deviceName": deviceParts.count > 0 ? deviceParts[0] : @"",
        @"systemName": deviceParts.count > 1 ? deviceParts[1] : @"",
        @"systemVersion": deviceParts.count > 2 ? deviceParts[2] : @"",
        @"model": deviceParts.count > 3 ? deviceParts[3] : @"",
        // TrollVNC endpoints bundled in the same (rootless) .deb.
        // Pure-VNC plan: dashboard embeds noVNC RFB.js and talks here directly.
        @"vnc": @{ @"port": @5901, @"httpPort": @5801 },
        @"lastAction": self.lastAction ?: @"Ready",
        @"lastError": self.lastError ?: @"",
        @"scriptCount": @([self scripts].count)
    };
}

- (NSString *)recentLogs
{
    NSString *logs = [NSString stringWithContentsOfFile:RUNTIME_OUTPUT_PATH encoding:NSUTF8StringEncoding error:nil] ?: @"";
    if (logs.length <= ZXDashboardMaximumLogLength) return logs;
    return [@"[Showing the newest log output.]\n" stringByAppendingString:[logs substringFromIndex:logs.length - ZXDashboardMaximumLogLength]];
}

- (BOOL)isSafeAssetFileName:(NSString *)fileName
{
    if (fileName.length == 0 || [fileName isEqualToString:@"."] || [fileName isEqualToString:@".."] ||
        [fileName rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\"]].location != NSNotFound) {
        return NO;
    }
    return [fileName caseInsensitiveCompare:@"info.plist"] != NSOrderedSame;
}

- (NSString *)dashboardBasePath
{
    // Rootless SpringBoard server. Roothide variant is resolved by the OS
    // jbroot; the dashboard HTML lives next to the bundled noVNC assets at
    // <app>/index.html + <app>/novnc/... so a single .deb carries everything.
    NSString *rootless = @"/var/jb/Applications/zxtouch.app";
    if ([[NSFileManager defaultManager] fileExistsAtPath:[rootless stringByAppendingPathComponent:@"index.html"]]) return rootless;
    return nil;
}

- (NSString *)dashboardHTML
{
    NSString *base = [self dashboardBasePath];
    NSString *path = base ? [base stringByAppendingPathComponent:@"index.html"] : nil;
    NSString *html = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    return html ?: @"<h1>ZXTouch Dashboard is unavailable.</h1>";
}

- (GCDWebServerResponse *)novncFileResponseForRequest:(GCDWebServerRequest *)request
{
    // Serve bundled noVNC assets (./novnc/core/rfb.js, ...) with the same
    // token auth as the dashboard. Rejects ".." to stay inside the app dir.
    NSString *base = [self dashboardBasePath];
    if (!base) return nil;
    NSString *relative = [request.path substringFromIndex:@"/novnc/".length];
    if ([relative rangeOfString:@".."].location != NSNotFound) return nil;
    NSString *candidate = [[base stringByAppendingPathComponent:@"novnc"] stringByAppendingPathComponent:relative];
    if (![[NSFileManager defaultManager] fileExistsAtPath:candidate]) return nil;
    return [GCDWebServerFileResponse responseWithFile:candidate];
}

- (NSString *)editorFrontmostApp
{
    // Task 25/subtask 32 replies "frontmost;;playing;;recording".
    NSString *reply = [self payloadFromSocketReply:[self sendSocketCommand:@"2532" expectsReply:YES]];
    NSArray *parts = [reply componentsSeparatedByString:@";;"];
    NSString *frontmost = parts.count > 0 ? parts[0] : @"";
    return frontmost.length ? frontmost : nil;
}

- (NSString *)writeEditorBundleWithCode:(NSString *)code error:(NSError **)error
{
    // Hidden staging bundle next to the runtime log dir (NOT in the library).
    NSString *bundlePath = [[RUNTIME_OUTPUT_PATH stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"__editor__.bdl"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager createDirectoryAtPath:bundlePath withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }
    // Pin FrontApp so an editor run never yanks the user to another app.
    NSString *frontmost = [self editorFrontmostApp] ?: @"";
    NSDictionary *info = @{ @"Entry": @"entry.py", @"FrontApp": frontmost, @"Orientation": @"1" };
    [info writeToFile:[bundlePath stringByAppendingPathComponent:@"info.plist"] atomically:YES];
    if (![code writeToFile:[bundlePath stringByAppendingPathComponent:@"entry.py"]
                atomically:YES encoding:NSUTF8StringEncoding error:error]) {
        return nil;
    }
    return bundlePath;
}

- (NSString *)sanitizedScriptName:(id)rawName
{
    NSString *name = [[rawName isKindOfClass:[NSString class]] ? rawName : @""
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0 || name.length > 64) return nil;
    if ([name isEqualToString:@"__editor__"]) return nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_.()"];
    if ([name rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return nil;
    if ([name hasPrefix:@"."]) return nil;
    return name;
}

- (void)configureHandlers
{
    __weak typeof(self) weakSelf = self;
    [self.server addHandlerForMethod:@"GET" path:@"/" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        return [GCDWebServerDataResponse responseWithHTML:[strongSelf dashboardHTML]];
    }];

    // Bundled noVNC client (single-.deb plan): ./novnc/** served with token auth.
    // The dashboard loads ./novnc/core/rfb.js from here, then opens a raw
    // WebSocket to the TrollVNC VNC port (:5901/websockify) for stream+input.
    [self.server addHandlerForMethod:@"GET" pathRegex:@"^/novnc/.*" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        GCDWebServerResponse *file = [strongSelf novncFileResponseForRequest:request];
        if (!file) return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"noVNC asset not found. Reinstall the package." } status:404];
        return file;
    }];

    [self.server addHandlerForMethod:@"GET" path:@"/api/scripts" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"scripts": [strongSelf scripts] } status:200];
    }];

    [self.server addHandlerForMethod:@"GET" path:@"/api/status" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"status": [strongSelf status] } status:200];
    }];

    [self.server addHandlerForMethod:@"GET" path:@"/api/logs" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"logs": [strongSelf recentLogs] } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/logs/clear" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        NSError *error = nil;
        [@"" writeToFile:RUNTIME_OUTPUT_PATH atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error) return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": error.localizedDescription ?: @"Unable to clear logs." } status:500];
        strongSelf.lastAction = @"Clear logs";
        return [strongSelf jsonResponse:@{ @"ok": @YES } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/run" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        NSDictionary *body = [request.jsonObject isKindOfClass:[NSDictionary class]] ? request.jsonObject : @{};
        NSString *bundlePath = [strongSelf bundlePathForRelativePath:body[@"path"]];
        if (!bundlePath) return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Script was not found." } status:404];
        NSString *result = [strongSelf sendSocketCommand:[@"19" stringByAppendingString:bundlePath] expectsReply:YES];
        strongSelf.lastAction = [NSString stringWithFormat:@"Run %@", bundlePath.lastPathComponent];
        return [strongSelf jsonResponse:@{ @"ok": @([result hasPrefix:@"0"]), @"result": result ?: @"" } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/stop" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        NSString *result = [strongSelf sendSocketCommand:@"20" expectsReply:YES];
        strongSelf.lastAction = @"Stop script";
        return [strongSelf jsonResponse:@{ @"ok": @([result hasPrefix:@"0"]), @"result": result ?: @"" } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/record/start" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        NSString *result = [strongSelf sendSocketCommand:@"14" expectsReply:YES];
        strongSelf.lastAction = @"Start recording";
        return [strongSelf jsonResponse:@{ @"ok": @(![result hasPrefix:@"-1"]), @"result": result ?: @"" } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/record/stop" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        NSString *result = [strongSelf sendSocketCommand:@"15" expectsReply:YES];
        strongSelf.lastAction = @"Stop recording";
        return [strongSelf jsonResponse:@{ @"ok": @([result hasPrefix:@"0"]), @"result": result ?: @"" } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/assets" requestClass:[GCDWebServerMultiPartFormRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerMultiPartFormRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        NSString *relativePath = [[request firstArgumentForControlName:@"script"] string];
        NSString *bundlePath = [strongSelf bundlePathForRelativePath:relativePath];
        GCDWebServerMultiPartFile *upload = [request firstFileForControlName:@"asset"];
        NSString *fileName = upload.fileName.lastPathComponent;
        NSDictionary *attributes = upload.temporaryPath.length ? [[NSFileManager defaultManager] attributesOfItemAtPath:upload.temporaryPath error:nil] : nil;
        unsigned long long size = [attributes fileSize];
        if (!bundlePath || upload == nil || ![strongSelf isSafeAssetFileName:fileName]) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Choose a script and an asset file." } status:400];
        }
        if (size > ZXDashboardMaximumAssetSize) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Assets must be 25 MB or smaller." } status:413];
        }
        NSString *destination = [bundlePath stringByAppendingPathComponent:fileName];
        [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
        NSError *error = nil;
        BOOL copied = [[NSFileManager defaultManager] copyItemAtPath:upload.temporaryPath toPath:destination error:&error];
        if (!copied) return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": error.localizedDescription ?: @"Unable to save asset." } status:500];
        strongSelf.lastAction = [NSString stringWithFormat:@"Upload %@", fileName];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"file": fileName } status:200];
    }];

    [self.server addHandlerForMethod:@"GET" path:@"/api/download" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        NSString *bundlePath = [strongSelf bundlePathForRelativePath:request.query[@"path"]];
        NSString *entry = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"info.plist"]][@"Entry"];
        NSString *entryPath = entry.length ? [bundlePath stringByAppendingPathComponent:entry] : nil;
        if (!entryPath || ![[NSFileManager defaultManager] fileExistsAtPath:entryPath]) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Script entry was not found." } status:404];
        }
        return [GCDWebServerFileResponse responseWithFile:entryPath isAttachment:YES];
    }];

    // ── Editor tab: ad-hoc write/run/save/load ──────────────────────
    // POST /api/editor/run {code} — writes a hidden __editor__.bdl bundle
    // (outside SCRIPTS_PATH so quick runs don't pollute the library) and
    // plays it immediately. FrontApp is pinned to the currently frontmost
    // app so the run doesn't yank the user elsewhere.
    [self.server addHandlerForMethod:@"POST" path:@"/api/editor/run" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        NSDictionary *body = [((GCDWebServerDataRequest *)request).jsonObject isKindOfClass:[NSDictionary class]] ? ((GCDWebServerDataRequest *)request).jsonObject : @{};
        NSString *code = [body[@"code"] isKindOfClass:[NSString class]] ? body[@"code"] : @"";
        if (code.length == 0) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Code is empty." } status:400];
        }
        if (code.length > ZXEditorMaximumCodeLength) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Code is too large (256 KB max)." } status:413];
        }
        NSError *error = nil;
        NSString *bundlePath = [strongSelf writeEditorBundleWithCode:code error:&error];
        if (!bundlePath) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": error.localizedDescription ?: @"Unable to stage editor script." } status:500];
        }
        // Byte offset BEFORE the run so the Editor tab can poll ONLY this
        // run's output (script prints, not older system/log lines).
        unsigned long long logOffset = [[[NSFileManager defaultManager] attributesOfItemAtPath:RUNTIME_OUTPUT_PATH error:nil] fileSize];
        NSString *result = [strongSelf sendSocketCommand:[@"19" stringByAppendingString:bundlePath] expectsReply:YES];
        strongSelf.lastAction = @"Editor run";
        return [strongSelf jsonResponse:@{ @"ok": @([result hasPrefix:@"0"]), @"result": result ?: @"", @"logOffset": @(logOffset) } status:200];
    }];

    // GET /api/editor/logs?since=<bytes> — bytes appended to the runtime
    // log since the offset (returned by /api/editor/run). Editor tab polls
    // this while its script runs and appends to its own pane (accumulates
    // across runs, never auto-cleared). Capped per poll to bound memory.
    [self.server addHandlerForMethod:@"GET" path:@"/api/editor/logs" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        unsigned long long since = (unsigned long long)[request.query[@"since"] longLongValue];
        unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:RUNTIME_OUTPUT_PATH error:nil] fileSize];
        if (since > size) since = 0; // log rotated/cleared meanwhile — restart from head
        NSString *text = @"";
        if (size > since) {
            NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:RUNTIME_OUTPUT_PATH];
            @try {
                [handle seekToFileOffset:since];
                NSData *data = [handle readDataOfLength:(NSUInteger)MIN(size - since, 65536)];
                // Advance by raw bytes (not string length) so a multi-byte
                // char split across polls is re-read, never skipped.
                since += data.length;
                text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
            } @catch (NSException *e) {
                return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Unable to read logs." } status:500];
            } @finally {
                [handle closeFile];
            }
        }
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"logs": text, @"offset": @(since) } status:200];
    }];

    // GET /api/editor/load?path=<rel.bdl> — read a library entry as text.
    [self.server addHandlerForMethod:@"GET" path:@"/api/editor/load" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        NSString *bundlePath = [strongSelf bundlePathForRelativePath:request.query[@"path"]];
        NSString *entry = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"info.plist"]][@"Entry"];
        NSString *entryPath = entry.length ? [bundlePath stringByAppendingPathComponent:entry] : nil;
        if (!entryPath || ![[NSFileManager defaultManager] fileExistsAtPath:entryPath]) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Script entry was not found." } status:404];
        }
        NSError *error = nil;
        NSString *code = [NSString stringWithContentsOfFile:entryPath encoding:NSUTF8StringEncoding error:&error];
        if (!code) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": error.localizedDescription ?: @"Unable to read script." } status:500];
        }
        if (code.length > ZXEditorMaximumCodeLength) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Script is too large to edit (256 KB max)." } status:413];
        }
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"name": bundlePath.lastPathComponent.stringByDeletingPathExtension, @"entry": entry, @"code": code } status:200];
    }];

    // POST /api/editor/save {path?, name?, code} — overwrite a bundle entry
    // or create "<name>.bdl". Never touches info.plist of existing bundles.
    [self.server addHandlerForMethod:@"POST" path:@"/api/editor/save" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf requestIsAuthorized:request]) return [strongSelf unauthorizedResponse];
        NSDictionary *body = [((GCDWebServerDataRequest *)request).jsonObject isKindOfClass:[NSDictionary class]] ? ((GCDWebServerDataRequest *)request).jsonObject : @{};
        NSString *code = [body[@"code"] isKindOfClass:[NSString class]] ? body[@"code"] : @"";
        if (code.length == 0) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Code is empty." } status:400];
        }
        if (code.length > ZXEditorMaximumCodeLength) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Code is too large (256 KB max)." } status:413];
        }
        NSString *bundlePath = [strongSelf bundlePathForRelativePath:body[@"path"]];
        NSString *relativePath = nil;
        if (bundlePath) {
            NSString *entry = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"info.plist"]][@"Entry"];
            if (![entry isKindOfClass:[NSString class]] || !entry.length) {
                return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Bundle has no editable entry." } status:400];
            }
            NSError *error = nil;
            if (![code writeToFile:[bundlePath stringByAppendingPathComponent:entry] atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
                return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": error.localizedDescription ?: @"Unable to save script." } status:500];
            }
            relativePath = body[@"path"];
        } else {
            NSString *name = [strongSelf sanitizedScriptName:body[@"name"]];
            if (!name) {
                return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Give the script a name (letters, numbers, space, - _ .)." } status:400];
            }
            relativePath = [name stringByAppendingPathExtension:@"bdl"];
            NSString *newBundle = [[SCRIPTS_PATH stringByStandardizingPath] stringByAppendingPathComponent:relativePath];
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:newBundle withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": error.localizedDescription ?: @"Unable to create script." } status:500];
            }
            if (![[NSFileManager defaultManager] fileExistsAtPath:[newBundle stringByAppendingPathComponent:@"info.plist"]]) {
                NSDictionary *info = @{ @"Entry": @"entry.py", @"FrontApp": [strongSelf editorFrontmostApp] ?: @"", @"Orientation": @"1" };
                [info writeToFile:[newBundle stringByAppendingPathComponent:@"info.plist"] atomically:YES];
            }
            NSString *entry = [NSDictionary dictionaryWithContentsOfFile:[newBundle stringByAppendingPathComponent:@"info.plist"]][@"Entry"];
            if (![entry isKindOfClass:[NSString class]] || !entry.length) entry = @"entry.py";
            if (![code writeToFile:[newBundle stringByAppendingPathComponent:entry] atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
                return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": error.localizedDescription ?: @"Unable to save script." } status:500];
            }
        }
        strongSelf.lastAction = [NSString stringWithFormat:@"Editor save %@", relativePath.lastPathComponent];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"path": relativePath } status:200];
    }];
}

- (BOOL)start
{
    if (self.server.running) return YES;
    self.server = [[GCDWebServer alloc] init];
    [self configureHandlers];
    NSError *error = nil;
    BOOL started = [self.server startWithOptions:@{
        GCDWebServerOption_Port: @8080,
        GCDWebServerOption_ServerName: @"ZXTouch Dashboard",
        GCDWebServerOption_AutomaticallySuspendInBackground: @NO
    } error:&error];
    self.lastError = started ? @"" : (error.localizedDescription ?: @"Unable to start dashboard.");
    if (!started) self.server = nil;
    return started;
}

- (void)stop
{
    [self.server stop];
    self.server = nil;
}

@end

static ZXRemoteDashboardServer *ZXDashboardServer;

void ZXDashboardReloadConfiguration(void)
{
    NSDictionary *configuration = [NSDictionary dictionaryWithContentsOfFile:ZXDashboardConfigPath];
    if (![configuration isKindOfClass:[NSDictionary class]]) {
        NSDictionary *legacy = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.zjx.zxtouch.plist"];
        NSMutableDictionary *migrated = [NSMutableDictionary dictionary];
        id legacyEnabled = legacy[@"zxtouch_remote_dashboard_enabled"];
        NSString *legacyToken = [legacy[@"zxtouch_remote_dashboard_token"] isKindOfClass:[NSString class]] ? legacy[@"zxtouch_remote_dashboard_token"] : @"";
        if (legacyEnabled) migrated[ZXDashboardEnabledKey] = legacyEnabled;
        if (legacyToken.length) migrated[ZXDashboardTokenKey] = legacyToken;
        if (migrated.count) [migrated writeToFile:ZXDashboardConfigPath atomically:YES];
        configuration = migrated;
    }
    BOOL enabled = [configuration[ZXDashboardEnabledKey] boolValue];
    NSString *token = [configuration[ZXDashboardTokenKey] isKindOfClass:[NSString class]] ? configuration[ZXDashboardTokenKey] : @"";
    (void)token; // kept for config compat; auth is open (see requestIsAuthorized:)
    if (!enabled) {
        [ZXDashboardServer stop];
        ZXDashboardServer = nil;
        return;
    }
    if (ZXDashboardServer && ![ZXDashboardServer.token isEqualToString:token]) {
        [ZXDashboardServer stop];
        ZXDashboardServer = nil;
    }
    if (!ZXDashboardServer) ZXDashboardServer = [[ZXRemoteDashboardServer alloc] initWithToken:token];
    [ZXDashboardServer start];
}

#else

static NSString *ZXDashboardSettingsLastError = @"";

static NSMutableDictionary *ZXDashboardConfiguration(void)
{
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:ZXDashboardConfigPath];
    if ([stored isKindOfClass:[NSDictionary class]]) return [stored mutableCopy];

    NSMutableDictionary *configuration = [NSMutableDictionary dictionary];
    NSUserDefaults *legacyDefaults = [NSUserDefaults standardUserDefaults];
    id legacyEnabled = [legacyDefaults objectForKey:@"zxtouch_remote_dashboard_enabled"];
    NSString *legacyToken = [legacyDefaults stringForKey:@"zxtouch_remote_dashboard_token"];
    if (legacyEnabled) configuration[ZXDashboardEnabledKey] = legacyEnabled;
    if (legacyToken.length) configuration[ZXDashboardTokenKey] = legacyToken;
    return configuration;
}

static NSString *ZXDashboardToken(NSMutableDictionary *configuration)
{
    NSString *token = [configuration[ZXDashboardTokenKey] isKindOfClass:[NSString class]] ? configuration[ZXDashboardTokenKey] : @"";
    if (token.length == 0) {
        token = [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
        configuration[ZXDashboardTokenKey] = token;
    }
    return token;
}

BOOL ZXRemoteDashboardSetEnabled(BOOL enabled)
{
    NSMutableDictionary *configuration = ZXDashboardConfiguration();
    ZXDashboardToken(configuration);
    configuration[ZXDashboardEnabledKey] = @(enabled);
    NSError *directoryError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[ZXDashboardConfigPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&directoryError];
    BOOL saved = directoryError == nil && [configuration writeToFile:ZXDashboardConfigPath atomically:YES];
    ZXDashboardSettingsLastError = saved ? @"" : (directoryError.localizedDescription ?: @"Unable to save Remote Dashboard settings.");
    if (saved) notify_post(ZXDashboardConfigurationNotification);
    return saved;
}

BOOL ZXRemoteDashboardIsEnabled(void)
{
    return [ZXDashboardConfiguration()[ZXDashboardEnabledKey] boolValue];
}

NSString *ZXRemoteDashboardURL(void)
{
    NSMutableDictionary *configuration = ZXDashboardConfiguration();
    NSString *token = ZXDashboardToken(configuration);
    NSString *host = ZXDashboardIPAddress() ?: @"iPad-IP-address";
    return [NSString stringWithFormat:@"http://%@:%d/?token=%@", host, 8080, token];
}

NSString *ZXRemoteDashboardLastError(void)
{
    return ZXDashboardSettingsLastError ?: @"";
}

#endif
