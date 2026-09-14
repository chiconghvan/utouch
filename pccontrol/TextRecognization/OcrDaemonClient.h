#ifndef ZX_OCR_DAEMON_CLIENT_H
#define ZX_OCR_DAEMON_CLIENT_H

#import <Foundation/Foundation.h>

// 1 = daemon returned a response, 0 = daemon unavailable, -1 = daemon error.
int ZXPerformOcrThroughDaemon(UInt8 *eventData, NSString **result, NSError **error);

#endif
