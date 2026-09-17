#include "Play.h"
#include "SocketServer.h"
#include "Process.h"
#include "Task.h"
#include "AlertBox.h"
#include "Config.h"
#import "ScriptPlayer.h"
#include "Common.h"
#import <CoreFoundation/CoreFoundation.h>

static BOOL switchAppBeforeRunScript = true;
ScriptPlayer *scriptPlayer;
static float currentRunSpeed = 1.0f;
NSString * const ZXScriptStateDidChangeNotification = @"com.zjx.zxtouch.script-state-changed";

void notifyScriptState(NSString *state)
{
    if (!state) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:ZXScriptStateDidChangeNotification
                                                            object:nil
                                                          userInfo:@{ @"state": state }];
    });
}

void initScriptPlayer()
{
    scriptPlayer = [[ScriptPlayer alloc] init];
}

void updateSwtichAppBeforeRunScript(BOOL value)
{
    switchAppBeforeRunScript = value;
}

int playScript(UInt8* path, NSError **error)
{
    if (!scriptPlayer)
    {
        NSLog(@"com.zjx.springboard: Unable to run the script. Internal error. scriptPlayer is null.");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Internal error. scriptPlayer is null.\r\n"}];
        return -1;
    }
    // read config file to get repeat time etc
    int repeatTime = 0;
    float sleepBetweenRun = 0;
    float playSpeed = 1.0f;
    
    NSLog(@"com.zjx.springboard: path: %s", path);
    NSDictionary *config = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:SCRIPT_PLAY_CONFIG_PATH])
        config = [[NSDictionary alloc] initWithContentsOfFile:SCRIPT_PLAY_CONFIG_PATH];

    if (config)
    {
        // App-launched scripts only use per-script settings written by the app.
        // Floating panel settings are handled separately so they do not leak.
        NSDictionary *individualConfigs = config[@"individual_configs"];
        NSDictionary *scriptInfo = [individualConfigs valueForKey:[NSString stringWithFormat:@"%s", path]];

        if (scriptInfo)
        {
            repeatTime = [scriptInfo[@"repeat_times"] intValue];
            sleepBetweenRun = [scriptInfo[@"interval"] floatValue];
            float sp = [scriptInfo[@"speed"] floatValue];
            if (sp > 0) playSpeed = sp;
        }
    }

    return playScriptWithSettings(path, repeatTime, playSpeed, sleepBetweenRun, error);
}

int playScriptWithSettings(UInt8* path, int repeatTime, float playSpeed, float sleepBetweenRun, NSError **error)
{
    if (!scriptPlayer)
    {
        NSLog(@"com.zjx.springboard: Unable to run the script. Internal error. scriptPlayer is null.");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Internal error. scriptPlayer is null.\r\n"}];
        return -1;
    }
    if (playSpeed <= 0) playSpeed = 1.0f;
    currentRunSpeed = playSpeed;

    [scriptPlayer setPath:[NSString stringWithFormat:@"%s", path]];
    [scriptPlayer setRepeatTime:repeatTime];
    [scriptPlayer setSpeed:playSpeed];
    [scriptPlayer setInterval:sleepBetweenRun];
    [scriptPlayer setSwitchApp:switchAppBeforeRunScript];

    [scriptPlayer play:error];

    return 0;
}

// In-place play: same as above but never switches apps first. The script runs
// immediately on whatever screen is currently displayed (floating panel and
// dashboard entry points). The global switch_app_before_run_script setting is
// intentionally ignored here.
int playScriptWithSettingsInPlace(UInt8* path, int repeatTime, float playSpeed, float sleepBetweenRun, NSError **error)
{
    if (!scriptPlayer)
    {
        NSLog(@"com.zjx.springboard: Unable to run the script. Internal error. scriptPlayer is null.");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Internal error. scriptPlayer is null.\r\n"}];
        return -1;
    }
    if (playSpeed <= 0) playSpeed = 1.0f;
    currentRunSpeed = playSpeed;

    [scriptPlayer setPath:[NSString stringWithFormat:@"%s", path]];
    [scriptPlayer setRepeatTime:repeatTime];
    [scriptPlayer setSpeed:playSpeed];
    [scriptPlayer setInterval:sleepBetweenRun];
    [scriptPlayer setSwitchApp:NO];

    [scriptPlayer play:error];

    return 0;
}

int playScriptInPlace(UInt8* path, NSError **error)
{
    if (!scriptPlayer)
    {
        NSLog(@"com.zjx.springboard: Unable to run the script. Internal error. scriptPlayer is null.");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Internal error. scriptPlayer is null.\r\n"}];
        return -1;
    }
    // read config file to get repeat time etc (same as playScript)
    int repeatTime = 0;
    float sleepBetweenRun = 0;
    float playSpeed = 1.0f;

    NSLog(@"com.zjx.springboard: path (in place): %s", path);
    NSDictionary *config = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:SCRIPT_PLAY_CONFIG_PATH])
        config = [[NSDictionary alloc] initWithContentsOfFile:SCRIPT_PLAY_CONFIG_PATH];

    if (config)
    {
        // App-launched scripts only use per-script settings written by the app.
        // Floating panel settings are handled separately so they do not leak.
        NSDictionary *individualConfigs = config[@"individual_configs"];
        NSDictionary *scriptInfo = [individualConfigs valueForKey:[NSString stringWithFormat:@"%s", path]];

        if (scriptInfo)
        {
            repeatTime = [scriptInfo[@"repeat_times"] intValue];
            sleepBetweenRun = [scriptInfo[@"interval"] floatValue];
            float sp = [scriptInfo[@"speed"] floatValue];
            if (sp > 0) playSpeed = sp;
        }
    }

    return playScriptWithSettingsInPlace(path, repeatTime, playSpeed, sleepBetweenRun, error);
}


void stopScriptPlaying(NSError **error)
{
    if (scriptPlayer) [scriptPlayer forceStop:error];
    notifyScriptState(@"stopped");
}

void pauseScriptPlaying(void)
{
    if (!scriptPlayer || ![scriptPlayer isPlaying]) return;
    [scriptPlayer pause];
    notifyScriptState(@"paused");
}

void resumeScriptPlaying(void)
{
    if (!scriptPlayer) return;
    [scriptPlayer resume];
    notifyScriptState(@"resumed");
}

BOOL isScriptPaused(void)
{
    return scriptPlayer && [scriptPlayer isPaused];
}

BOOL isScriptPlaying()
{
    return scriptPlayer && [scriptPlayer isPlaying];
}

void playHasStoppedCallBack()
{
    notifyScriptState(@"finished");
    // "Script Finished" popup is OFF by default (it interrupts automation).
    // Users can turn it back on in the app's settings
    // (Script -> Script Finished Popup).
    NSDictionary *tweakCfg = [[NSDictionary alloc] initWithContentsOfFile:@"/var/mobile/Library/ZXTouch/config/tweak/config.plist"];
    id showFinishedPopup = tweakCfg[@"show_script_finished_popup"];
    if (![showFinishedPopup boolValue]) {
        return;
    }

    if (CFAbsoluteTimeGetCurrent() - lastAlertBoxRequestTime() < 4.0) {
        NSLog(@"com.zjx.springboard: skipping Script Finished popup because script recently showed an alert.");
        return;
    }

    NSString *bundlePath = [scriptPlayer getCurrentBundlePath];
    NSString *scriptName = (bundlePath.length > 0) ? [[bundlePath lastPathComponent] stringByDeletingPathExtension] : @"Unknown";
    int completedRuns = [scriptPlayer getCompletedRuns];

    NSString *msg = [NSString stringWithFormat:@"Script: %@\nSpeed: %.1f×\nPlayed: %d time(s)",
                     scriptName, currentRunSpeed, completedRuns];
    showAlertBox(@"Script Finished", msg, 0);
}
