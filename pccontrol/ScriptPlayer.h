#ifndef SCRIPT_PLAYER_H
#define SCRIPT_PLAYER_H

#import <Foundation/Foundation.h>

@interface ScriptPlayer : NSObject

- (void)setRepeatTime:(int)rt;
- (void)setInterval:(float)intv;
- (void)setSpeed:(float)sp;
- (void)setPath:(NSString*)path;
- (void)forceStop:(NSError**)error;
- (void)pause;
- (void)resume;
- (BOOL)isPaused;
- (void)setSwitchApp:(BOOL)value;

- (id)initWithPath:(NSString*)path;

// Runs `python3 -m zxtouch.checker <path>` synchronously and leaves the report
// at `<path>.diag.json`. Returns nil on success, or a short error string.
+ (NSString *)validateScriptAtPath:(NSString *)path;

- (int)play:(NSError**)error;
- (BOOL)isPlaying;
- (NSString*)getCurrentBundlePath;
- (int)getCompletedRuns;

@end

#endif
