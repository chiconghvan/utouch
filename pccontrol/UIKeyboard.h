#ifndef UIKeyboard_H
#define UIKeyboard_H

#import <Foundation/Foundation.h>

NSString* inputTextFromRawData(UInt8 *eventData, NSError **error);
NSString* keyboardVisibleFromRawData(NSError **error);

#endif
