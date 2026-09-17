#ifndef SCREEN_MATCH_H
#define SCREEN_MATCH_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

CGRect screenMatchFromRawData(UInt8 *eventData, NSError **error);
// Same as above, but also reports the NCC confidence of the hit (NULL to ignore).
CGRect screenMatchFromRawDataWithScore(UInt8 *eventData, float *outScore, NSError **error);

@interface ScreenMatch : NSObject
+ (CGRect)matchCurrentScreenWithTemplate:(NSString*)templatePath maxTryTimes:(int)mtt acceptableValue:(float)av scaleRation:(float)sr error:(NSError**)err;
+ (CGRect)matchCurrentScreenWithTemplate:(NSString*)templatePath maxTryTimes:(int)mtt acceptableValue:(float)av scaleRation:(float)sr score:(float*)outScore error:(NSError**)err;
@end

#endif
