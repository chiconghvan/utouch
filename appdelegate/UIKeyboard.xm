#include "UIKeyboard.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CFMessagePort.h>
#import <Foundation/NSDistributedNotificationCenter.h>
#import <execinfo.h>
#import <mach-o/dyld.h>
#include <substrate.h>

#define INSERT_TEXT 1
#define VIRTUAL_KEYBOARD 2
#define MOVE_CURSOR 3
#define DELETE_CHARACTER 4
#define PASTE_FROM_CLIPBOARD 5

#define TEST 99

#define VIRTUAL_KEYBOARD_HIDE 1
#define VIRTUAL_KEYBOARD_SHOW 2

static volatile BOOL zxKeyboardVisible = NO;
static NSString *const ZXKeyboardQueryNotification = @"com.zjx.zxtouch.keyboard.query";
static NSString *const ZXKeyboardResponseNotification = @"com.zjx.zxtouch.keyboard.response";
static NSString *const ZXKeyboardControlResponseNotification = @"com.zjx.zxtouch.keyboardcontrol.response";
static __weak UIResponder *zxLastInputResponder = nil;


@interface UIKeyboardImpl : UIView
	+ (id)sharedInstance;
	+ (id)activeInstance;
	- (void)zx_registerKeyboardStateObservers;
	- (void)insertText:(id)arg1;
	- (void)hideKeyboard;
    - (void)showKeyboard;
	- (void)zx_handleKeyboardVisibilityRequest:(NSString *)requestID visible:(BOOL)visible;
	- (void)clearDelegate;
	- (void)clearInput;
	- (void)moveSelectionToEndOfWord;
	- (void)moveCursorByAmount:(long long)arg1;
	- (void)deleteFromInput;
	- (void)clearSelection;
    - (void)deleteBackward;
 	- (void)setSelectionWithPoint:(struct CGPoint)arg1;
    - (id)markedText;
    - (void)unmarkText;
    - (void)clearSelection;
    - (void)setInputPoint:(struct CGPoint)arg1;
    - (_Bool)hasMarkedText;

 	@property (readonly, assign, nonatomic) UIResponder <UITextInput> *inputDelegate;
@end

static BOOL zxIsActiveApplication(void)
{
    UIApplication *application = [UIApplication sharedApplication];
    return application && application.applicationState == UIApplicationStateActive;
}

static UIResponder *zxFindFirstResponder(void)
{
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIResponder *responder = [window performSelector:@selector(firstResponder)];
            if (responder) return responder;
        }
    }
    return nil;
}

static void zxPostKeyboardControlResponse(NSString *requestID, BOOL success, BOOL visible, NSString *error)
{
    if (!requestID) return;

    NSMutableDictionary *userInfo = [@{
        @"request_id": requestID,
        @"success": @(success),
        @"visible": @(visible)
    } mutableCopy];
    if (error) userInfo[@"error"] = error;

    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:ZXKeyboardControlResponseNotification
                      object:nil
                    userInfo:userInfo
           deliverImmediately:NO];
}


%hook UIKeyboardImpl

    %new
    - (void)zx_registerKeyboardStateObservers {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            [center addObserverForName:UIKeyboardDidShowNotification object:nil
                                 queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification *notification) {
                zxKeyboardVisible = YES;
            }];
            [center addObserverForName:UIKeyboardDidHideNotification object:nil
                                 queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification *notification) {
                zxKeyboardVisible = NO;
            }];
            [[NSDistributedNotificationCenter defaultCenter]
                addObserverForName:ZXKeyboardQueryNotification object:nil
                             queue:nil
                         usingBlock:^(NSNotification *notification) {
                if (!zxIsActiveApplication()) return;
                NSString *requestID = notification.userInfo[@"request_id"];
                if (!requestID) return;
                [[NSDistributedNotificationCenter defaultCenter]
                    postNotificationName:ZXKeyboardResponseNotification object:nil
                                  userInfo:@{
                                      @"request_id": requestID,
                                      @"visible": @(zxKeyboardVisible)
                                  }
                         deliverImmediately:NO];
            }];
        });
    }

    - (id)initWithFrame:(CGRect)arg1 forCustomInputView:(UIView*)view
    {
        // Don't register in SpringBoard — keyboard commands are sent FROM SpringBoard, not received
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            [[NSDistributedNotificationCenter defaultCenter]
                addObserver:self selector:@selector(handleKeyboardNotification:)
                name:@"com.zjx.zxtouch.keyboardcontrol" object:nil];
        }
        id result = %orig;
        [self zx_registerKeyboardStateObservers];
        return result;
    }

	- (id)initWithFrame:(CGRect)arg1 {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            [[NSDistributedNotificationCenter defaultCenter]
                addObserver:self selector:@selector(handleKeyboardNotification:)
                name:@"com.zjx.zxtouch.keyboardcontrol" object:nil];
        }
        id result = %orig;
        [self zx_registerKeyboardStateObservers];
        return result;
	}

    - (void)dealloc {

        [[NSDistributedNotificationCenter defaultCenter] removeObserver:self name:@"com.zjx.zxtouch.keyboardcontrol" object:nil];
		//NSLog(@"com.zjx.appdelegate: UIKeyboardImpl instance deallocated");
		return %orig;
    }

    %new
    - (void)zx_handleKeyboardVisibilityRequest:(NSString *)requestID visible:(BOOL)visible
    {
        UIKeyboardImpl *keyboard = self;
        if ([UIKeyboardImpl respondsToSelector:@selector(activeInstance)]) {
            UIKeyboardImpl *active = [UIKeyboardImpl activeInstance];
            if (active) keyboard = active;
        }

        NSString *transitionNotification = visible
            ? UIKeyboardDidShowNotification
            : UIKeyboardDidHideNotification;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        __block BOOL completed = NO;
        __block id observer = nil;

        void (^complete)(BOOL, BOOL, NSString *) = ^(BOOL success, BOOL currentVisible, NSString *error) {
            if (completed) return;
            completed = YES;
            if (observer) {
                [center removeObserver:observer];
                observer = nil;
            }
            zxKeyboardVisible = currentVisible;
            zxPostKeyboardControlResponse(requestID, success, currentVisible, error);
        };

        observer = [center addObserverForName:transitionNotification object:nil
                                        queue:[NSOperationQueue mainQueue]
                                   usingBlock:^(__unused NSNotification *notification) {
            complete(YES, visible, nil);
        }];

        if (visible && zxKeyboardVisible) {
            complete(YES, YES, nil);
            return;
        }

        if (!visible && !zxKeyboardVisible) {
            UIResponder *current = [keyboard inputDelegate];
            if (!current) current = zxFindFirstResponder();
            if (!current || ![current isFirstResponder]) {
                complete(YES, NO, nil);
                return;
            }
        }

        if (visible) {
            UIResponder *input = [keyboard inputDelegate];
            if (!input) input = zxFindFirstResponder();
            if (!input) input = zxLastInputResponder;

            BOOL becameFirstResponder = NO;
            if (input && [input respondsToSelector:@selector(becomeFirstResponder)]) {
                becameFirstResponder = [input becomeFirstResponder];
            }
            if (!becameFirstResponder && [keyboard respondsToSelector:@selector(showKeyboard)]) {
                [keyboard showKeyboard];
            }
        }
        else {
            UIResponder *input = [keyboard inputDelegate];
            if (!input) input = zxFindFirstResponder();
            if (input && [input isFirstResponder]) {
                zxLastInputResponder = input;
                if (![input resignFirstResponder] && [keyboard respondsToSelector:@selector(hideKeyboard)]) {
                    [keyboard hideKeyboard];
                }
            }
            else if ([keyboard respondsToSelector:@selector(hideKeyboard)]) {
                [keyboard hideKeyboard];
            }
        }

        // A keyboard transition is asynchronous. Do not leave the socket caller blocked forever
        // if the target app rejects the responder change or does not emit UIKit's notification.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!completed) {
                complete(NO, visible ? zxKeyboardVisible : NO,
                         @"Keyboard visibility transition timed out.");
            }
        });
    }

    %new
	- (void)handleKeyboardNotification:(NSNotification *)notification {
		//NSLog(@"com.zjx.appdelegate: keyboard related notification received. %@", notification);
		if (!zxIsActiveApplication()) return;
		NSDictionary *data = (NSDictionary*)notification.userInfo;

        int taskId = [data[@"task_id"] intValue];
		if (taskId == INSERT_TEXT)
		{
            NSString *content = data[@"task_content"] ?: @"";
            dispatch_async(dispatch_get_main_queue(), ^{
                // Try first responder directly (more reliable on iOS 16)
                BOOL inserted = NO;
                for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                    if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                    for (UIWindow *win in ((UIWindowScene *)scene).windows) {
                        UIResponder *r = [win performSelector:@selector(firstResponder)];
                        if (r && [r respondsToSelector:@selector(insertText:)]) {
                            [(id)r insertText:content];
                            inserted = YES;
                            break;
                        }
                    }
                    if (inserted) break;
                }
                // Fallback to UIKeyboardImpl
                if (!inserted && [self respondsToSelector:@selector(insertText:)])
                    [self insertText:content];
            });
		}
        else if (taskId == VIRTUAL_KEYBOARD)
        {
            UIKeyboardImpl *active = nil;
            if ([UIKeyboardImpl respondsToSelector:@selector(activeInstance)])
                active = [UIKeyboardImpl activeInstance];
            if (active && active != self) return;

            int status = [data[@"task_content"] intValue];
            NSString *requestID = data[@"request_id"];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (status == VIRTUAL_KEYBOARD_HIDE)
                    [self zx_handleKeyboardVisibilityRequest:requestID visible:NO];
                else if (status == VIRTUAL_KEYBOARD_SHOW)
                    [self zx_handleKeyboardVisibilityRequest:requestID visible:YES];
            });
        }
        else if (taskId == MOVE_CURSOR)
        {
            long long moveAmount = [data[@"task_content"] longLongValue];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self respondsToSelector:@selector(moveCursorByAmount:)])
                    [self moveCursorByAmount:moveAmount];
            });
        }
        else if (taskId == DELETE_CHARACTER)
        {
            int n = [data[@"task_content"] intValue];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self respondsToSelector:@selector(deleteBackward)]) {
                    for (int i = 0; i < n; i++) [self deleteBackward];
                }
            });
        }
        else if (taskId == PASTE_FROM_CLIPBOARD)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self respondsToSelector:@selector(insertText:)])
                    [self insertText:[UIPasteboard generalPasteboard].string ?: @""];
            });
        }
	}

%end
