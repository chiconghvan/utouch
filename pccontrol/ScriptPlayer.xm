#import "ScriptPlayer.h"
#include <roothide.h>
#include "Play.h"
#include "SocketServer.h"
#include "Process.h"
#include "Task.h"
#include "AlertBox.h"
#include "Config.h"
#include "Common.h"
#import <sys/stat.h>
#include <errno.h>
#include <signal.h>

static BOOL isPlaying = false;

static NSString *ZXShellQuote(NSString *value)
{
    if (!value) return @"''";
    return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

static NSString *ZXFirstExecutablePath(NSArray<NSString *> *candidates)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if (path.length > 0 && [fm isExecutableFileAtPath:path]) {
            return path;
        }
    }
    return nil;
}

static NSString *ZXPythonPath(void)
{
    // Prefer specific versions before the generic `python3` symlink. If a
    // previous install of ZXTouch (or another package) pointed `python3` at a
    // broken interpreter (e.g. Procursus 3.7 whose libpython lives at a path
    // dyld can't resolve on rootless), a versioned binary is more likely to
    // actually load. 3.7 is dropped entirely — it aborts at dyld on 15+.
    return ZXFirstExecutablePath(@[
        jbroot(@"/usr/bin/python3.12"),
        jbroot(@"/usr/bin/python3.11"),
        jbroot(@"/usr/bin/python3.10"),
        jbroot(@"/usr/bin/python3.9"),
        jbroot(@"/usr/bin/python3.8"),
        jbroot(@"/usr/bin/python3"),
        @"/var/jb/usr/bin/python3.12",
        @"/var/jb/usr/bin/python3.11",
        @"/var/jb/usr/bin/python3.10",
        @"/var/jb/usr/bin/python3.9",
        @"/var/jb/usr/bin/python3.8",
        @"/var/jb/usr/bin/python3",
        @"/usr/bin/python3.12",
        @"/usr/bin/python3.11",
        @"/usr/bin/python3.10",
        @"/usr/bin/python3.9",
        @"/usr/bin/python3.8",
        @"/usr/bin/python3"
    ]);
}

static NSString *ZXShellPath(void)
{
    return ZXFirstExecutablePath(@[
        jbroot(@"/bin/sh"),
        jbroot(@"/usr/bin/sh"),
        @"/var/jb/bin/sh",
        @"/var/jb/usr/bin/sh",
        @"/bin/sh",
        @"/usr/bin/sh"
    ]) ?: @"/bin/sh";
}

static NSString *ZXPythonModulePath(void)
{
    // The zxtouch module ships under /usr/share/zxtouch/python and the postinst
    // also copies it into every installed Python's site/dist-packages. Include
    // the share path unconditionally so scripts still find `import zxtouch`
    // even if the copy step skipped a Python version installed later.
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *path in @[
        jbroot(@"/usr/share/zxtouch/python"),
        jbroot(@"/usr/lib/python3/site-packages"),
        jbroot(@"/usr/lib/python3/dist-packages"),
        @"/var/jb/usr/share/zxtouch/python",
        @"/var/jb/usr/lib/python3/site-packages",
        @"/var/jb/usr/lib/python3/dist-packages",
        @"/usr/lib/python3/site-packages",
        @"/usr/lib/python3/dist-packages"
    ]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [paths addObject:path];
        }
    }
    return [paths componentsJoinedByString:@":"];
}

@implementation ScriptPlayer
{
    int repeatTime;
    float interval;
    float speed;
    NSString* scriptBundlePath;
    UIWindow *_playIndicator;
    int currentScriptType; // -1 no task has specified; 0 not playing but has upcoming task; 1 raw file playing; 2 py file playing
    NSTimer *replayTimer;
    UIView *circleView;
    volatile sig_atomic_t scriptPlayForceStop;
    volatile sig_atomic_t scriptStopRequested;
    volatile sig_atomic_t scriptPauseRequested;
    NSCondition *pauseCondition;
    CFRunLoopRef replayRunLoop;
    pid_t pythonProcessGroup;
    Boolean switchAppBeforePlaying;
    int _completedRuns;
}

+ (NSString *)validateScriptAtPath:(NSString *)path
{
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return @"Script file not found.";
    }
    NSString *pythonPath = ZXPythonPath();
    if (!pythonPath) {
        return @"Python is not installed on this device.";
    }
    NSString *modulePath = ZXPythonModulePath();
    NSString *envPrefix = modulePath.length > 0 ? [NSString stringWithFormat:@"PYTHONPATH=%@ ", ZXShellQuote(modulePath)] : @"";
    // The checker writes <path>.diag.json itself; exit code 0 covers "ran",
    // including scripts that legitimately have diagnostics.
    NSString *command = [NSString stringWithFormat:@"%@%@ -m zxtouch.checker %@ 2>&1",
                         envPrefix, ZXShellQuote(pythonPath), ZXShellQuote(path)];
    int status = system2([command UTF8String], NULL, NULL);
    if (status != 0) {
        return [NSString stringWithFormat:@"Checker exited with status %d.", status];
    }
    return nil;
}

- (BOOL)isPlaying {
    return isPlaying;
}

- (int)getCompletedRuns {
    return _completedRuns;
}

- (NSString*)getCurrentBundlePath {
    if (!scriptBundlePath)
    {
        return @"";
    }
    return scriptBundlePath;
}

- (void)setPath:(NSString*)path {
    if (isPlaying)
    {
        NSLog(@"com.zjx.springboard: cannot change script path because a script is playing.");
        return;
    }
    scriptBundlePath = path;
}

- (void)setRepeatTime:(int)rt {
    if (isPlaying)
    {
        NSLog(@"com.zjx.springboard: cannot change repeat time because a script is playing.");
        return;
    }
    repeatTime = rt;
}

- (void)setInterval:(float)intv {
    if (isPlaying)
    {
        NSLog(@"com.zjx.springboard: cannot change interval because a script is playing.");
        return;
    }
    interval = intv;
}

- (void)setSpeed:(float)sp {
    if (isPlaying)
    {
        NSLog(@"com.zjx.springboard: cannot change speed because a script is playing.");
        return;
    }
    speed = sp;
}

- (void)setSwitchApp:(BOOL)value {
    if (isPlaying)
    {
        NSLog(@"com.zjx.springboard: cannot change speed because a script is playing.");
        return;
    }
    switchAppBeforePlaying = value;
}


- (id)init {
    self = [super init];
    if (self)
    {
        [self clear];
        scriptStopRequested = 0;
        scriptPauseRequested = 0;
        pauseCondition = [[NSCondition alloc] init];
        replayRunLoop = NULL;
        pythonProcessGroup = 0;
    }
    return self;
}

- (id)initWithPath:(NSString*)path {
    self = [super init];
    if (self)
    {
        scriptBundlePath = path;
        currentScriptType = -1;
        scriptStopRequested = 0;
        scriptPauseRequested = 0;
        pauseCondition = [[NSCondition alloc] init];
        replayRunLoop = NULL;
        pythonProcessGroup = 0;
    }
    return self;
}

-(int)runScript:(NSError**)error {
    scriptStopRequested = 0;
    pythonProcessGroup = 0;

    if (!scriptBundlePath)
    {
        NSLog(@"com.zjx.springboard: Unable to run the script. ScriptBundlePath not set.");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. ScriptBundlePath not set.\r\n"}];
        return -1;
    }

    BOOL isDir;
    if (![[NSFileManager defaultManager] fileExistsAtPath:scriptBundlePath isDirectory:&isDir] || !isDir)
    {
        NSLog(@"com.zjx.springboard: Unable to run the script. Path not found or it is not a directory.");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Path not found or it is not a directory.\r\n"}];
        return -1;
    }

    // read info.plist into dictionary
    NSString *infoFilePath = [NSString stringWithFormat:@"%@/info.plist", scriptBundlePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:infoFilePath isDirectory:&isDir])
    {
        NSLog(@"com.zjx.springboard: Unable to run the script. Info.plist not found.");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Info.plist not found.\r\n"}];
        return -1;
    }
    NSDictionary *scriptInfo = [NSDictionary dictionaryWithContentsOfFile:infoFilePath];
    // get entry file extension
    NSString *entryFileName = scriptInfo[@"Entry"];
    NSString *fileExtension = [entryFileName pathExtension];

    NSString *foregroundApp = scriptInfo[@"FrontApp"];
    // call different functions depending on file extension
    isPlaying = true;
    notifyScriptState(@"started");

    // show indicator
    dispatch_async(dispatch_get_main_queue(), ^{
        // Attach to a UIWindowScene — a scene-less UIWindow is fatal from iOS 17
        // on. See the matching comment in Record.xm's startRecording.
        CGRect indicatorFrame = CGRectMake(0, 0, 10*2, 10*2);
        UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
        if (scene) {
            _playIndicator = [[UIWindow alloc] initWithWindowScene:scene];
            _playIndicator.frame = indicatorFrame;
        } else {
            _playIndicator = [[UIWindow alloc] initWithFrame:indicatorFrame];
        }
        UIViewController *indicatorRoot = [[UIViewController alloc] init];
        indicatorRoot.view.backgroundColor = [UIColor clearColor];
        _playIndicator.rootViewController = indicatorRoot;
        _playIndicator.windowLevel = UIWindowLevelStatusBar;
        [_playIndicator setBackgroundColor:[UIColor clearColor]];
        [_playIndicator setUserInteractionEnabled:NO];

        circleView = [[UIView alloc] initWithFrame:indicatorFrame];

        //circleView.alpha = 1;
        circleView.layer.cornerRadius = 10;  // half the width/height
        circleView.backgroundColor = [UIColor greenColor];
        [_playIndicator addSubview:circleView];

        _playIndicator.hidden = NO;
    });

    NSString *entryFilePath = [scriptBundlePath stringByAppendingPathComponent:entryFileName];
    NSLog(@"com.zjx.sprinboard: currently playing: %@. Repeat time: %d", entryFilePath, repeatTime);
    

    if ([fileExtension isEqualToString:@"raw"])
    {
        currentScriptType = 1;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            NSError *err = nil;
            [self playFromRawFile:entryFilePath foregroundApp:foregroundApp err:&err];
        }); 
    }
    else if ([fileExtension isEqualToString:@"py"])
    {
        currentScriptType = 2;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            NSError *err = nil;
            [self playFromPythonFile:entryFilePath foregroundApp:foregroundApp err:&err];
        });
        
    }
}

// play the script
- (int)play:(NSError**)error
{
    if (isPlaying)
    {
        NSLog(@"com.zjx.springboard: Unable to run the script. Another script is currently running.");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Another script is currently running.\r\n"}];
        return -1;
    }
    scriptPlayForceStop = false;
    scriptPauseRequested = 0;
    _completedRuns = 0;
    [self runScript:error];
}

- (BOOL)isPaused
{
    return scriptPauseRequested != 0;
}

- (void)pause
{
    if (!isPlaying) return;
    scriptPauseRequested = 1;
    [pauseCondition lock];
    [pauseCondition broadcast];
    [pauseCondition unlock];

    pid_t processGroup = pythonProcessGroup;
    if (currentScriptType == 2 && processGroup > 0) {
        kill(-processGroup, SIGSTOP);
    }
}

- (void)resume
{
    scriptPauseRequested = 0;
    [pauseCondition lock];
    [pauseCondition broadcast];
    [pauseCondition unlock];

    pid_t processGroup = pythonProcessGroup;
    if (currentScriptType == 2 && processGroup > 0) {
        kill(-processGroup, SIGCONT);
    }
}

- (BOOL)waitUntilRunnable
{
    [pauseCondition lock];
    while (scriptPauseRequested && !scriptPlayForceStop) {
        [pauseCondition wait];
    }
    BOOL shouldContinue = !scriptPlayForceStop;
    [pauseCondition unlock];
    return shouldContinue;
}

- (BOOL)waitForMicroseconds:(int)microseconds
{
    NSTimeInterval remaining = MAX(0.0, (double)microseconds / 1000000.0);
    while (remaining > 0.0) {
        if (![self waitUntilRunnable]) return NO;

        NSDate *started = [NSDate date];
        [pauseCondition lock];
        if (scriptPauseRequested && !scriptPlayForceStop) {
            [pauseCondition unlock];
            continue;
        }
        NSTimeInterval slice = MIN(remaining, 0.05);
        [pauseCondition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:slice]];
        BOOL shouldContinue = !scriptPlayForceStop;
        BOOL paused = scriptPauseRequested != 0;
        [pauseCondition unlock];

        if (!shouldContinue) return NO;
        if (!paused) remaining -= -[started timeIntervalSinceNow];
    }
    return [self waitUntilRunnable];
}


-(void)playFromRawFile:(NSString*) filePath foregroundApp:(NSString*)foregroundApp err:(NSError**)err
{
    isPlaying = true;
    if (switchAppBeforePlaying)
    {
        bringAppForeground(foregroundApp);
    }

    // Mirror the python path: leave Start/Finish markers in the runtime log.
    NSString *rawOutputLog = @"/var/mobile/Library/ZXTouch/coreutils/ScriptRuntime/output";
    {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"MM-dd-yyyy HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"%@: Start running script. Script path: %@\n",
                          [fmt stringFromDate:[NSDate date]], filePath];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:rawOutputLog];
        if (![[NSFileManager defaultManager] fileExistsAtPath:rawOutputLog])
            [line writeToFile:rawOutputLog atomically:YES encoding:NSUTF8StringEncoding error:nil];
        else if (fh) {
            @try { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
            @catch (NSException *e) { NSLog(@"com.zjx.springboard: cannot append start marker: %@", e.reason); }
        }
    }

    FILE *file = fopen([filePath UTF8String], "r");

    if (!file)
    {
        showAlertBox(@"Error", [NSString stringWithFormat:@"Cannot play this script because zxtouch cannot open the file. File path: %@", filePath], 999);
        [self clear];
        return;
    }
    
    char buffer[256];
    
    BOOL stoppedByUser = NO;
    while (fgets(buffer, sizeof(char)*256, file) != NULL)
    {
        if (![self waitUntilRunnable])
        {
            stoppedByUser = YES;
            break;
        }

        int taskType = 0;
        int taskSleep = 0;
        sscanf(buffer, "%2d%d", &taskType, &taskSleep);
        if (taskType == TASK_USLEEP) {
            if (speed > 0 && speed != 1) taskSleep = (int)(taskSleep / speed);
            if (![self waitForMicroseconds:taskSleep]) {
                stoppedByUser = YES;
                break;
            }
            continue;
        }

        if (speed > 0 && speed != 1)
        {
            processTask((UInt8*)buffer, NULL);
        }
        else
        {
            processTask((UInt8*)buffer, NULL);
        }

    }
    fclose(file);

    {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"MM-dd-yyyy HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"%@: Finish running script%@. Script path: %@\n",
                          [fmt stringFromDate:[NSDate date]],
                          stoppedByUser ? @" (stopped by user)" : @"",
                          filePath];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:rawOutputLog];
        if (fh) {
            @try { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
            @catch (NSException *e) { NSLog(@"com.zjx.springboard: cannot append finish marker: %@", e.reason); }
        }
    }
    if (!stoppedByUser) [self playHasStopped];
}

-(void) playFromPythonFile:(NSString*) filePath foregroundApp:(NSString*) foregroundApp err:(NSError**) err
{
    isPlaying = true;

    if (switchAppBeforePlaying)
    {
        bringAppForeground(foregroundApp);
    }
    
    NSString *pythonPath = ZXPythonPath();
    if (!pythonPath)
    {
        showAlertBox(@"Python not installed",
                     @"ZXTouch could not find a working python3 on this device.\n\nOpen Sileo and install the 'python3' package from Procursus, then reinstall ZXTouch so it can register the new interpreter.",
                     999);
        [self clear];
        return;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath])
    {
        showAlertBox(@"Error", [NSString stringWithFormat:@"Cannot play this script. Script file not found in bdl folder. Script path: %@", filePath], 999);
        [self clear];
        return;
    }
    // Ensure output log file exists so the >> redirect doesn't fail
    NSString *outputLog = @"/var/mobile/Library/ZXTouch/coreutils/ScriptRuntime/output";
    if (![[NSFileManager defaultManager] fileExistsAtPath:outputLog])
        [@"" writeToFile:outputLog atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSString *dateWrapper = @"/var/mobile/Library/ZXTouch/coreutils/ScriptRuntime/add_datetime.sh";
    NSString *shellPath = ZXShellPath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:dateWrapper]) {
        // Resolve date through jbroot() first so the wrapper works under the
        // randomized roothide prefix; rootless/static fallbacks stay for safety.
        NSString *datePath = ZXFirstExecutablePath(@[
            jbroot(@"/usr/bin/date"),
            jbroot(@"/bin/date"),
            @"/var/jb/usr/bin/date",
            @"/var/jb/bin/date",
            @"/usr/bin/date",
            @"/bin/date"
        ]) ?: @"/usr/bin/date";
        NSString *wrapper = [NSString stringWithFormat:@"#!%@\nOUTPUT=/var/mobile/Library/ZXTouch/coreutils/ScriptRuntime/output\nDATE=%@\nif [ ! -x \"$DATE\" ]; then DATE=/usr/bin/date; fi\nif [ ! -x \"$DATE\" ]; then DATE=/bin/date; fi\necho \"$($DATE '+%%m-%%d-%%Y %%T'): Start running script. Script path: $1\" >> \"$OUTPUT\"\nwhile IFS= read -r line; do\n    echo \"$($DATE '+%%m-%%d-%%Y %%T'): $line\" >> \"$OUTPUT\"\ndone\necho \"$($DATE '+%%m-%%d-%%Y %%T'): Finish running script. Script path: $1\" >> \"$OUTPUT\"\n", shellPath, datePath];
        [wrapper writeToFile:dateWrapper atomically:YES encoding:NSUTF8StringEncoding error:nil];
        chmod(dateWrapper.UTF8String, 0755);
    }

    // A bundle records where the script's assets live when they are not next to
    // the entry file (an editor run stages the code in a scratch bundle of its
    // own). That folder then stands in for the script's own folder: the runtime
    // resolves relative asset names against it, and it is the working directory,
    // so relative file I/O lands beside the assets rather than in the scratch.
    NSDictionary *assetInfo = [NSDictionary dictionaryWithContentsOfFile:
        [[filePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"info.plist"]];
    NSString *assetDir = assetInfo[@"AssetDir"];
    BOOL assetDirIsDirectory = NO;
    if (![assetDir isKindOfClass:[NSString class]] || assetDir.length == 0 ||
        ![[NSFileManager defaultManager] fileExistsAtPath:assetDir isDirectory:&assetDirIsDirectory] ||
        !assetDirIsDirectory) {
        assetDir = nil;
    }

    NSString *scriptDir = assetDir.length ? assetDir : [filePath stringByDeletingLastPathComponent];
    NSString *statusFile = @"/var/mobile/Library/ZXTouch/coreutils/ScriptRuntime/last_python_status";
    NSString *pythonModulePath = ZXPythonModulePath();
    NSMutableString *envPrefix = [NSMutableString string];
    if (pythonModulePath.length > 0) {
        [envPrefix appendFormat:@"PYTHONPATH=%@ ", ZXShellQuote(pythonModulePath)];
    }
    if (assetDir.length > 0) {
        [envPrefix appendFormat:@"ZX_ASSET_DIR=%@ ", ZXShellQuote(assetDir)];
    }
    NSString *commandToRun = [NSString stringWithFormat:@"rm -f %@; (cd %@ && %@%@ -u -m zxtouch.runner %@ 2>&1; echo $? > %@) | %@ %@ %@; exit $(cat %@ 2>/dev/null || echo 1)",
                              ZXShellQuote(statusFile),
                              ZXShellQuote(scriptDir),
                              envPrefix,
                              ZXShellQuote(pythonPath),
                              ZXShellQuote(filePath),
                              ZXShellQuote(statusFile),
                              ZXShellQuote(shellPath),
                              ZXShellQuote(dateWrapper),
                              ZXShellQuote(filePath),
                              ZXShellQuote(statusFile)];
    NSLog(@"com.zjx.springboard: command to run for running py file %@", commandToRun);

    int shellExitCode = system2CancelableWithPause([commandToRun UTF8String], NULL, NULL,
                                                    &pythonProcessGroup, &scriptStopRequested,
                                                    &scriptPauseRequested);
    BOOL stoppedByUser = scriptStopRequested != 0;
    scriptStopRequested = 0;
    NSString *statusText = [NSString stringWithContentsOfFile:statusFile encoding:NSUTF8StringEncoding error:nil];
    int pythonExitCode = statusText ? [statusText intValue] : shellExitCode;
    // Always leave a Finish marker in the runtime log (the shell wrapper also
    // appends one when the pipe closes; this line adds the exit code / stop
    // reason so "Start running script" is never left dangling).
    {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"MM-dd-yyyy HH:mm:ss";
        NSString *stamp = [fmt stringFromDate:[NSDate date]];
        NSString *finish = stoppedByUser
            ? [NSString stringWithFormat:@"%@: Finish running script (stopped by user). Script path: %@\n", stamp, filePath]
            : [NSString stringWithFormat:@"%@: Finish running script (exit code %d). Script path: %@\n", stamp, pythonExitCode, filePath];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:outputLog];
        if (fh) {
            @try {
                [fh seekToEndOfFile];
                [fh writeData:[finish dataUsingEncoding:NSUTF8StringEncoding]];
                [fh closeFile];
            } @catch (NSException *e) {
                NSLog(@"com.zjx.springboard: cannot append finish marker: %@", e.reason);
            }
        }
    }
    if (!stoppedByUser && pythonExitCode != 0) {
        NSString *title = @"Script Error";
        NSString *message;
        NSString *logTail = [NSString stringWithContentsOfFile:outputLog encoding:NSUTF8StringEncoding error:nil] ?: @"";
        BOOL dyldLibpythonMissing = [logTail rangeOfString:@"Library not loaded" options:0].location != NSNotFound &&
                                    [logTail rangeOfString:@"libpython" options:0].location != NSNotFound;
        if (statusText == nil && shellExitCode < 0) {
            // system2 failed before python could run — spawn was denied or the
            // shell was unusable. Common on semi-jailbreaks with stripped
            // entitlements. Check Console.app for `system2` NSLog output.
            title = @"Script could not launch";
            message = @"ZXTouch could not start a shell to run the script (posix_spawn failed).\n\nOpen Console.app (or `oslog`) and search for `com.zjx.springboard: system2` to see the exact error.";
        } else if (pythonExitCode == 134 && dyldLibpythonMissing) {
            // 134 = SIGABRT. Dyld couldn't find libpython — the interpreter
            // was linked against a path that doesn't exist on this JB (classic
            // Procursus python3.7 on rootless).
            title = @"Python interpreter is broken";
            message = @"The installed python3 aborted at launch because dyld cannot find its libpython dylib.\n\nInstall the 'python3' package (3.9 or newer) from Sileo (Procursus), then reinstall ZXTouch so it re-picks the working interpreter.";
        } else {
            message = [NSString stringWithFormat:@"Python script exited with code %d. Open Logs for the traceback.", pythonExitCode];
        }
        NSLog(@"com.zjx.springboard: %@ — %@", title, message);
        showAlertBox(title, message, 999);
    }
    if (!stoppedByUser) [self playHasStopped];
}

- (void)replay:(NSTimer*)nstimer {
    NSLog(@"com.zjx.springboard: script is replaying...");
    if (![self waitUntilRunnable]) {
        CFRunLoopStop(CFRunLoopGetCurrent());
        return;
    }
    NSError *err = nil;

    [self runScript:&err];

    CFRunLoopStop(CFRunLoopGetCurrent());
}

-(void) playHasStopped
{
    // If forceStop already called clear(), isPlaying is false — don't show finished popup
    if (!isPlaying) return;

    NSLog(@"com.zjx.springboard: script has finished");
    _completedRuns++;

    // check whether need to replay
    if (repeatTime != 0)
    {    
        dispatch_async(dispatch_get_main_queue(), ^{
            circleView.backgroundColor = [UIColor orangeColor];
        });

        NSLog(@"com.zjx.springboard: need replay. Replay time: %d", repeatTime);

        replayTimer = [NSTimer scheduledTimerWithTimeInterval:interval
         target:self selector:@selector(replay:) 
         userInfo:nil repeats:NO];
        repeatTime--;

        currentScriptType = 0;

        replayRunLoop = CFRunLoopGetCurrent();
        CFRunLoopRun();
        replayRunLoop = NULL;
    }
    else
    {
        playHasStoppedCallBack();
        [self clear];
    }



}

- (void)clear {
    BOOL hadActiveScript = isPlaying || currentScriptType != -1;
    repeatTime = 0;
    interval = 0.0f;
    speed = 1.0f;
    scriptBundlePath = nil;
    isPlaying = false;
    currentScriptType = -1;
    scriptPauseRequested = 0;
    [pauseCondition lock];
    [pauseCondition broadcast];
    [pauseCondition unlock];
    //scriptPlayForceStop = false;

    // remove indicator
    dispatch_async(dispatch_get_main_queue(), ^{
        _playIndicator.hidden = YES;
        _playIndicator = nil;
    });

    if (replayTimer)
        [replayTimer invalidate];

    replayTimer = nil;

    if (replayRunLoop) {
        CFRunLoopStop(replayRunLoop);
        replayRunLoop = NULL;
    }

    if (hadActiveScript) notifyScriptState(@"stopped");
}

- (void)forceStop:(NSError**)error {
    if (currentScriptType == -1)
    {
        NSLog(@"com.zjx.springboard: Cannot stop playing script. No script is playing.");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Cannot stop script. No script is playing.\r\n"}];
        return;
    }

    if (currentScriptType == 0)
    {
        scriptPlayForceStop = true;
        [self clear];
    }
    else if (currentScriptType == 1)
    {
        // make stop to be true
        scriptPlayForceStop = true;
        [self clear];
    }
    else if (currentScriptType == 2)
    {
        scriptStopRequested = 1;
        pid_t processGroup = pythonProcessGroup;
        if (processGroup > 0 && kill(-processGroup, SIGKILL) != 0 && errno != ESRCH) {
            NSLog(@"com.zjx.springboard: failed to stop Python process group %d: errno %d",
                  processGroup, errno);
        }
        [pauseCondition lock];
        [pauseCondition broadcast];
        [pauseCondition unlock];
        [self clear];
    }
    else
    {
        NSLog(@"com.zjx.springboard: unknown currently playing script type.");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Cannot stop script. Unkonwn currently playing script type.\r\n"}];
        return;
    }

}

@end
