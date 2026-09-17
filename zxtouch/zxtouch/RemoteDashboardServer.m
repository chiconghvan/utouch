#if ZX_DASHBOARD_SPRINGBOARD_SERVER
#import "../../pccontrol/RemoteDashboardServer.h"
#import <sys/socket.h>
#import <sys/time.h>
#import <sys/sysctl.h>
#import <signal.h>
#import <unistd.h>
#else
#import "RemoteDashboardServer.h"
#endif

#import <arpa/inet.h>
#import <errno.h>
#import <ifaddrs.h>
#import <sys/socket.h>
#import <notify.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <execinfo.h>
#import <fcntl.h>
#import <mach/mach.h>
#import <mach/vm_statistics.h>
#import <signal.h>
#import <spawn.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/file.h>
#import <sys/resource.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/wait.h>
#import <unistd.h>
extern char **environ;

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
static const char *ZXDashboardConfigurationNotification = "com.zjx.zxtouch.remote-dashboard-changed";
static const unsigned long long ZXDashboardMaximumAssetSize = 25ULL * 1024ULL * 1024ULL;
static const NSUInteger ZXDashboardMaximumLogLength = 256 * 1024;
static const NSUInteger ZXEditorMaximumCodeLength = 256 * 1024;
static NSString *const ZXVNCEnabledKey = @"vnc_server_enabled";
static const NSTimeInterval ZXDashboardStatusCacheTTL = 2.0;
static const NSTimeInterval ZXVNCRecoverCooldown = 30.0;
// Two hosts serve the same dashboard, so they must never share a port: the
// standalone daemon (zxtouch-dashboardd, the intended owner and the address
// Settings advertises) and the SpringBoard-embedded fallback. ZX_DASHBOARD_DAEMON
// selects the host at compile time, so every ZXDashboardPort call site below
// stays correct per binary while the Settings build can still name both.
enum { ZXDashboardDaemonPort = 8688, ZXDashboardFallbackPort = 8689 };
#if ZX_DASHBOARD_DAEMON
#define ZXDashboardPort ZXDashboardDaemonPort
#else
#define ZXDashboardPort ZXDashboardFallbackPort
#endif

// Liveness check for an HTTP port that does NOT open a connection. A bare
// connect+close (what ZXVNCProbePort does, which is fine for the VNC ports)
// makes the server that owns the port read EOF before any header arrived, and
// it logs that as a 500 "(invalid request)" — once per probe. bind() instead
// never touches the owner: it fails with EADDRINUSE as soon as a live listener
// holds the port.
//
// SO_REUSEADDR mirrors what GCDWebServer itself passes before its own bind
// (GCDWebServer.m `_createListeningSocket:`), so this answer is exactly the one
// our server would get: leftover TIME_WAIT sockets from previous connections do
// not count as taken, while a second live listener can never bind.
static BOOL ZXDashboardPortIsTaken(uint16_t port)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    int reuse = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    BOOL bound = bind(fd, (struct sockaddr *)&address, sizeof(address)) == 0;
    close(fd);
    return !bound;
}

// ── VNC choice parking ───────────────────────────────────────────────────
// Dashboard OFF forces vnc_server_enabled=NO so an open web page cannot keep
// streaming the screen. The user's real choice is parked on that ON→OFF edge,
// so turning the dashboard back on restores it instead of leaving VNC dead
// until Settings is opened again.
static NSString *const ZXVNCParkedKey = @"vnc_server_enabled_parked";

static void ZXVNCWriteDashboardConfiguration(NSDictionary *configuration)
{
    [[NSFileManager defaultManager] createDirectoryAtPath:[ZXDashboardConfigPath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [configuration writeToFile:ZXDashboardConfigPath atomically:YES];
}

// Returns YES when the dictionary changed, so callers write only on a real edge.
static BOOL ZXVNCParkAndForceDisabledIn(NSMutableDictionary *configuration)
{
    if (configuration[ZXVNCEnabledKey] != nil && [configuration[ZXVNCEnabledKey] boolValue] == NO) return NO;
    configuration[ZXVNCParkedKey] = configuration[ZXVNCEnabledKey] == nil ? @YES : configuration[ZXVNCEnabledKey];
    configuration[ZXVNCEnabledKey] = @NO;
    return YES;
}

static void ZXVNCRestoreParkedIn(NSMutableDictionary *configuration)
{
    id parked = configuration[ZXVNCParkedKey];
    if (parked == nil) return;
    configuration[ZXVNCEnabledKey] = @([parked boolValue]);
    [configuration removeObjectForKey:ZXVNCParkedKey];
}

// Used by the two supervised hosts right before they read the VNC switch.
static BOOL ZXVNCRestoreParkedChoice(void)
{
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:ZXDashboardConfigPath];
    if (stored[ZXVNCParkedKey] == nil) return NO;
    NSMutableDictionary *configuration = [stored mutableCopy];
    ZXVNCRestoreParkedIn(configuration);
    ZXVNCWriteDashboardConfiguration(configuration);
    return YES;
}

#if ZX_DASHBOARD_SPRINGBOARD_SERVER
static void ZXVNCkillServer(void);
static void ZXVNCStartServerDirectly(void);
static BOOL ZXVNCProbePort(uint16_t port);
static BOOL ZXDashboardDaemonEnabled(void);

// ── Dashboard debug log ───────────────────────────────────────────────────
// A file logger written by the server itself instead of launchd: the fallback
// server that runs inside SpringBoard has no stdout redirection, so a crash
// there would otherwise leave nothing behind. Both hosts run as `mobile` and
// open the file with O_APPEND, so their lines never overwrite each other.
static int ZXDashboardDebugLogFD = -1;
static const unsigned long long ZXDashboardDebugLogMaximumBytes = 2ULL * 1024ULL * 1024ULL;

static void ZXDashboardDebugLogRaw(const char *bytes, size_t length)
{
    if (ZXDashboardDebugLogFD < 0 || bytes == NULL || length == 0) return;
    ssize_t written = write(ZXDashboardDebugLogFD, bytes, length);
    (void)written;
}

static void ZXDashboardDebugLog(NSString *format, ...)
{
    if (ZXDashboardDebugLogFD < 0) return;
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSString *line = [NSString stringWithFormat:@"%@ [pid=%d] %@\n", [NSDate date], getpid(), message ?: @""];
    ZXDashboardDebugLogRaw(line.UTF8String, strlen(line.UTF8String));
    NSLog(@"[dashboard-debug] %@", message ?: @"");
}

static NSString *ZXDashboardDebugLogTail(void)
{
    NSString *log = [NSString stringWithContentsOfFile:ZX_DASHBOARD_DEBUG_LOG_PATH encoding:NSUTF8StringEncoding error:nil] ?: @"";
    if (log.length <= ZXDashboardMaximumLogLength) return log;
    return [@"[Showing the newest debug output.]\n" stringByAppendingString:
            [log substringFromIndex:log.length - ZXDashboardMaximumLogLength]];
}

static void ZXDashboardDebugLogClear(void)
{
    if (ZXDashboardDebugLogFD < 0) return;
    ftruncate(ZXDashboardDebugLogFD, 0);
    ZXDashboardDebugLog(@"===== cleared pid=%d =====", getpid());
}

// ── Hardware snapshot ─────────────────────────────────────────────────────
// Taken at session start and again right before the process dies, so an
// out-of-memory or a runaway-CPU crash is visible from the log alone. The raw
// variant sticks to syscalls and mach traps to stay async-signal-safe.
static double ZXDashboardSessionStartCPU = 0.0;
static unsigned long long ZXDashboardSessionStartUptimeMS = 0;

static double ZXDashboardProcessCPUSeconds(void)
{
    struct rusage usage;
    memset(&usage, 0, sizeof(usage));
    if (getrusage(RUSAGE_SELF, &usage) != 0) return 0.0;
    return (double)usage.ru_utime.tv_sec + (double)usage.ru_utime.tv_usec / 1000000.0 +
           (double)usage.ru_stime.tv_sec + (double)usage.ru_stime.tv_usec / 1000000.0;
}

static unsigned long long ZXDashboardSystemUptimeMilliseconds(void)
{
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    struct timeval boot;
    size_t size = sizeof(boot);
    if (sysctl(mib, 2, &boot, &size, NULL, 0) != 0) return 0;
    struct timeval now;
    gettimeofday(&now, NULL);
    long long milliseconds = ((long long)now.tv_sec - (long long)boot.tv_sec) * 1000LL +
                             ((long long)now.tv_usec - (long long)boot.tv_usec) / 1000LL;
    return milliseconds > 0 ? (unsigned long long)milliseconds : 0;
}

static void ZXDashboardHardwareSnapshotRaw(const char *label)
{
    if (ZXDashboardDebugLogFD < 0) return;

    struct rusage usage;
    memset(&usage, 0, sizeof(usage));
    getrusage(RUSAGE_SELF, &usage);
    double cpuSeconds = ZXDashboardProcessCPUSeconds();
    unsigned long long uptimeMS = ZXDashboardSystemUptimeMilliseconds();
    double cpuPercent = 0.0;
    if (ZXDashboardSessionStartUptimeMS && uptimeMS > ZXDashboardSessionStartUptimeMS) {
        cpuPercent = (cpuSeconds - ZXDashboardSessionStartCPU) * 100000.0 /
                     (double)(uptimeMS - ZXDashboardSessionStartUptimeMS);
    }

    struct mach_task_basic_info taskInfo;
    memset(&taskInfo, 0, sizeof(taskInfo));
    mach_msg_type_number_t taskInfoCount = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t taskResult = task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                                         (task_info_t)&taskInfo, &taskInfoCount);
    unsigned long long residentBytes = taskResult == KERN_SUCCESS ? (unsigned long long)taskInfo.resident_size : 0;
    unsigned long long virtualBytes = taskResult == KERN_SUCCESS ? (unsigned long long)taskInfo.virtual_size : 0;

    unsigned int threadCount = 0;
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t threadArrayCount = 0;
    if (task_threads(mach_task_self(), &threads, &threadArrayCount) == KERN_SUCCESS && threads) {
        threadCount = (unsigned int)threadArrayCount;
        for (mach_msg_type_number_t index = 0; index < threadArrayCount; index++) {
            mach_port_deallocate(mach_task_self(), threads[index]);
        }
        vm_deallocate(mach_task_self(), (vm_address_t)threads, threadArrayCount * sizeof(thread_t));
    }

    vm_size_t pageSize = 0;
    host_page_size(mach_host_self(), &pageSize);
    vm_statistics64_data_t vmStats;
    memset(&vmStats, 0, sizeof(vmStats));
    mach_msg_type_number_t vmCount = HOST_VM_INFO64_COUNT;
    double freeMB = 0.0;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vmStats, &vmCount) == KERN_SUCCESS) {
        freeMB = (double)vmStats.free_count * (double)pageSize / 1048576.0;
    }

    char line[512];
    int length = snprintf(line, sizeof(line),
        "[hwinfo] %s pid=%d threads=%u rss=%.1fMB vsize=%.1fMB cpu=%.1f%% "
        "(user=%.2fs sys=%.2fs) uptime=%.1fs free=%.1fMB maxrss=%.1fMB faults=%ld\n",
        label, getpid(), threadCount,
        (double)residentBytes / 1048576.0, (double)virtualBytes / 1048576.0, cpuPercent,
        (double)usage.ru_utime.tv_sec + (double)usage.ru_utime.tv_usec / 1000000.0,
        (double)usage.ru_stime.tv_sec + (double)usage.ru_stime.tv_usec / 1000000.0,
        (double)uptimeMS / 1000.0, freeMB,
        (double)usage.ru_maxrss / 1048576.0, (long)usage.ru_majflt);
    if (length > 0) ZXDashboardDebugLogRaw(line, MIN((size_t)length, sizeof(line) - 1));
}

// Adds the values that need ObjC (thermal state, low power, processor counts),
// so it may only be called from a normal context, never from a signal handler.
static void ZXDashboardHardwareSnapshotRich(NSString *label)
{
    ZXDashboardHardwareSnapshotRaw(label.UTF8String ?: "snapshot");
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    NSArray<NSString *> *thermalNames = @[@"nominal", @"fair", @"serious", @"critical"];
    NSUInteger thermalIndex = MIN((NSUInteger)processInfo.thermalState, thermalNames.count - 1);
    ZXDashboardDebugLog(@"[hwinfo] %@ thermal=%@ lowPower=%d processors=%lu/%lu physical=%.0fMB",
                        label, thermalNames[thermalIndex], (int)processInfo.lowPowerModeEnabled,
                        (unsigned long)processInfo.processorCount,
                        (unsigned long)processInfo.activeProcessorCount,
                        (double)processInfo.physicalMemory / 1048576.0);
}

// A run is clean only when its last session marker is session-close. Anything
// appended after it (postinst markers, another daemon's lines) is irrelevant,
// and a tail that ends on session-open means the process died without
// unwinding — a crash or a hard kill, never a normal stop.
static BOOL ZXDashboardDebugLogPreviousSessionWasClean(void)
{
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:ZX_DASHBOARD_DEBUG_LOG_PATH];
    if (!handle) return YES;
    @try {
        unsigned long long size = [handle seekToEndOfFile];
        [handle seekToFileOffset:size > 4096 ? size - 4096 : 0];
        NSString *text = [[NSString alloc] initWithData:[handle readDataToEndOfFile] encoding:NSUTF8StringEncoding] ?: @"";
        NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
        for (NSInteger index = (NSInteger)lines.count - 1; index >= 0; index--) {
            NSString *line = [lines[index] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([line containsString:@"session-close"]) return YES;
            if ([line containsString:@"session-open"]) return NO;
        }
        return YES;
    } @finally {
        [handle closeFile];
    }
}

static void ZXDashboardDebugLogInstall(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager createDirectoryAtPath:[ZX_DASHBOARD_DEBUG_LOG_PATH stringByDeletingLastPathComponent]
                   withIntermediateDirectories:YES attributes:nil error:nil];
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:ZX_DASHBOARD_DEBUG_LOG_PATH error:nil];
        if ([attributes fileSize] > ZXDashboardDebugLogMaximumBytes) {
            [fileManager removeItemAtPath:ZX_DASHBOARD_DEBUG_LOG_PATH error:nil];
        }
        BOOL uncleanShutdown = !ZXDashboardDebugLogPreviousSessionWasClean();

        ZXDashboardDebugLogFD = open(ZX_DASHBOARD_DEBUG_LOG_PATH.fileSystemRepresentation,
                                     O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (ZXDashboardDebugLogFD < 0) return;

        ZXDashboardSessionStartCPU = ZXDashboardProcessCPUSeconds();
        ZXDashboardSessionStartUptimeMS = ZXDashboardSystemUptimeMilliseconds();

        ZXDashboardDebugLog(@"===== session-open pid=%d uptime=%.0fs =====", getpid(),
                            [NSProcessInfo processInfo].systemUptime);
        ZXDashboardHardwareSnapshotRich(@"session-start");
        if (uncleanShutdown) {
            ZXDashboardDebugLog(@"previous session did not shut down cleanly (crash or kill)");
        }
    });
}

// ── Crash capture ─────────────────────────────────────────────────────────
// Writes the faulting signal plus a backtrace to the debug log, then lets the
// process die its normal death: the handler restores SIG_DFL and re-raises, so
// the OS crash reporter still records the crash. Only async-signal-safe calls
// are used here — no ObjC, no allocation.
static const char *ZXDashboardSignalName(int signalNumber)
{
    switch (signalNumber) {
        case SIGSEGV: return "SIGSEGV";
        case SIGABRT: return "SIGABRT";
        case SIGBUS:  return "SIGBUS";
        case SIGILL:  return "SIGILL";
        case SIGFPE:  return "SIGFPE";
        default:      return "signal";
    }
}

static void ZXDashboardCrashSignalHandler(int signalNumber)
{
    char header[128];
    int length = snprintf(header, sizeof(header), "\n*** CRASH %s (%d) pid=%d ***\n",
                          ZXDashboardSignalName(signalNumber), signalNumber, getpid());
    if (length > 0) ZXDashboardDebugLogRaw(header, MIN((size_t)length, sizeof(header) - 1));
    ZXDashboardHardwareSnapshotRaw("crash");
    if (ZXDashboardDebugLogFD >= 0) {
        void *frames[64];
        int frameCount = backtrace(frames, 64);
        backtrace_symbols_fd(frames, frameCount, ZXDashboardDebugLogFD);
    }
    signal(signalNumber, SIG_DFL);
    raise(signalNumber);
}

static NSUncaughtExceptionHandler *ZXDashboardPreviousExceptionHandler = NULL;

static void ZXDashboardUncaughtExceptionHandler(NSException *exception)
{
    @try {
        ZXDashboardDebugLog(@"*** CRASH uncaught exception %@: %@", exception.name, exception.reason);
        for (NSString *symbol in exception.callStackSymbols) {
            ZXDashboardDebugLog(@"[exception] %@", symbol);
        }
        ZXDashboardHardwareSnapshotRich(@"exception");
    } @catch (__unused NSException *ignored) {
    }
    if (ZXDashboardPreviousExceptionHandler) ZXDashboardPreviousExceptionHandler(exception);
}

static void ZXDashboardCrashHandlersInstall(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ZXDashboardDebugLogInstall();
        ZXDashboardPreviousExceptionHandler = NSGetUncaughtExceptionHandler();
        NSSetUncaughtExceptionHandler(&ZXDashboardUncaughtExceptionHandler);
        const int signals[] = {SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE};
        struct sigaction action;
        memset(&action, 0, sizeof(action));
        action.sa_handler = ZXDashboardCrashSignalHandler;
        sigemptyset(&action.sa_mask);
        action.sa_flags = SA_RESETHAND;
        for (size_t index = 0; index < sizeof(signals) / sizeof(signals[0]); index++) {
            sigaction(signals[index], &action, NULL);
        }
    });
}

// The daemon is stopped by launchd with SIGTERM on unload and on every package
// upgrade, so it writes the clean-shutdown marker itself. Without this, a normal
// unload would look identical to a crash to the next session.
static void ZXDashboardDaemonTerminationHandler(int signalNumber)
{
    char line[128];
    int length = snprintf(line, sizeof(line), "===== session-close pid=%d (signal %d) =====\n",
                          getpid(), signalNumber);
    if (length > 0) ZXDashboardDebugLogRaw(line, MIN((size_t)length, sizeof(line) - 1));
    _exit(0);
}

static void ZXDashboardDaemonTerminationInstall(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        struct sigaction action;
        memset(&action, 0, sizeof(action));
        action.sa_handler = ZXDashboardDaemonTerminationHandler;
        sigemptyset(&action.sa_mask);
        sigaction(SIGTERM, &action, NULL);
        sigaction(SIGINT, &action, NULL);
    });
}

// ── dashboard port liveness watchdog ─────────────────────────────────────
// Logs every transition of the port so a dropped dashboard is timestamped even
// when the process that served it died without a chance to log anything.
static void ZXDashboardWatchdogStart(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ZXDashboardDebugLogInstall();
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                         dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        if (!timer) return;
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                                  3 * NSEC_PER_SEC, 500 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(timer, ^{
            static BOOL lastOpen = YES;
            BOOL open = ZXDashboardPortIsTaken(ZXDashboardPort);
            if (open != lastOpen) {
                ZXDashboardDebugLog(@"[watchdog] :%d %@", ZXDashboardPort, open ? @"came up" : @"went down");
                if (!open) ZXDashboardHardwareSnapshotRich(@"watchdog");
                lastOpen = open;
            }
        });
        dispatch_resume(timer);
    });
}

static BOOL ZXVNCIsEnabled(void)
{
    NSDictionary *configuration = [NSDictionary dictionaryWithContentsOfFile:ZXDashboardConfigPath];
    id value = configuration[ZXVNCEnabledKey];
    return value == nil ? YES : [value boolValue];
}

// Roothide has no fixed /var/jb prefix: postinst rewrites the bundled plist
// via `jbroot` to the live prefix. Resolve it shell-less (no /bin/sh).
static NSString *ZXJbrootPrefix(void)
{
    static NSString *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        // Fast path rootless: stock /var/jb layout.
        if ([fm fileExistsAtPath:@"/var/jb/Library/LaunchDaemons/com.zjx.trollvnc.plist"] ||
            [fm fileExistsAtPath:@"/var/jb/usr/bin/trollvncserver"]) {
            cached = @"/var/jb";
            return;
        }
        // /var/jb is a symlink on some roothide setups — realpath() reveals it.
        char resolved[1024];
        if (realpath("/var/jb", resolved) != NULL) {
            NSString *p = [NSString stringWithUTF8String:resolved];
            if (p.length > 1 &&
                [fm fileExistsAtPath:[p stringByAppendingPathComponent:@"Library/LaunchDaemons/com.zjx.trollvnc.plist"]]) {
                cached = [p copy];
                return;
            }
        }
        // Ask the jbroot helper itself (roothide postinst uses `jbroot` bare).
        // Spawn absolute candidates shell-less and capture stdout via pipe.
        static const char * const jbBinaries[] = {
            "/var/jb/usr/bin/jbroot",
            "/usr/bin/jbroot",
            "/bin/jbroot",
            NULL
        };
        for (int i = 0; jbBinaries[i]; i++) {
            if (access(jbBinaries[i], X_OK) != 0) continue;
            int out[2] = {-1, -1};
            if (pipe(out) != 0) continue;
            posix_spawn_file_actions_t actions;
            posix_spawn_file_actions_init(&actions);
            posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO);
            posix_spawn_file_actions_addclose(&actions, out[0]);
            posix_spawn_file_actions_addclose(&actions, out[1]);
            posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
            posix_spawnattr_t attrs;
            posix_spawnattr_init(&attrs);
            char * const argv[] = {(char *)"jbroot", NULL};
            pid_t pid = 0;
            int err = posix_spawn(&pid, jbBinaries[i], &actions, &attrs, argv, environ);
            posix_spawn_file_actions_destroy(&actions);
            posix_spawnattr_destroy(&attrs);
            close(out[1]);
            NSString *prefix = nil;
            if (err == 0) {
                char buf[1024];
                ssize_t total = 0;
                // Short-lived helper: blocking read then reap.
                ssize_t n = read(out[0], buf, sizeof(buf) - 1);
                int status = 0;
                for (int t = 0; t < 20; t++) {
                    if (waitpid(pid, &status, WNOHANG) == pid) break;
                    usleep(100 * 1000);
                }
                if (n > 0) {
                    total = n;
                    buf[total] = '\0';
                    NSString *s = [[NSString stringWithUTF8String:buf]
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if ([s hasPrefix:@"/"] && [fm fileExistsAtPath:s]) prefix = s;
                }
            }
            close(out[0]);
            if (prefix) { cached = [prefix copy]; return; }
        }
    });
    return cached;
}

static NSString *ZXVNCLaunchDaemonPath(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *rootlessPath = @"/var/jb/Library/LaunchDaemons/com.zjx.trollvnc.plist";
    if ([fm fileExistsAtPath:rootlessPath]) return rootlessPath;

    // Roothide: live prefix + /Library/LaunchDaemons/...
    NSString *prefix = ZXJbrootPrefix();
    if (prefix && ![prefix isEqualToString:@"/var/jb"]) {
        NSString *p = [prefix stringByAppendingPathComponent:@"Library/LaunchDaemons/com.zjx.trollvnc.plist"];
        if ([fm fileExistsAtPath:p]) return p;
    }
    return @"/Library/LaunchDaemons/com.zjx.trollvnc.plist";
}

// Server binary: prefer ProgramArguments[0] from the installed plist because
// postinst-roothide rewrites /var/jb -> live jbroot there. Falls back to the
// well-known absolute candidates on both schemes.
static NSString *ZXVNCServerBinaryPath(void)
{
    NSString *daemonPath = ZXVNCLaunchDaemonPath();
    NSDictionary *job = [NSDictionary dictionaryWithContentsOfFile:daemonPath];
    NSArray *args = job[@"ProgramArguments"];
    if ([args isKindOfClass:[NSArray class]] && args.count > 0 &&
        [args[0] isKindOfClass:[NSString class]] &&
        [[NSFileManager defaultManager] isExecutableFileAtPath:args[0]]) {
        return args[0];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in @[@"/var/jb/usr/bin/trollvncserver", @"/usr/bin/trollvncserver"]) {
        if ([fm isExecutableFileAtPath:p]) return p;
    }
    NSString *prefix = ZXJbrootPrefix();
    if (prefix) {
        NSString *p = [prefix stringByAppendingPathComponent:@"usr/bin/trollvncserver"];
        if ([fm isExecutableFileAtPath:p]) return p;
    }
    return @"/var/jb/usr/bin/trollvncserver";
}

// ── Shell-less spawn (rootless fix) ──────────────────────────────────────
// system() always execs /bin/sh, which does not exist on rootless
// (only /var/jb/bin/sh exists). That made every VNC recovery return
// 127<<8 = 32512 with no log output. Everything below uses posix_spawn
// with absolute binary paths — no shell, no PATH, no nohup.
static void ZXVNCIgnoreSIGCHLDOnce(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        signal(SIGCHLD, SIG_IGN);
    });
}

static const char *ZXFirstExecutable(const char * const *candidates)
{
    for (int i = 0; candidates[i]; i++) {
        if (access(candidates[i], X_OK) == 0) return candidates[i];
    }
    return NULL;
}

// Spawn and wait up to timeoutMs (for short-lived helpers like launchctl).
// Child stdout/stderr go to /dev/null to mirror the old >/dev/null 2>&1.
static BOOL ZXSpawnAndWait(const char *path, char * const argv[], int timeoutMs)
{
    ZXVNCIgnoreSIGCHLDOnce();
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);

    posix_spawnattr_t attrs;
    posix_spawnattr_init(&attrs);
    sigset_t empty;
    sigemptyset(&empty);
    posix_spawnattr_setsigmask(&attrs, &empty);
    posix_spawnattr_setflags(&attrs, POSIX_SPAWN_SETSIGMASK);

    pid_t pid = 0;
    int err = posix_spawn(&pid, path, &actions, &attrs, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attrs);
    if (err != 0) return NO;

    int elapsed = 0;
    while (elapsed < timeoutMs) {
        int status = 0;
        pid_t w = waitpid(pid, &status, WNOHANG);
        if (w == pid) return WIFEXITED(status) && WEXITSTATUS(status) == 0;
        if (w < 0 && errno != EINTR) return NO;
        usleep(100 * 1000);
        elapsed += 100;
    }
    return NO;
}

static void ZXVNCLaunchctl(NSString *verb, BOOL withW, NSString *daemonPath)
{
    const char *daemon = daemonPath.UTF8String;
    if (!daemon || !daemon[0]) return;
    // Fixed candidates (rootless + stock) plus the live roothide prefix.
    NSMutableArray<NSString *> *list = [NSMutableArray arrayWithObjects:
        @"/var/jb/bin/launchctl", @"/bin/launchctl", @"/usr/bin/launchctl", nil];
    NSString *prefix = ZXJbrootPrefix();
    if (prefix && ![prefix isEqualToString:@"/var/jb"]) {
        [list insertObject:[prefix stringByAppendingPathComponent:@"bin/launchctl"] atIndex:0];
    }
    for (NSString *bin in list) {
        const char *path = bin.UTF8String;
        if (access(path, X_OK) != 0) continue;
        if (withW) {
            char * const argv[] = {
                (char *)"launchctl", (char *)verb.UTF8String,
                (char *)"-w", (char *)daemon, NULL
            };
            ZXSpawnAndWait(path, argv, 5000);
        } else {
            char * const argv[] = {
                (char *)"launchctl", (char *)verb.UTF8String,
                (char *)daemon, NULL
            };
            ZXSpawnAndWait(path, argv, 5000);
        }
    }
}

static BOOL ZXVNCServerProcessRunning(void)
{
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0 || size == 0) return NO;
    struct kinfo_proc *procs = malloc(size);
    if (!procs) return NO;
    BOOL running = NO;
    if (sysctl(mib, 4, procs, &size, NULL, 0) == 0) {
        size_t count = size / sizeof(struct kinfo_proc);
        for (size_t i = 0; i < count; i++) {
            const char *name = procs[i].kp_proc.p_comm;
            if (name && strcmp(name, "trollvncserver") == 0) { running = YES; break; }
        }
    }
    free(procs);
    return running;
}

static void ZXVNCkillServerSignal(int sig)
{
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0 || size == 0) return;
    struct kinfo_proc *procs = malloc(size);
    if (!procs) return;
    if (sysctl(mib, 4, procs, &size, NULL, 0) != 0) { free(procs); return; }
    size_t count = size / sizeof(struct kinfo_proc);
    for (size_t i = 0; i < count; i++) {
        const char *name = procs[i].kp_proc.p_comm;
        if (name && strcmp(name, "trollvncserver") == 0) {
            pid_t pid = procs[i].kp_proc.p_pid;
            // A rejected kill (EPERM when the server runs under another uid) used
            // to vanish without a trace — which is exactly the case where the
            // switch looks applied while the server keeps running.
            if (kill(pid, sig) != 0) {
                ZXDashboardDebugLog(@"[vnc] kill(%d, %d) failed: %s", pid, sig, strerror(errno));
            }
        }
    }
    free(procs);
}

static void ZXVNCSetDaemonDisabled(BOOL disabled)
{
    NSString *daemonPath = ZXVNCLaunchDaemonPath();
    // Set the flag in-process. The shell route this replaced needed `plutil`,
    // which a rootless install does not ship at all — the write then did nothing
    // while looking successful, so a job that should have been disabled stayed
    // loadable.
    NSMutableDictionary *job = [[NSDictionary dictionaryWithContentsOfFile:daemonPath] mutableCopy];
    if (job) {
        job[@"Disabled"] = @(disabled);
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:job
                                                                  format:NSPropertyListXMLFormat_v1_0
                                                                 options:0
                                                                   error:nil];
        if (!data || ![data writeToFile:daemonPath atomically:YES]) {
            // Expected as mobile against a root-owned LaunchDaemon: report it
            // instead of letting the OFF look fully applied.
            ZXDashboardDebugLog(@"[vnc] could not set Disabled=%@ on %@",
                                disabled ? @"YES" : @"NO", daemonPath.lastPathComponent);
        }
    }
    // Shell-less: try every known launchctl binary directly. No PATH, no
    // test(1), no shell — posix_spawn with absolute paths.
    NSString *verb = disabled ? @"unload" : @"load";
    ZXVNCLaunchctl(verb, YES, daemonPath);
    ZXVNCLaunchctl(verb, NO, daemonPath);
}

static void ZXVNCApplyEnabledState(BOOL enabled)
{
    if (enabled) {
        // Enable path: make sure launchd owns the server again, then make sure a
        // server is actually listening. `launchctl load -w` on a system daemon
        // needs root while this code runs as mobile, and re-loading an already
        // loaded job never starts it — so spawn the same binary directly when
        // the port is still closed. Re-check the switch first: an OFF that
        // landed in between must win over this stale enable.
        ZXVNCSetDaemonDisabled(NO);
        if (ZXVNCIsEnabled() && !ZXVNCProbePort(5901)) ZXVNCStartServerDirectly();
        return;
    }
    // Disable path must be total. The daemon entry carries no KeepAlive, so the
    // kill alone already makes OFF stick; the unload/Disabled steps stay for
    // the case where this runs as root (SpringBoard on a rootful setup) and are
    // harmless no-ops when it does not.
    ZXVNCSetDaemonDisabled(YES);
    ZXVNCkillServerSignal(SIGTERM);
    [NSThread sleepForTimeInterval:0.5];
    ZXVNCSetDaemonDisabled(YES);
    if (ZXVNCServerProcessRunning() || ZXVNCProbePort(5901) || ZXVNCProbePort(5801)) {
        ZXVNCkillServerSignal(SIGKILL);
        [NSThread sleepForTimeInterval:0.5];
    }
    // Final sweep: a server that came back between the two kills would
    // otherwise live on.
    if (ZXVNCServerProcessRunning() || ZXVNCProbePort(5901) || ZXVNCProbePort(5801)) {
        ZXVNCSetDaemonDisabled(YES);
        ZXVNCkillServerSignal(SIGKILL);
    }
    // A process that survives even SIGKILL (stuck in a kernel call) keeps its
    // name, and the port-first recovery in ZXVNCStartServerDirectly() then reads
    // it as "alive" — say so here instead of leaving the next recovery to look
    // like a silent failure.
    if (ZXVNCServerProcessRunning()) {
        ZXDashboardDebugLog(@"[vnc] trollvncserver survived the OFF sweep (ports %d/%d)",
                            ZXVNCProbePort(5901), ZXVNCProbePort(5801));
    }
}

static NSString *const ZXVNCScaleKey = @"vnc_scale";
static const double ZXVNCScaleDefault = 0.3;

static BOOL ZXVNCScaleIsAllowed(double scale)
{
    static const double allowed[] = {0.3, 0.5, 0.6, 0.7, 1.0};
    for (size_t i = 0; i < sizeof(allowed) / sizeof(allowed[0]); i++) {
        double delta = allowed[i] - scale;
        if (delta < 0) delta = -delta;
        if (delta < 0.001) return YES;
    }
    return NO;
}

static double ZXVNCScale(void)
{
    NSDictionary *configuration = [NSDictionary dictionaryWithContentsOfFile:ZXDashboardConfigPath];
    double scale = [[configuration objectForKey:ZXVNCScaleKey] doubleValue];
    return ZXVNCScaleIsAllowed(scale) ? scale : ZXVNCScaleDefault;
}

static void ZXVNCSetScale(double scale)
{
    if (!ZXVNCScaleIsAllowed(scale)) return;
    NSMutableDictionary *configuration = [[NSDictionary dictionaryWithContentsOfFile:ZXDashboardConfigPath] mutableCopy];
    if (!configuration) configuration = [NSMutableDictionary dictionary];
    configuration[ZXVNCScaleKey] = @(scale);
    [[NSFileManager defaultManager] createDirectoryAtPath:[ZXDashboardConfigPath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:nil];
    [configuration writeToFile:ZXDashboardConfigPath atomically:YES];
}

// Start the server without relying on launchd or on any shell.
// `launchctl load -w` on a system daemon needs root while this code runs as
// mobile, and re-loading an already-loaded job never starts it — so the binary
// itself is spawned directly when the port is still closed. The binary drops
// itself to uid 501 (same as the launchd-started one), so both routes end up
// with the identical process.
static void ZXVNCStartServerDirectly(void)
{
    // "Already running?" must mean the PORT answers, never "a process with the
    // right name exists". A server that takes a TERM while it is already tearing
    // down keeps its name after its listeners are closed, and the old
    // process-name test then answered YES forever.
    if (ZXVNCProbePort(5901)) return;
    if (ZXVNCServerProcessRunning()) {
        ZXDashboardDebugLog(@"[vnc] trollvncserver alive while :5901 is closed — killing the wedged copy");
        ZXVNCkillServerSignal(SIGKILL);
        [NSThread sleepForTimeInterval:0.5];
        if (ZXVNCProbePort(5901)) return;
    }
    // Shell-less: best effort let launchd own it again when running as root,
    // then spawn the binary directly with absolute paths. No /bin/sh, no PATH,
    // no nohup — posix_spawn + append redirection into trollvnc.log.
    ZXVNCLaunchctl(@"load", YES, ZXVNCLaunchDaemonPath());
    if (ZXVNCIsEnabled() && ZXVNCProbePort(5901)) return;

    NSString *serverPath = ZXVNCServerBinaryPath();
    const char *server = serverPath.UTF8String;
    if (!server || !server[0] || access(server, X_OK) != 0) {
        ZXDashboardDebugLog(@"[vnc] trollvncserver binary not found");
        return;
    }
    char scaleStr[32];
    snprintf(scaleStr, sizeof(scaleStr), "%g", ZXVNCScale());
    const char *logPath = ZX_TROLLVNC_LOG_PATH.fileSystemRepresentation;
    if (!logPath || !logPath[0]) logPath = "/var/mobile/Library/ZXTouch/trollvnc.log";

    ZXVNCIgnoreSIGCHLDOnce();
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, logPath,
                                     O_WRONLY | O_CREAT | O_APPEND, 0644);
    posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);

    posix_spawnattr_t attrs;
    posix_spawnattr_init(&attrs);
    sigset_t empty;
    sigemptyset(&empty);
    posix_spawnattr_setsigmask(&attrs, &empty);
    // Minimal flags only: SETPGROUP/SETSID need privileges a mobile daemon
    // does not have and posix_spawn then fails with EPERM (1). Inheriting
    // the parent process group is fine — SIGCHLD is ignored so no zombie.
    posix_spawnattr_setflags(&attrs, POSIX_SPAWN_SETSIGMASK);

    char * const argv[] = {
        (char *)"trollvncserver",
        (char *)"-p", (char *)"5901",
        (char *)"-H", (char *)"5801",
        (char *)"-n", (char *)"ZXTouch",
        (char *)"-s", scaleStr,
        (char *)"-F", (char *)"30:60:120",
        (char *)"-d", (char *)"0.008",
        (char *)"-Q", (char *)"1",
        (char *)"-O", (char *)"on",
        (char *)"-B", (char *)"off",
        (char *)"-A", (char *)"15",
        (char *)"-I", (char *)"off",
        NULL
    };
    pid_t pid = 0;
    int err = posix_spawn(&pid, server, &actions, &attrs, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attrs);
    if (err != 0) {
        ZXDashboardDebugLog(@"[vnc] spawn %s failed: %s (%d)", server, strerror(err), err);
    } else {
        ZXDashboardDebugLog(@"[vnc] spawn %s pid=%d scale=%s", server, pid, scaleStr);
    }
}

static void ZXVNCkillServer(void)
{
    // Compatibility wrapper: full disable-path sweep (unload + TERM + KILL).
    // Callers that only want to restart (scale change) clear the cooldown and
    // call recoverVNC afterwards; callers that disable must use
    // ZXVNCApplyEnabledState(NO) so the daemon stays unloaded.
    ZXVNCSetDaemonDisabled(YES);
    ZXVNCkillServerSignal(SIGTERM);
    [NSThread sleepForTimeInterval:0.5];
    if (ZXVNCServerProcessRunning() || ZXVNCProbePort(5901) || ZXVNCProbePort(5801)) {
        ZXVNCkillServerSignal(SIGKILL);
    }
}

static BOOL ZXVNCProbePort(uint16_t port)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    struct timeval timeout = {0, 300000};
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    BOOL open = connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0;
    close(fd);
    return open;
}
#endif

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

#import "GCDWebServerConnection.h"

// Logs every client connection close so a dashboard that dropped on its own
// can be told apart from a browser tab the user simply closed. GCDWebServer's
// own connection logs are DEBUG-level, which release builds compile out.
@interface ZXLoggedConnection : GCDWebServerConnection
@end

@implementation ZXLoggedConnection

- (void)close
{
    ZXDashboardDebugLog(@"[conn] closed remote=%@", self.remoteAddressString ?: @"?");
    [super close];
}

@end

@interface ZXRemoteDashboardServer : NSObject
@property(nonatomic, strong) GCDWebServer *server;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic, copy) NSString *lastAction;
@property(nonatomic, copy) NSArray<NSDictionary *> *appsCache;
@property(nonatomic, strong) NSDate *appsCacheAt;
@property(nonatomic, copy) NSDictionary *statusCache;
@property(nonatomic, strong) NSDate *statusCacheAt;
@property(nonatomic, strong) NSDate *vncRecoveryAt;
@end

static NSString *ZXPreludePath(void)
{
    NSArray *paths = @[
        @"/var/jb/usr/share/zxtouch/python/zxtouch/prelude.py",
        @"/usr/share/zxtouch/python/zxtouch/prelude.py"
    ];
    for (NSString *path in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    }
    return nil;
}

static NSString *ZXEditorParameterType(NSString *parameter, NSString *defaultValue)
{
    NSString *raw = [parameter stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *name = [[raw componentsSeparatedByString:@":"].firstObject
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *lower = name.lowercaseString;
    NSString *annotation = raw.length > name.length ? [[raw substringFromIndex:name.length + 1]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
    if ([annotation isEqualToString:@"str"]) return @"text";
    if ([annotation isEqualToString:@"int"] || [annotation isEqualToString:@"float"]) return @"number";
    if ([annotation isEqualToString:@"bool"]) return @"boolean";
    if ([annotation isEqualToString:@"dict"] || [annotation isEqualToString:@"list"] || [annotation isEqualToString:@"tuple"]) return @"table";
    if ([raw hasPrefix:@"*"]) return @"any";
    if ([defaultValue isEqualToString:@"True"] || [defaultValue isEqualToString:@"False"]) return @"boolean";
    if ([defaultValue hasPrefix:@"\""] || [defaultValue hasPrefix:@"'"]) return @"text";
    if ([defaultValue rangeOfString:@"^[+-]?[0-9]+(\\.[0-9]+)?$" options:NSRegularExpressionSearch].location != NSNotFound) return @"number";
    if ([lower containsString:@"region"] || [lower containsString:@"pattern"] || [lower containsString:@"location"] ||
        [lower containsString:@"header"] || [lower containsString:@"body"] || [lower containsString:@"option"] ||
        [lower isEqualToString:@"data"] || [lower isEqualToString:@"obj"]) return @"table";
    if ([lower isEqualToString:@"enabled"] || [lower isEqualToString:@"case_sensitive"] || [lower isEqualToString:@"debug"]) return @"boolean";
    if ([lower isEqualToString:@"x"] || [lower isEqualToString:@"y"] || [lower isEqualToString:@"w"] ||
        [lower isEqualToString:@"h"] || [lower isEqualToString:@"fid"] || [lower containsString:@"count"] ||
        [lower containsString:@"timeout"] || [lower containsString:@"interval"] || [lower containsString:@"duration"] ||
        [lower containsString:@"delay"] || [lower containsString:@"speed"] || [lower containsString:@"threshold"] ||
        [lower containsString:@"tolerance"] || [lower containsString:@"scale"] || [lower containsString:@"angle"] ||
        [lower containsString:@"seconds"] || [lower containsString:@"microseconds"] || [lower containsString:@"mins"] ||
        [lower containsString:@"maxs"] || [lower containsString:@"index"]) return @"number";
    if ([lower containsString:@"path"] || [lower containsString:@"url"] || [lower containsString:@"text"] ||
        [lower containsString:@"message"] || [lower containsString:@"title"] || [lower containsString:@"name"] ||
        [lower containsString:@"key"] || [lower containsString:@"direction"] || [lower isEqualToString:@"s"] ||
        [lower isEqualToString:@"lang"] || [lower isEqualToString:@"content"] || [lower isEqualToString:@"bundleid"]) return @"text";
    return @"any";
}

static NSString *ZXEditorTypedSignature(NSString *name, NSString *args)
{
    if (args.length == 0) return [NSString stringWithFormat:@"%@()", name];
    NSMutableArray *typed = [NSMutableArray array];
    for (NSString *part in [args componentsSeparatedByString:@","]) {
        NSString *parameter = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (parameter.length == 0 || [parameter isEqualToString:@"/"] || [parameter isEqualToString:@"*"]) continue;
        NSArray *assignment = [parameter componentsSeparatedByString:@"="];
        NSString *declaration = [assignment.firstObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *defaultValue = @"";
        if (assignment.count > 1) {
            defaultValue = [[assignment subarrayWithRange:NSMakeRange(1, assignment.count - 1)] componentsJoinedByString:@"="];
            defaultValue = [defaultValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        NSString *namePart = [[declaration componentsSeparatedByString:@":"].firstObject
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *type = ZXEditorParameterType(declaration, defaultValue);
        NSString *formatted = [NSString stringWithFormat:@"%@: %@%@", namePart, type,
                               defaultValue.length ? [NSString stringWithFormat:@" = %@", defaultValue] : @""];
        [typed addObject:formatted];
    }
    return [NSString stringWithFormat:@"%@(%@)", name, [typed componentsJoinedByString:@", "]];
}

static NSArray *ZXEditorFunctionCatalog(void)
{
    NSString *path = ZXPreludePath();
    NSString *source = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    if (source.length == 0) return @[];

    // Only expose names injected by prelude.install(), not private helpers.
    NSRange allStart = [source rangeOfString:@"__all__ = ["];
    NSRange allEnd = allStart.location == NSNotFound ? NSMakeRange(NSNotFound, 0) :
        [source rangeOfString:@"\n]" options:0 range:NSMakeRange(NSMaxRange(allStart), source.length - NSMaxRange(allStart))];
    if (allStart.location == NSNotFound || allEnd.location == NSNotFound) return @[];
    NSString *allSource = [source substringWithRange:NSMakeRange(NSMaxRange(allStart), allEnd.location - NSMaxRange(allStart))];
    NSRegularExpression *quoted = [NSRegularExpression regularExpressionWithPattern:@"\\\"([A-Za-z_]\\w*)\\\"" options:0 error:nil];
    NSMutableSet *exported = [NSMutableSet set];
    [quoted enumerateMatchesInString:allSource options:0 range:NSMakeRange(0, allSource.length)
                           usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        [exported addObject:[allSource substringWithRange:[match rangeAtIndex:1]]];
    }];

    NSRegularExpression *defs = [NSRegularExpression regularExpressionWithPattern:@"^def\\s+([A-Za-z_]\\w*)\\s*\\((.*?)\\)\\s*:"
                                                                               options:NSRegularExpressionDotMatchesLineSeparators | NSRegularExpressionAnchorsMatchLines
                                                                                 error:nil];
    NSMutableArray *functions = [NSMutableArray array];
    [defs enumerateMatchesInString:source options:0 range:NSMakeRange(0, source.length)
                         usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        NSString *name = [source substringWithRange:[match rangeAtIndex:1]];
        if (![exported containsObject:name]) return;
        NSString *args = [source substringWithRange:[match rangeAtIndex:2]];
        args = [args stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        args = [args stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *signature = ZXEditorTypedSignature(name, args);
        [functions addObject:@{ @"name": name,
                                @"signature": signature,
                                @"description": signature }];
    }];
    return functions;
}

@implementation ZXRemoteDashboardServer

- (instancetype)init
{
    self = [super init];
    if (self) {
        _lastAction = @"Ready";
    }
    return self;
}

- (GCDWebServerDataResponse *)jsonResponse:(NSDictionary *)payload status:(NSInteger)status
{
    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithJSONObject:payload];
    response.statusCode = status;
    return response;
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

- (NSArray<NSDictionary *> *)installedApps
{
    static const NSTimeInterval ZXAppsCacheSeconds = 30;
    if (self.appsCache && self.appsCacheAt && -[self.appsCacheAt timeIntervalSinceNow] < ZXAppsCacheSeconds) {
        return self.appsCache;
    }
    // Enumerate the real LaunchServices app list through ObjC runtime only —
    // the dashboard has no private-framework headers, and every selector here
    // is probed so an OS that lacks one simply yields an empty list instead of
    // crashing SpringBoard (which hosts this server).
    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    if (!workspaceClass) return @[];
    SEL defaultWs = sel_registerName("defaultWorkspace");
    if (![workspaceClass respondsToSelector:defaultWs]) return @[];
    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultWs);
    if (!workspace) return @[];

    SEL allApps = sel_registerName("allApplications");
    if (![workspace respondsToSelector:allApps]) return @[];
    NSArray *apps = ((id (*)(id, SEL))objc_msgSend)(workspace, allApps);
    if (![apps isKindOfClass:[NSArray class]]) return @[];

    SEL bundleIdSel = sel_registerName("bundleIdentifier");
    // Name probes, best first. `localizedName` / `displayName` are real
    // LSApplicationProxy getters; `localizedNameForListing:` needs the listing
    // constant (0 = icon) and is kept last as a best-effort fallback.
    SEL localizedNameSel = sel_registerName("localizedName");
    SEL displayNameSel = sel_registerName("displayName");
    SEL listingNameSel = sel_registerName("localizedNameForListing:");
    SEL bundleSel = sel_registerName("bundleURL");
    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:apps.count];
    for (id proxy in apps) {
        @try {
            NSString *bundleId = nil;
            if ([proxy respondsToSelector:bundleIdSel]) {
                id raw = ((id (*)(id, SEL))objc_msgSend)(proxy, bundleIdSel);
                if ([raw isKindOfClass:[NSString class]]) bundleId = raw;
            }
            if (bundleId.length == 0) continue;

            NSString *name = nil;
            const SEL nameProbes[] = { localizedNameSel, displayNameSel };
            for (size_t i = 0; i < sizeof(nameProbes) / sizeof(nameProbes[0]); i++) {
                if (![proxy respondsToSelector:nameProbes[i]]) continue;
                id raw = ((id (*)(id, SEL))objc_msgSend)(proxy, nameProbes[i]);
                if ([raw isKindOfClass:[NSString class]] && [(NSString *)raw length]) { name = raw; break; }
            }
            if (name.length == 0 && [proxy respondsToSelector:listingNameSel]) {
                id raw = ((id (*)(id, SEL, long))objc_msgSend)(proxy, listingNameSel, 0L);
                if ([raw isKindOfClass:[NSString class]]) name = raw;
            }
            if (name.length == 0 && [proxy respondsToSelector:bundleSel]) {
                id url = ((id (*)(id, SEL))objc_msgSend)(proxy, bundleSel);
                if ([url respondsToSelector:@selector(lastPathComponent)]) {
                    NSString *leaf = [[url lastPathComponent] stringByDeletingPathExtension];
                    if (leaf.length) name = leaf;
                }
            }
            if (name.length == 0) name = bundleId;
            [out addObject:@{ @"name": name, @"bundleId": bundleId }];
        } @catch (NSException *e) { /* skip one bad proxy, keep the list */ }
    }
    NSArray<NSDictionary *> *sorted = [out sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
    if (sorted.count) { self.appsCache = sorted; self.appsCacheAt = [NSDate date]; }
    return sorted;
}

- (NSString *)sendSocketCommand:(NSString *)command expectsReply:(BOOL)expectsReply
{
    return [self sendSocketCommand:command expectsReply:expectsReply timeout:2.0];
}

- (NSString *)sendSocketCommand:(NSString *)command expectsReply:(BOOL)expectsReply timeout:(NSTimeInterval)timeout
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
    struct timeval tv;
    tv.tv_sec = (time_t)timeout;
    tv.tv_usec = (suseconds_t)((timeout - (NSTimeInterval)tv.tv_sec) * 1000000.0);
    setsockopt(socketHandle, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(socketHandle, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
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

- (NSDictionary *)vncHealth
{
    BOOL enabled = ZXVNCIsEnabled();
    // Report REAL port state even when disabled so the dashboard can detect a
    // failed kill (disabled=true but port still open) instead of masking it.
    // The frontend gates on `enabled`, not on the port flags.
    return @{ @"enabled": @(enabled), @"port": @5901, @"httpPort": @5801,
              @"scale": @(ZXVNCScale()),
              @"vncPortOpen": @(ZXVNCProbePort(5901)),
              @"httpPortOpen": @(ZXVNCProbePort(5801)) };
}

- (NSDictionary *)status
{
    if (self.statusCache && self.statusCacheAt && [[NSDate date] timeIntervalSinceDate:self.statusCacheAt] < ZXDashboardStatusCacheTTL) {
        return self.statusCache;
    }
    NSString *rawSize = [self sendSocketCommand:@"251" expectsReply:YES];
    if (![rawSize hasPrefix:@"0"]) {
        NSDictionary *offline = @{
            @"running": @(self.server.running),
            @"serviceOnline": @NO,
            @"stale": self.statusCache != nil ? @YES : @NO,
            @"port": @(self.server.port),
            @"screen": @{ @"width": @"", @"height": @"" },
            @"orientation": @"", @"battery": @"", @"foregroundApp": @"",
            @"scriptPlaying": @NO, @"recording": @NO,
            @"deviceName": @"", @"systemName": @"", @"systemVersion": @"", @"model": @"",
            @"vnc": [self vncHealth],
            @"lastAction": self.lastAction ?: @"Ready",
            @"lastError": self.lastError ?: @"ZXTouch service unavailable.",
            @"scriptCount": @([self scripts].count)
        };
        self.statusCache = offline;
        self.statusCacheAt = [NSDate date];
        return offline;
    }
    NSString *rawOrientation = [self sendSocketCommand:@"252" expectsReply:YES];
    if (![rawOrientation hasPrefix:@"0"]) { self.statusCache = nil; return @{ @"running": @(self.server.running), @"serviceOnline": @NO, @"stale": @NO, @"vnc": [self vncHealth], @"lastError": self.lastError ?: @"ZXTouch service unavailable.", @"scriptCount": @([self scripts].count) }; }
    NSString *rawBattery = [self sendSocketCommand:@"2531" expectsReply:YES];
    if (![rawBattery hasPrefix:@"0"]) { self.statusCache = nil; return @{ @"running": @(self.server.running), @"serviceOnline": @NO, @"stale": @NO, @"vnc": [self vncHealth], @"lastError": self.lastError ?: @"ZXTouch service unavailable.", @"scriptCount": @([self scripts].count) }; }
    NSString *rawRuntime = [self sendSocketCommand:@"2532" expectsReply:YES];
    if (![rawRuntime hasPrefix:@"0"]) { self.statusCache = nil; return @{ @"running": @(self.server.running), @"serviceOnline": @NO, @"stale": @NO, @"vnc": [self vncHealth], @"lastError": self.lastError ?: @"ZXTouch service unavailable.", @"scriptCount": @([self scripts].count) }; }
    // Task 25 (device info) + subtask 30 = name;;systemName;;systemVersion;;model;;vendorID.
    // Model (uname.machine, e.g. iPhone12,8 / iPhone14,6) drives the
    // physical-Home vs swipe-Home detection in the dashboard (Pure-VNC plan).
    NSString *rawDeviceInfo = [self sendSocketCommand:@"2530" expectsReply:YES];
    if (![rawDeviceInfo hasPrefix:@"0"]) { self.statusCache = nil; return @{ @"running": @(self.server.running), @"serviceOnline": @NO, @"stale": @NO, @"vnc": [self vncHealth], @"lastError": self.lastError ?: @"ZXTouch service unavailable.", @"scriptCount": @([self scripts].count) }; }
    NSString *size = [self payloadFromSocketReply:rawSize];
    NSString *orientation = [self payloadFromSocketReply:rawOrientation];
    NSString *battery = [self payloadFromSocketReply:rawBattery];
    NSString *runtime = [self payloadFromSocketReply:rawRuntime];
    NSString *deviceInfo = [self payloadFromSocketReply:rawDeviceInfo];
    NSArray *sizeParts = [size componentsSeparatedByString:@";;"];
    NSArray *batteryParts = [battery componentsSeparatedByString:@";;"];
    NSArray *runtimeParts = [runtime componentsSeparatedByString:@";;"];
    NSArray *deviceParts = [deviceInfo componentsSeparatedByString:@";;"];
    NSDictionary *fresh = @{
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
        // TrollVNC endpoints bundled in the same (rootless) .deb. These values
        // are diagnostic metadata; they do not prove the daemon is listening.
        @"vnc": [self vncHealth],
        @"lastAction": self.lastAction ?: @"Ready",
        @"lastError": self.lastError ?: @"",
        @"scriptCount": @([self scripts].count)
    };
    self.statusCache = fresh;
    self.statusCacheAt = [NSDate date];
    return fresh;
}

- (NSDictionary *)recoverVNC
{
    if (!ZXVNCIsEnabled()) {
        return @{ @"ok": @NO, @"started": @NO, @"vncPortOpen": @(ZXVNCProbePort(5901)), @"httpPortOpen": @(ZXVNCProbePort(5801)),
                  @"message": @"VNC Server is disabled in Settings." };
    }
    BOOL vncOpen = ZXVNCProbePort(5901);
    BOOL httpOpen = ZXVNCProbePort(5801);
    if (vncOpen) return @{ @"ok": @YES, @"started": @NO, @"vncPortOpen": @YES, @"httpPortOpen": @(httpOpen), @"message": @"VNC server is already running." };
    NSDate *now = [NSDate date];
    if (self.vncRecoveryAt && [now timeIntervalSinceDate:self.vncRecoveryAt] < ZXVNCRecoverCooldown) {
        return @{ @"ok": @NO, @"started": @NO, @"vncPortOpen": @NO, @"httpPortOpen": @(httpOpen), @"message": @"VNC recovery is cooling down." };
    }
    self.vncRecoveryAt = now;
    // Re-check after claiming the cooldown slot: a disable that landed in
    // between must win over this in-flight recovery.
    if (!ZXVNCIsEnabled()) {
        return @{ @"ok": @NO, @"started": @NO, @"vncPortOpen": @(ZXVNCProbePort(5901)), @"httpPortOpen": @(ZXVNCProbePort(5801)),
                  @"message": @"VNC Server is disabled in Settings." };
    }
    // Re-enable the daemon entry (it may carry Disabled=YES from a previous
    // OFF) before asking launchd to load it.
    ZXVNCSetDaemonDisabled(NO);
    if (!ZXVNCIsEnabled()) {
        ZXVNCApplyEnabledState(NO);
        return @{ @"ok": @NO, @"started": @NO, @"vncPortOpen": @NO, @"httpPortOpen": @NO,
                  @"message": @"VNC Server is disabled in Settings." };
    }
    ZXVNCStartServerDirectly();
    for (int i = 0; i < 16 && !vncOpen; i++) {
        // Abort the wait as soon as the user disables VNC mid-start, and tear
        // down the half-started server so OFF is always final.
        if (!ZXVNCIsEnabled()) {
            ZXVNCApplyEnabledState(NO);
            self.statusCache = nil;
            self.statusCacheAt = nil;
            return @{ @"ok": @NO, @"started": @NO, @"vncPortOpen": @(ZXVNCProbePort(5901)), @"httpPortOpen": @(ZXVNCProbePort(5801)),
                      @"message": @"VNC Server is disabled in Settings." };
        }
        [NSThread sleepForTimeInterval:0.5];
        vncOpen = ZXVNCProbePort(5901);
    }
    // Final gate: never report success for a server the user just disabled.
    if (!ZXVNCIsEnabled()) {
        ZXVNCApplyEnabledState(NO);
        self.statusCache = nil;
        self.statusCacheAt = nil;
        return @{ @"ok": @NO, @"started": @NO, @"vncPortOpen": @(ZXVNCProbePort(5901)), @"httpPortOpen": @(ZXVNCProbePort(5801)),
                  @"message": @"VNC Server is disabled in Settings." };
    }
    httpOpen = ZXVNCProbePort(5801);
    self.statusCache = nil;
    self.statusCacheAt = nil;
    return @{ @"ok": @(vncOpen), @"started": @YES, @"vncPortOpen": @(vncOpen), @"httpPortOpen": @(httpOpen),
              @"message": vncOpen ? @"VNC server started." : @"Unable to start VNC server." };
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

- (BOOL)isImageFileName:(NSString *)fileName
{
    static NSSet<NSString *> *extensions = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        extensions = [NSSet setWithArray:@[@"png", @"jpg", @"jpeg", @"gif", @"webp", @"bmp", @"tif", @"tiff", @"heic"]];
    });
    NSString *extension = fileName.pathExtension.lowercaseString;
    return extension.length > 0 && [extensions containsObject:extension];
}

- (NSString *)assetPathInBundle:(NSString *)bundlePath relativeName:(NSString *)relativeName
{
    // Second traversal guard behind bundlePathForRelativePath: the name arrives
    // straight from the client query, so it must not escape the bundle folder.
    if (![bundlePath isKindOfClass:[NSString class]] || bundlePath.length == 0) return nil;
    if (![relativeName isKindOfClass:[NSString class]] || relativeName.length == 0) return nil;
    if ([relativeName hasPrefix:@"/"] || [relativeName rangeOfString:@".."].location != NSNotFound) return nil;

    NSString *candidate = [[bundlePath stringByAppendingPathComponent:relativeName] stringByStandardizingPath];
    NSString *prefix = [bundlePath stringByAppendingString:@"/"];
    BOOL isDirectory = NO;
    if (![candidate hasPrefix:prefix] || ![[NSFileManager defaultManager] fileExistsAtPath:candidate isDirectory:&isDirectory] || isDirectory) {
        return nil;
    }
    return candidate;
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
    // Serve bundled noVNC assets (./novnc/core/rfb.js, ...) openly on the LAN
    // like the dashboard. Rejects ".." to stay inside the app dir.
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

- (GCDWebServerResponse *)captureScreenResponse
{
    NSString *name = [NSString stringWithFormat:@"dashboard-capture-%@.png", [NSUUID UUID].UUIDString];
    NSString *result = [self sendSocketCommand:[@"30" stringByAppendingString:name] expectsReply:YES];
    if (![result hasPrefix:@"0"]) {
        return [self jsonResponse:@{ @"ok": @NO, @"error": result.length ? result : @"Unable to capture the device screen." } status:503];
    }

    NSString *path = [self payloadFromSocketReply:result];
    NSData *imageData = path.length ? [NSData dataWithContentsOfFile:path] : nil;
    if (path.length) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    if (!imageData.length) {
        return [self jsonResponse:@{ @"ok": @NO, @"error": @"The device returned an empty screen capture." } status:500];
    }

    GCDWebServerDataResponse *response = [GCDWebServerDataResponse responseWithData:imageData contentType:@"image/png"];
    [response setValue:@"attachment; filename=\"zxtouch-screen.png\"" forAdditionalHeader:@"Content-Disposition"];
    [response setValue:@"no-store" forAdditionalHeader:@"Cache-Control"];
    return response;
}

- (NSString *)writeEditorBundleWithCode:(NSString *)code assetBundle:(NSString *)assetBundle error:(NSError **)error
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
    NSMutableDictionary *info = [@{ @"Entry": @"entry.py", @"FrontApp": frontmost, @"Orientation": @"1" } mutableCopy];
    // The staging bundle holds the code and nothing else, so a script that
    // references "home-activ.png" would have no assets beside it. Point the
    // runtime at the bundle the tab came from instead: that folder is what
    // relative asset names resolve against during the run.
    if (assetBundle.length) {
        info[@"AssetDir"] = assetBundle;
    }
    [info writeToFile:[bundlePath stringByAppendingPathComponent:@"info.plist"] atomically:YES];
    if (![code writeToFile:[bundlePath stringByAppendingPathComponent:@"entry.py"]
                atomically:YES encoding:NSUTF8StringEncoding error:error]) {
        return nil;
    }
    return bundlePath;
}

- (NSString *)writeValidationSourceWithCode:(NSString *)code error:(NSError **)error
{
    // Fresh file per request so overlapping checks cannot read each other's
    // report. Lives next to the runtime log dir, outside the script library.
    NSString *directory = [[RUNTIME_OUTPUT_PATH stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"editorcheck"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }
    NSString *path = [directory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"check_%@.py", [[NSUUID UUID] UUIDString]]];
    if (![code writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error]) {
        return nil;
    }
    return path;
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
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        return [GCDWebServerDataResponse responseWithHTML:[strongSelf dashboardHTML]];
    }];

    // Bundled noVNC client (single-.deb plan): ./novnc/** served openly.
    // The dashboard loads ./novnc/core/rfb.js from here, then opens a raw
    // WebSocket to the TrollVNC VNC port (:5901/websockify) for stream+input.
    [self.server addHandlerForMethod:@"GET" pathRegex:@"^/novnc/.*" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        if (!ZXVNCIsEnabled()) return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"VNC Server is disabled in Settings." } status:403];
        GCDWebServerResponse *file = [strongSelf novncFileResponseForRequest:request];
        if (!file) return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"noVNC asset not found. Reinstall the package." } status:404];
        return file;
    }];

    [self.server addHandlerForMethod:@"GET" path:@"/api/scripts" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"scripts": [strongSelf scripts] } status:200];
    }];

    [self.server addHandlerForMethod:@"GET" path:@"/api/editor/functions" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"functions": ZXEditorFunctionCatalog() } status:200];
    }];

    [self.server addHandlerForMethod:@"GET" path:@"/api/status" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"status": [strongSelf status] } status:200];
    }];

    [self.server addHandlerForMethod:@"GET" path:@"/api/capture-screen" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        strongSelf.lastAction = @"Capture full-resolution screen";
        return [strongSelf captureScreenResponse];
    }];

    [self.server addHandlerForMethod:@"GET" path:@"/api/health" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"dashboard": @YES, @"port": @(strongSelf.server.port) } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/vnc/recover" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSDictionary *result = [strongSelf recoverVNC];
        return [strongSelf jsonResponse:result status:[result[@"ok"] boolValue] ? 200 : 503];
    }];

    [self.server addHandlerForMethod:@"GET" path:@"/api/vnc/scale" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        if (!ZXVNCIsEnabled()) return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"VNC Server is disabled in Settings." } status:403];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"scale": @(ZXVNCScale()),
            @"options": @[@0.3, @0.5, @0.6, @0.7, @1.0] } status:200];
    }];

    // POST /api/vnc/scale {scale} — persist the TrollVNC framebuffer scale
    // (0.3/0.5/0.6/0.7/1.0), restart the server so it takes effect, and report
    // the new health. An explicit user action bypasses the recovery cooldown.
    [self.server addHandlerForMethod:@"POST" path:@"/api/vnc/scale" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        if (!ZXVNCIsEnabled()) return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"VNC Server is disabled in Settings." } status:403];
        NSDictionary *body = [((GCDWebServerDataRequest *)request).jsonObject isKindOfClass:[NSDictionary class]] ? ((GCDWebServerDataRequest *)request).jsonObject : @{};
        double scale = [body[@"scale"] doubleValue];
        if (!ZXVNCScaleIsAllowed(scale)) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Scale must be one of 0.3, 0.5, 0.6, 0.7, 1.0.",
                @"scale": @(ZXVNCScale()), @"options": @[@0.3, @0.5, @0.6, @0.7, @1.0] } status:400];
        }
        ZXVNCSetScale(scale);
        // Restart-only path: kill the process but immediately re-arm the
        // daemon entry — ZXVNCkillServer() leaves Disabled=YES by design so a
        // plain kill here would look like a user OFF to the next recover.
        ZXVNCkillServerSignal(SIGTERM);
        [NSThread sleepForTimeInterval:0.5];
        if (ZXVNCServerProcessRunning()) ZXVNCkillServerSignal(SIGKILL);
        ZXVNCSetDaemonDisabled(NO);
        if (!ZXVNCIsEnabled()) {
            ZXVNCApplyEnabledState(NO);
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"VNC Server is disabled in Settings." } status:403];
        }
        strongSelf.vncRecoveryAt = nil;
        NSMutableDictionary *result = [[strongSelf recoverVNC] mutableCopy];
        result[@"scale"] = @(ZXVNCScale());
        result[@"options"] = @[@0.3, @0.5, @0.6, @0.7, @1.0];
        strongSelf.lastAction = [NSString stringWithFormat:@"VNC scale %g", scale];
        return [strongSelf jsonResponse:result status:[result[@"ok"] boolValue] ? 200 : 503];
    }];

    // GET /api/apps — installed apps as { name, bundleId }, sorted by name.
    // Cached for a short while: allApplications touches LaunchServices, and the
    // dashboard polls, so re-walking it on every request is wasteful.
    [self.server addHandlerForMethod:@"GET" path:@"/api/apps" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSArray<NSDictionary *> *apps = [strongSelf installedApps];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"apps": apps, @"count": @(apps.count) } status:200];
    }];

    [self.server addHandlerForMethod:@"GET" path:@"/api/logs" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"logs": [strongSelf recentLogs] } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/logs/clear" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSError *error = nil;
        [@"" writeToFile:RUNTIME_OUTPUT_PATH atomically:YES encoding:NSUTF8StringEncoding error:&error];
        if (error) return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": error.localizedDescription ?: @"Unable to clear logs." } status:500];
        strongSelf.lastAction = @"Clear logs";
        return [strongSelf jsonResponse:@{ @"ok": @YES } status:200];
    }];

    // GET /api/debug-log — the dashboard's own crash/disconnect log, written
    // next to ocrd.log. It outlives the server process, so it is the one place
    // that still has evidence after the dashboard port drops.
    [self.server addHandlerForMethod:@"GET" path:@"/api/debug-log" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"log": ZXDashboardDebugLogTail() } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/debug-log/clear" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        ZXDashboardDebugLogClear();
        strongSelf.lastAction = @"Clear dashboard debug log";
        return [strongSelf jsonResponse:@{ @"ok": @YES } status:200];
    }];

    // GET /api/logs/download?name=dashboardd|trollvnc|debug — the three daemon
    // log files, streamed as a download. The name is whitelisted onto a fixed
    // path, so nothing the client sends can reach the filesystem.
    [self.server addHandlerForMethod:@"GET" path:@"/api/logs/download" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSDictionary<NSString *, NSString *> *logs = @{
            @"dashboardd": ZX_DASHBOARDD_LOG_PATH,
            @"trollvnc": ZX_TROLLVNC_LOG_PATH,
            @"debug": ZX_DASHBOARD_DEBUG_LOG_PATH,
        };
        NSString *path = logs[request.query[@"name"] ?: @""];
        if (path.length == 0) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Unknown log name." } status:400];
        }
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": [NSString stringWithFormat:@"%@ was not found.", path.lastPathComponent] } status:404];
        }
        GCDWebServerFileResponse *response = [GCDWebServerFileResponse responseWithFile:path isAttachment:YES];
        if (!response) return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": [NSString stringWithFormat:@"%@ could not be read.", path.lastPathComponent] } status:500];
        [response setValue:@"no-store" forAdditionalHeader:@"Cache-Control"];
        return response;
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/run" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSDictionary *body = [request.jsonObject isKindOfClass:[NSDictionary class]] ? request.jsonObject : @{};
        NSString *bundlePath = [strongSelf bundlePathForRelativePath:body[@"path"]];
        if (!bundlePath) return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Script was not found." } status:404];
        NSString *result = [strongSelf sendSocketCommand:[@"19" stringByAppendingString:bundlePath] expectsReply:YES];
        strongSelf.lastAction = [NSString stringWithFormat:@"Run %@", bundlePath.lastPathComponent];
        return [strongSelf jsonResponse:@{ @"ok": @([result hasPrefix:@"0"]), @"result": result ?: @"" } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/stop" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSString *result = [strongSelf sendSocketCommand:@"20" expectsReply:YES];
        strongSelf.lastAction = @"Stop script";
        return [strongSelf jsonResponse:@{ @"ok": @([result hasPrefix:@"0"]), @"result": result ?: @"" } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/record/start" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSString *result = [strongSelf sendSocketCommand:@"14" expectsReply:YES];
        strongSelf.lastAction = @"Start recording";
        return [strongSelf jsonResponse:@{ @"ok": @(![result hasPrefix:@"-1"]), @"result": result ?: @"" } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/record/stop" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerDataRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSString *result = [strongSelf sendSocketCommand:@"15" expectsReply:YES];
        strongSelf.lastAction = @"Stop recording";
        return [strongSelf jsonResponse:@{ @"ok": @([result hasPrefix:@"0"]), @"result": result ?: @"" } status:200];
    }];

    [self.server addHandlerForMethod:@"POST" path:@"/api/assets" requestClass:[GCDWebServerMultiPartFormRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerMultiPartFormRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSString *relativePath = [[request firstArgumentForControlName:@"script"] string];
        NSString *bundlePath = [strongSelf bundlePathForRelativePath:relativePath];
        // One request may carry several "asset" parts (the dashboard's file
        // input is a multi-select), so collect them all instead of the first.
        NSMutableArray<GCDWebServerMultiPartFile *> *uploads = [NSMutableArray array];
        for (GCDWebServerMultiPartFile *file in request.files) {
            if ([file.controlName isEqualToString:@"asset"]) [uploads addObject:file];
        }
        if (!bundlePath || uploads.count == 0) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Choose a script and at least one asset file." } status:400];
        }
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSMutableArray<NSString *> *fileNames = [NSMutableArray array];
        // Validate the whole batch before copying anything: a rejected file
        // must not leave the rest of the selection half-uploaded.
        for (GCDWebServerMultiPartFile *upload in uploads) {
            NSString *fileName = upload.fileName.lastPathComponent;
            NSDictionary *attributes = upload.temporaryPath.length ? [fileManager attributesOfItemAtPath:upload.temporaryPath error:nil] : nil;
            unsigned long long size = [attributes fileSize];
            if (![strongSelf isSafeAssetFileName:fileName]) {
                return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": [NSString stringWithFormat:@"%@ cannot be added to a bundle.", fileName.length ? fileName : @"That file"] } status:400];
            }
            if (size > ZXDashboardMaximumAssetSize) {
                return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": [NSString stringWithFormat:@"%@ is larger than 25 MB.", fileName] } status:413];
            }
            [fileNames addObject:fileName];
        }
        for (NSUInteger index = 0; index < uploads.count; index++) {
            NSString *destination = [bundlePath stringByAppendingPathComponent:fileNames[index]];
            [fileManager removeItemAtPath:destination error:nil];
            NSError *error = nil;
            if (![fileManager copyItemAtPath:uploads[index].temporaryPath toPath:destination error:&error]) {
                return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": error.localizedDescription ?: [NSString stringWithFormat:@"Unable to save %@.", fileNames[index]] } status:500];
            }
        }
        strongSelf.lastAction = fileNames.count == 1 ? [NSString stringWithFormat:@"Upload %@", fileNames[0]] : [NSString stringWithFormat:@"Upload %lu assets", (unsigned long)fileNames.count];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"files": fileNames } status:200];
    }];

    // ── Script bundle assets: list + serve ──────────────────────────
    // GET /api/scripts/assets?path=<rel.bdl> — every file inside the bundle
    // (recursively, so "img/btn.png" shows up), minus bundle metadata, the
    // entry script and dotfiles. "image" tells the dashboard when a hover
    // preview is worth fetching.
    [self.server addHandlerForMethod:@"GET" path:@"/api/scripts/assets" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSString *bundlePath = [strongSelf bundlePathForRelativePath:request.query[@"path"]];
        if (!bundlePath) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Choose a script bundle." } status:400];
        }
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"info.plist"]];
        // info.plist is user-editable, so the value is only trusted when it
        // really is a string (same guard as -scripts).
        NSString *entry = [info[@"Entry"] isKindOfClass:[NSString class]] ? info[@"Entry"] : @"";
        NSMutableArray<NSDictionary *> *assets = [NSMutableArray array];
        for (NSString *relative in [fileManager subpathsAtPath:bundlePath] ?: @[]) {
            NSString *fileName = relative.lastPathComponent;
            if ([fileName hasPrefix:@"."]) continue;
            if ([fileName caseInsensitiveCompare:@"info.plist"] == NSOrderedSame) continue;
            if (entry.length && [relative isEqualToString:entry]) continue;
            NSString *fullPath = [bundlePath stringByAppendingPathComponent:relative];
            BOOL isDirectory = NO;
            if (![fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory] || isDirectory) continue;
            NSDictionary *attributes = [fileManager attributesOfItemAtPath:fullPath error:nil];
            [assets addObject:@{ @"name": relative,
                                 @"size": @([attributes fileSize]),
                                 @"image": @([strongSelf isImageFileName:relative]) }];
        }
        [assets sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
        }];
        return [strongSelf jsonResponse:@{ @"ok": @YES, @"path": request.query[@"path"], @"assets": assets } status:200];
    }];

    // GET /api/scripts/asset?path=<rel.bdl>&name=<relative path> — raw bytes
    // of one asset. Not an attachment: the dashboard loads it in an <img>, so
    // GCDWebServerFileResponse sets the content type from the extension.
    [self.server addHandlerForMethod:@"GET" path:@"/api/scripts/asset" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSString *bundlePath = [strongSelf bundlePathForRelativePath:request.query[@"path"]];
        NSString *filePath = [strongSelf assetPathInBundle:bundlePath relativeName:request.query[@"name"]];
        if (!filePath) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Asset was not found." } status:404];
        }
        return [GCDWebServerFileResponse responseWithFile:filePath];
    }];

    [self.server addHandlerForMethod:@"GET" path:@"/api/download" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSString *bundlePath = [strongSelf bundlePathForRelativePath:request.query[@"path"]];
        NSString *entry = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"info.plist"]][@"Entry"];
        NSString *entryPath = entry.length ? [bundlePath stringByAppendingPathComponent:entry] : nil;
        if (!entryPath || ![[NSFileManager defaultManager] fileExistsAtPath:entryPath]) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Script entry was not found." } status:404];
        }
        return [GCDWebServerFileResponse responseWithFile:entryPath isAttachment:YES];
    }];

    // ── Editor tab: ad-hoc write/run/save/load ──────────────────────
    // POST /api/editor/run {code, path?} — writes a hidden __editor__.bdl bundle
    // (outside SCRIPTS_PATH so quick runs don't pollute the library) and
    // plays it immediately. FrontApp is pinned to the currently frontmost
    // app so the run doesn't yank the user elsewhere. `path` is the library
    // bundle the tab was opened from; its folder holds the assets the code
    // refers to by relative name, so the runtime resolves them there.
    [self.server addHandlerForMethod:@"POST" path:@"/api/editor/run" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSDictionary *body = [((GCDWebServerDataRequest *)request).jsonObject isKindOfClass:[NSDictionary class]] ? ((GCDWebServerDataRequest *)request).jsonObject : @{};
        NSString *code = [body[@"code"] isKindOfClass:[NSString class]] ? body[@"code"] : @"";
        if (code.length == 0) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Code is empty." } status:400];
        }
        if (code.length > ZXEditorMaximumCodeLength) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Code is too large (256 KB max)." } status:413];
        }
        NSError *error = nil;
        // An untitled tab has no bundle, and bundlePathForRelativePath: rejects
        // anything that is not an existing bundle inside the library.
        NSString *assetBundle = [strongSelf bundlePathForRelativePath:body[@"path"]];
        NSString *bundlePath = [strongSelf writeEditorBundleWithCode:code assetBundle:assetBundle error:&error];
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
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
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
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
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
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
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

    // POST /api/editor/validate {code} — static analysis of the script.
    // The browser sends Python (Lua is transpiled client-side); the code is
    // staged to a temp file and the SpringBoard service runs
    // `python3 -m zxtouch.checker` on it, writing the report next to the file.
    [self.server addHandlerForMethod:@"POST" path:@"/api/editor/validate" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        ZXRemoteDashboardServer *strongSelf = weakSelf;
        if (!strongSelf) return [GCDWebServerDataResponse responseWithStatusCode:500];
        NSDictionary *body = [((GCDWebServerDataRequest *)request).jsonObject isKindOfClass:[NSDictionary class]] ? ((GCDWebServerDataRequest *)request).jsonObject : @{};
        NSString *code = [body[@"code"] isKindOfClass:[NSString class]] ? body[@"code"] : @"";
        if (code.length > ZXEditorMaximumCodeLength) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": @"Code is too large (256 KB max)." } status:413];
        }
        if (code.length == 0) {
            return [strongSelf jsonResponse:@{ @"ok": @YES, @"clean": @YES, @"diagnostics": @[] } status:200];
        }
        NSError *error = nil;
        NSString *path = [strongSelf writeValidationSourceWithCode:code error:&error];
        if (!path) {
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": error.localizedDescription ?: @"Unable to stage the script for checking." } status:500];
        }
        NSString *reportPath = [path stringByAppendingString:@".diag.json"];
        // Cold Python start + prelude import can exceed the default 2s budget.
        NSString *reply = [strongSelf sendSocketCommand:[@"49" stringByAppendingString:path] expectsReply:YES timeout:30.0];
        NSData *reportData = [NSData dataWithContentsOfFile:reportPath];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:reportPath error:nil];
        NSDictionary *report = reportData.length ? [NSJSONSerialization JSONObjectWithData:reportData options:0 error:nil] : nil;
        if (![report isKindOfClass:[NSDictionary class]]) {
            NSString *message = [reply stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([message hasPrefix:@"-1;;"]) message = [message substringFromIndex:4];
            if (message.length == 0) message = @"The script checker did not return a report.";
            return [strongSelf jsonResponse:@{ @"ok": @NO, @"error": message } status:503];
        }
        strongSelf.lastAction = @"Editor validate";
        return [strongSelf jsonResponse:@{ @"ok": @YES,
                                           @"clean": @([report[@"ok"] boolValue]),
                                           @"diagnostics": report[@"diagnostics"] ?: @[] } status:200];
    }];
}

- (BOOL)start
{
    if (self.server.running) return YES;
    ZXDashboardDebugLogInstall();
    // Route GCDWebServer's own messages (bind / accept / socket errors) into the
    // debug log. Level 1 is VERBOSE per the documented scale in GCDWebServer.h;
    // DEBUG levels 0 stay unusable on purpose, since enabling them also turns
    // GWS_DCHECK into abort() and would cause the very crash we are chasing.
    static dispatch_once_t loggingOnce;
    dispatch_once(&loggingOnce, ^{
        [GCDWebServer setLogLevel:1];
        [GCDWebServer setBuiltInLogger:^(int level, NSString *message) {
            ZXDashboardDebugLog(@"[gws:%d] %@", level, message);
        }];
    });
    self.server = [[GCDWebServer alloc] init];
    [self configureHandlers];
    NSError *error = nil;
    BOOL started = [self.server startWithOptions:@{
        GCDWebServerOption_Port: @(ZXDashboardPort),
        GCDWebServerOption_ServerName: @"ZXTouch Dashboard",
        GCDWebServerOption_AutomaticallySuspendInBackground: @NO,
        GCDWebServerOption_ConnectionClass: [ZXLoggedConnection class]
    } error:&error];
    self.lastError = started ? @"" : (error.localizedDescription ?: @"Unable to start dashboard.");
    if (started) {
        ZXDashboardDebugLog(@"[server] started port=%d pid=%d uptime=%.0fs", (int)self.server.port, getpid(),
                            [NSProcessInfo processInfo].systemUptime);
        // LaunchDaemons can be absent after a jailbreak re-enable or can stop
        // without launchd recovering them. Give the dashboard one guarded
        // chance to restore VNC without waiting for a browser retry cycle.
        // Re-check inside the block: the user may have turned VNC OFF between
        // start and this async hop — that OFF must win, never resurrect.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            if (ZXVNCIsEnabled() && ZXDashboardDaemonEnabled()) {
                [self recoverVNC];
            }
        });
    } else {
        // GCDWebServer reports the bind failure as NSPOSIXErrorDomain/EADDRINUSE;
        // reading the code here keeps the "who owns the port?" answer without a
        // second probe that would make the current owner log a bogus 500.
        BOOL portTaken = (error.domain == NSPOSIXErrorDomain && error.code == EADDRINUSE);
        ZXDashboardDebugLog(@"[server] start failed: %@ (portTaken=%d)", self.lastError, portTaken);
        self.server = nil;
        // The standalone dashboard daemon may already serve this port. That is
        // the healthy post-migration state — not an error worth surfacing.
        if (portTaken) self.lastError = @"";
    }
    return started;
}

- (void)stop
{
    ZXDashboardDebugLog(@"[server] stopped pid=%d", getpid());
    ZXDashboardDebugLog(@"===== session-close pid=%d =====", getpid());
    [self.server stop];
    self.server = nil;
}

@end

static ZXRemoteDashboardServer *ZXDashboardServer;

// Tắt server zxtouch kéo theo tắt VNC: park lựa chọn thật của người dùng rồi
// persist vnc_server_enabled=NO vào cùng plist để Settings UI, dashboardd và
// SpringBoard thấy một trạng thái duy nhất. Bật dashboard lại sẽ khôi phục giá
// trị đã park (xem ZXVNCRestoreParkedChoice).
static void ZXDashboardForceVNCDisabledInConfig(void)
{
    NSMutableDictionary *configuration = [[NSDictionary dictionaryWithContentsOfFile:ZXDashboardConfigPath] mutableCopy];
    if (!configuration) configuration = [NSMutableDictionary dictionary];
    if (!ZXVNCParkAndForceDisabledIn(configuration)) return;
    ZXVNCWriteDashboardConfiguration(configuration);
}

void ZXDashboardReloadConfiguration(void)
{
    ZXDashboardCrashHandlersInstall();
    NSDictionary *configuration = [NSDictionary dictionaryWithContentsOfFile:ZXDashboardConfigPath];
    if (![configuration isKindOfClass:[NSDictionary class]]) {
        NSDictionary *legacy = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.zjx.zxtouch.plist"];
        NSMutableDictionary *migrated = [NSMutableDictionary dictionary];
        id legacyEnabled = legacy[@"zxtouch_remote_dashboard_enabled"];
        if (legacyEnabled) migrated[ZXDashboardEnabledKey] = legacyEnabled;
        if (migrated.count) [migrated writeToFile:ZXDashboardConfigPath atomically:YES];
        configuration = migrated;
    }
    BOOL dashboardEnabled = [configuration[ZXDashboardEnabledKey] boolValue];
    if (!dashboardEnabled) {
        // Dashboard và VNC độc lập: OFF dashboard chỉ dừng HTTP :8688,
        // để nguyên :5901. Bản cũ kill VNC ở đây rồi spawn lại bị EPERM
        // vì mobile không được spawn daemon system.
        [ZXDashboardServer stop];
        ZXDashboardServer = nil;
        return;
    }
    // Turning the dashboard back on restores the VNC choice the OFF path parked,
    // so the user does not have to flip the VNC switch again just to get the
    // stream back after an off/on cycle.
    if (ZXVNCRestoreParkedChoice()) {
        configuration = [NSDictionary dictionaryWithContentsOfFile:ZXDashboardConfigPath];
    }
    ZXVNCApplyEnabledState(configuration[ZXVNCEnabledKey] == nil ? YES : [configuration[ZXVNCEnabledKey] boolValue]);
    BOOL enabled = dashboardEnabled;
    // Each host owns its own port now (daemon :8688, this SpringBoard fallback
    // :8689), so the two never race for one. The probe only guards against a
    // second copy of this same host — starting one anyway would just fail the
    // bind.
    if (!ZXDashboardServer && ZXDashboardPortIsTaken(ZXDashboardPort)) return;
    if (!ZXDashboardServer) ZXDashboardServer = [[ZXRemoteDashboardServer alloc] init];
    ZXDashboardWatchdogStart();
    [ZXDashboardServer start];
}

// ── Standalone dashboard daemon (zxtouch-dashboardd) ─────────────────────
// Same HTTP server, zero SpringBoard hosting: if this process crashes, only the
// dashboard port drops and launchd restarts it — SpringBoard stays alive.
static BOOL ZXDashboardDaemonEnabled(void)
{
    NSDictionary *configuration = [NSDictionary dictionaryWithContentsOfFile:ZXDashboardConfigPath];
    if (![configuration isKindOfClass:[NSDictionary class]]) return NO;
    return [configuration[ZXDashboardEnabledKey] boolValue];
}

// ── Single-instance guard ────────────────────────────────────────────────
// Two daemons used to coexist whenever one survived an upgrade outside launchd
// (postinst only did launchctl unload/load): the loser then retried to bind the
// port forever, filled dashboardd.log and drove VNC twice. flock() keeps the
// invariant in the process itself. The kernel drops the lock when the holder
// dies, so a stale lock file can never wedge the daemon, and the path sits next
// to dashboardd.log / dashboard-debug.log where the other daemon files live.
static int ZXDashboardDaemonLockFD = -1;
// Tracks the "port busy" message so the retry loop logs the transition once
// instead of repeating itself every 30 seconds.
static BOOL ZXDashboardPortConflictNoted = NO;

static BOOL ZXDashboardDaemonAcquireLock(void)
{
    NSString *path = @"/var/mobile/Library/ZXTouch/dashboardd.lock";
    int fd = open(path.fileSystemRepresentation, O_RDWR | O_CREAT, 0644);
    // Fail open: an unusable lock file must not cost the user the dashboard.
    if (fd < 0) return YES;
    if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
        close(fd);
        return NO;
    }
    ZXDashboardDaemonLockFD = fd;
    if (ftruncate(fd, 0) == 0) {
        dprintf(fd, "%d\n", getpid());
    }
    return YES;
}

int ZXDashboardDaemonMain(void)
{
    // Take the lock before anything writes a session marker: a copy that loses
    // the race must not leave a trailing session-open behind, or the next real
    // session would report a crash that never happened. NSLog reaches
    // dashboardd.log through launchd's stderr redirection.
    if (!ZXDashboardDaemonAcquireLock()) {
        // Another daemon already serves the port. Exit cleanly so launchd's
        // KeepAlive (SuccessfulExit=false) leaves this copy stopped instead of
        // restarting it into the same conflict every 30 seconds.
        NSLog(@"[dashboardd] another instance holds the lock, exiting pid=%d", getpid());
        return 0;
    }
    ZXDashboardCrashHandlersInstall();
    ZXDashboardDaemonTerminationInstall();
    ZXDashboardWatchdogStart();
    __block ZXRemoteDashboardServer *server = [[ZXRemoteDashboardServer alloc] init];
    __block BOOL vncStateKnown = NO;
    __block BOOL lastVNCEnabled = YES;
    static int notifyToken = 0;
    notify_register_dispatch(ZXDashboardConfigurationNotification, &notifyToken,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(int token) {
        (void)token;
        // The Settings app writes the shared plist and posts this notification.
        // Apply the VNC switch here as well as in the SpringBoard path so a
        // running standalone dashboard cannot leave the old server alive.
        // Dashboard OFF chỉ dừng HTTP, để nguyên VNC (độc lập).
        if (!ZXDashboardDaemonEnabled()) {
            lastVNCEnabled = ZXVNCIsEnabled();
            vncStateKnown = YES;
            [server stop];
            return;
        }
        ZXVNCRestoreParkedChoice();
        BOOL enabled = ZXVNCIsEnabled();
        ZXVNCApplyEnabledState(enabled);
        lastVNCEnabled = enabled;
        vncStateKnown = YES;
    });
    for (;;) {
        @autoreleasepool {
            if (!ZXDashboardDaemonEnabled()) {
                // Poll fallback if the notify was missed: dashboard OFF chỉ
                // dừng HTTP, không động tới VNC.
                vncStateKnown = YES;
                lastVNCEnabled = ZXVNCIsEnabled();
                if (server.server.running) [server stop];
            } else {
            ZXVNCRestoreParkedChoice();
            BOOL enabled = ZXVNCIsEnabled();
            // Re-apply not only when the switch changes but whenever the server
            // has drifted from it: this daemon is what keeps :5901 up now that
            // the LaunchDaemon carries no KeepAlive, and it is also what keeps
            // the server dead when the switch is off.
            BOOL drifted = enabled != ZXVNCProbePort(5901);
            if (!vncStateKnown || enabled != lastVNCEnabled || drifted) {
                ZXVNCApplyEnabledState(enabled);
                lastVNCEnabled = enabled;
                vncStateKnown = YES;
            }
            if (!server.server.running && ![server start]) {
                // Port busy (embedded SpringBoard server until the next
                // respring) or transient failure — wait, never crash-loop.
                // Only the transition is logged: repeating the same line every
                // 30 s for hours is what buried the real events in this log.
                if (!ZXDashboardPortConflictNoted) {
                    ZXDashboardDebugLog(@"[dashboardd] :%d unavailable (%@), retrying", ZXDashboardPort,
                                        server.lastError);
                    ZXDashboardPortConflictNoted = YES;
                }
            } else if (ZXDashboardPortConflictNoted) {
                ZXDashboardDebugLog(@"[dashboardd] :%d available", ZXDashboardPort);
                ZXDashboardPortConflictNoted = NO;
            }
            }
        }
        sleep(30);
    }
    return 0;
}

#else

static NSString *ZXDashboardSettingsLastError = @"";
static NSString *ZXVNCSettingsLastError = @"";

static NSMutableDictionary *ZXDashboardConfiguration(void)
{
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:ZXDashboardConfigPath];
    if ([stored isKindOfClass:[NSDictionary class]]) return [stored mutableCopy];

    NSMutableDictionary *configuration = [NSMutableDictionary dictionary];
    NSUserDefaults *legacyDefaults = [NSUserDefaults standardUserDefaults];
    id legacyEnabled = [legacyDefaults objectForKey:@"zxtouch_remote_dashboard_enabled"];
    if (legacyEnabled) configuration[ZXDashboardEnabledKey] = legacyEnabled;
    return configuration;
}

// Best-effort: Settings process tự kill VNC ngay khi user OFF để không phải chờ
// dashboardd/SpringBoard nhận notify (đóng cửa sổ 0-30s). Thất bại cũng không sao
// vì daemon + SpringBoard sẽ kill lại khi nhận notify.
// Shell-less: system()/killall cần /bin/sh (không có trên rootless) nên dùng
// sysctl + kill() trực tiếp.
static void ZXSettingsKillVNCBestEffort(void)
{
#if defined(CTL_KERN) && defined(KERN_PROC)
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0 || size == 0) return;
    struct kinfo_proc *procs = malloc(size);
    if (!procs) return;
    if (sysctl(mib, 4, procs, &size, NULL, 0) != 0) { free(procs); return; }
    size_t count = size / sizeof(struct kinfo_proc);
    for (size_t i = 0; i < count; i++) {
        const char *name = procs[i].kp_proc.p_comm;
        if (name && strcmp(name, "trollvncserver") == 0) {
            kill(procs[i].kp_proc.p_pid, SIGKILL);
        }
    }
    free(procs);
#else
    // Fallback khi không có sysctl: spawn killall bằng đường dẫn tuyệt đối.
    static const char * const killallCandidates[] = {
        "/var/jb/usr/bin/killall",
        "/usr/bin/killall",
        NULL
    };
    for (int i = 0; killallCandidates[i]; i++) {
        if (access(killallCandidates[i], X_OK) != 0) continue;
        pid_t pid = 0;
        char * const argv[] = {
            (char *)"killall", (char *)"-9",
            (char *)"trollvncserver", NULL
        };
        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
        posix_spawnattr_t attrs;
        posix_spawnattr_init(&attrs);
        if (posix_spawn(&pid, killallCandidates[i], &actions, &attrs, argv, environ) == 0) {
            int status = 0;
            for (int t = 0; t < 50; t++) {
                if (waitpid(pid, &status, WNOHANG) == pid) break;
                usleep(100 * 1000);
            }
        }
        posix_spawn_file_actions_destroy(&actions);
        posix_spawnattr_destroy(&attrs);
        break;
    }
#endif
}

BOOL ZXRemoteDashboardSetEnabled(BOOL enabled)
{
    NSMutableDictionary *configuration = ZXDashboardConfiguration();
    configuration[ZXDashboardEnabledKey] = @(enabled);
    if (enabled) {
        // Migration một lần cho bản cũ đã park VNC khi OFF dashboard.
        // Từ nay dashboard và VNC độc lập: OFF dashboard chỉ dừng :8688,
        // không kill :5901 nữa (mobile spawn daemon system bị EPERM).
        ZXVNCRestoreParkedIn(configuration);
    }
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
    // No token: open http://<iphone-ip>:<port>/ directly from the same Wi-Fi.
    // The two hosts sit on different ports now, so point at whichever one is
    // actually listening — a dead daemon must not hide the SpringBoard fallback
    // that is still serving. Bind-probe, never connect: opening a connection
    // here would make the owner log a bogus 500.
    NSString *host = ZXDashboardIPAddress() ?: @"iPad-IP-address";
    uint16_t port = ZXDashboardDaemonPort;
    if (!ZXDashboardPortIsTaken(ZXDashboardDaemonPort) && ZXDashboardPortIsTaken(ZXDashboardFallbackPort)) {
        port = ZXDashboardFallbackPort;
    }
    return [NSString stringWithFormat:@"http://%@:%d/", host, port];
}

NSString *ZXRemoteDashboardLastError(void)
{
    return ZXDashboardSettingsLastError ?: @"";
}

BOOL ZXVNCServerSetEnabled(BOOL enabled)
{
    NSMutableDictionary *configuration = ZXDashboardConfiguration();
    configuration[ZXVNCEnabledKey] = @(enabled);
    // Người dùng tự gạt công tắc VNC: lựa chọn này thay thế giá trị mà lần tắt
    // dashboard đã park, nếu không lần bật dashboard sau sẽ ghi đè trở lại.
    [configuration removeObjectForKey:ZXVNCParkedKey];
    NSError *directoryError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[ZXDashboardConfigPath stringByDeletingLastPathComponent]
                                withIntermediateDirectories:YES attributes:nil error:&directoryError];
    BOOL saved = directoryError == nil && [configuration writeToFile:ZXDashboardConfigPath atomically:YES];
    if (!saved) {
        ZXVNCSettingsLastError = directoryError.localizedDescription ?: @"Unable to save VNC server settings.";
        return NO;
    }
    if (!enabled) ZXSettingsKillVNCBestEffort();
    if (saved) notify_post(ZXDashboardConfigurationNotification);
    return saved;
}

BOOL ZXVNCServerIsEnabled(void)
{
    NSDictionary *configuration = ZXDashboardConfiguration();
    if (configuration[ZXVNCEnabledKey] == nil) return YES;
    return [configuration[ZXVNCEnabledKey] boolValue];
}

NSString *ZXVNCServerLastError(void)
{
    return ZXVNCSettingsLastError ?: @"";
}

#endif
