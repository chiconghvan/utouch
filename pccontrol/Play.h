#ifndef PLAY_H
#define PLAY_H

#import <Foundation/Foundation.h>

extern NSString * const ZXScriptStateDidChangeNotification;
void notifyScriptState(NSString *state);

int playScript(UInt8* path, NSError** error);
int playScriptWithSettings(UInt8* path, int repeatTime, float playSpeed, float interval, NSError** error);
void playFromRawFile(NSString* filePath, NSString* foregroundApp, NSError **err);
void playFromPythonFile(NSString* filePath, NSString* foregroundApp, NSError **err);
void stopScriptPlaying(NSError **error);
void pauseScriptPlaying(void);
void resumeScriptPlaying(void);
BOOL isScriptPaused(void);
BOOL isScriptPlaying();
void playHasStoppedCallBack();
void initScriptPlayer();

#endif
