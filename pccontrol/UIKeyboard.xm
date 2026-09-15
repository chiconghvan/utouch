#include "UIKeyboard.h"
#import <UIKit/UIKit.h>
#import <Foundation/NSDistributedNotificationCenter.h>

#define TASK_GET_TEXT_FROM_CLIPBOARD 6
#define TASK_SAVE_TEXT_TO_CLIPBOARD 7
#define TASK_QUERY_KEYBOARD_VISIBLE 8
#define TASK_VIRTUAL_KEYBOARD 2

static NSString *const ZXKeyboardQueryNotification = @"com.zjx.zxtouch.keyboard.query";
static NSString *const ZXKeyboardResponseNotification = @"com.zjx.zxtouch.keyboard.response";
static NSString *const ZXKeyboardControlNotification = @"com.zjx.zxtouch.keyboardcontrol";
static NSString *const ZXKeyboardControlResponseNotification = @"com.zjx.zxtouch.keyboardcontrol.response";

static NSString* keyboardVisibilityControlFromRawData(NSArray *data, NSError **error)
{
    if ([data count] < 2)
    {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                                  userInfo:@{NSLocalizedDescriptionKey:
                                      @"-1;;Keyboard visibility task requires a status.\r\n"}];
        return nil;
    }

    int status = [data[1] intValue];
    if (status != 1 && status != 2)
    {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                                  userInfo:@{NSLocalizedDescriptionKey:
                                      @"-1;;Unknown keyboard visibility status.\r\n"}];
        return nil;
    }

    NSString *requestID = [NSString stringWithFormat:@"%.6f-%u",
                           NSDate.timeIntervalSinceReferenceDate, arc4random()];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL success = NO;
    __block BOOL visible = NO;
    __block BOOL received = NO;
    __block NSString *responseError = nil;

    id observer = [[NSDistributedNotificationCenter defaultCenter]
        addObserverForName:ZXKeyboardControlResponseNotification object:nil
                     queue:nil
                usingBlock:^(NSNotification *notification) {
        if (![notification.userInfo[@"request_id"] isEqualToString:requestID]) return;
        success = [notification.userInfo[@"success"] boolValue];
        visible = [notification.userInfo[@"visible"] boolValue];
        responseError = notification.userInfo[@"error"];
        received = YES;
        dispatch_semaphore_signal(semaphore);
    }];

    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:ZXKeyboardControlNotification
                      object:nil
                    userInfo:@{
                        @"task_id": data[0],
                        @"task_content": data[1],
                        @"request_id": requestID
                    }
           deliverImmediately:NO];

    long waitResult = dispatch_semaphore_wait(
        semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)));
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:observer];

    if (waitResult != 0 || !received)
    {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:998
                                  userInfo:@{NSLocalizedDescriptionKey:
                                      @"-1;;Keyboard visibility transition acknowledgement timed out.\r\n"}];
        return nil;
    }
    if (!success)
    {
        NSString *message = responseError ?: @"Keyboard visibility transition failed.";
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                                  userInfo:@{NSLocalizedDescriptionKey:
                                      [NSString stringWithFormat:@"-1;;%@\r\n", message]}];
        return nil;
    }

    return visible ? @"true" : @"false";
}

NSString* keyboardVisibleFromRawData(NSError **error)
{
    NSString *requestID = [NSString stringWithFormat:@"%.6f-%u",
                           NSDate.timeIntervalSinceReferenceDate, arc4random()];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSString *visible = nil;

    id observer = [[NSDistributedNotificationCenter defaultCenter]
        addObserverForName:ZXKeyboardResponseNotification object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *notification) {
        if (![notification.userInfo[@"request_id"] isEqualToString:requestID]) return;
        visible = [notification.userInfo[@"visible"] boolValue] ? @"true" : @"false";
        dispatch_semaphore_signal(semaphore);
    }];

    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:ZXKeyboardQueryNotification object:nil
                      userInfo:@{ @"request_id": requestID }
             deliverImmediately:NO];

    long waitResult = dispatch_semaphore_wait(
        semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)));
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:observer];
    if (waitResult != 0 || visible == nil)
    {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:998
                                  userInfo:@{NSLocalizedDescriptionKey:
                                      @"-1;;Keyboard visibility query timed out.\r\n"}];
        return nil;
    }
    return visible;
}

NSString* inputTextFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray *data = [[NSString stringWithUTF8String:(char*)eventData] componentsSeparatedByString:@";;"];

    if ([data count] < 1)
    {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Keyboard related event length error. You have to specify the task id.\r\n"}];
        return nil;
    }

    int taskType = [data[0] intValue];

    if (taskType == TASK_VIRTUAL_KEYBOARD)
    {
        return keyboardVisibilityControlFromRawData(data, error);
    }
    else if (taskType == TASK_GET_TEXT_FROM_CLIPBOARD)
    {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        return pasteboard.string ?: @"";
    }
    else if (taskType == TASK_SAVE_TEXT_TO_CLIPBOARD)
    {
        if ([data count] < 2)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Keyboard related event error. You have to specify the content you want to paste to clipboard.\r\n"}];
            return nil;
        }
        [UIPasteboard generalPasteboard].string = data[1];
        return @"";
    }
    else if (taskType == TASK_QUERY_KEYBOARD_VISIBLE)
    {
        return keyboardVisibleFromRawData(error);
    }

    // Forward to appdelegate tweak injected in the frontmost app.
    // deliverImmediately:NO (async) — avoids the SpringBoard crash from synchronous delivery.
    NSString *taskContent = ([data count] >= 2) ? data[1] : @"";
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:ZXKeyboardControlNotification
        object:nil
        userInfo:@{@"task_id": data[0], @"task_content": taskContent}
        deliverImmediately:NO];

    return @"";
}
