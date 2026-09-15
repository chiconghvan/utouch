#import "FloatingControl.h"
#import "Popup.h"
#import "Play.h"
#import "Toast.h"
#import "Common.h"
#include <roothide.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <math.h>

static CGFloat const ZXFloatingIconSize = 40.0f;
static CGFloat const ZXFloatingIconMargin = 8.0f;
static NSString * const ZXFloatingSideKey = @"floating_icon_side";
static NSString * const ZXFloatingYKey = @"floating_icon_y";

@interface ZXFloatingControl : NSObject
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UIButton *button;
@property(nonatomic, strong) UIWindow *alertWindow;
@property(nonatomic, assign) CGRect dragStartFrame;
@property(nonatomic, assign) CGPoint dragTouchOffset;
@property(nonatomic, assign) BOOL didDrag;
@property(nonatomic, assign) BOOL promptVisible;
- (void)show;
- (void)layoutForCurrentScreen;
- (void)handleTap:(UITapGestureRecognizer *)gesture;
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
- (void)showStopPrompt;
- (void)finishStopPromptWithStop:(BOOL)stop;
@end

static ZXFloatingControl *floatingControl = nil;

static UIWindowScene *ZXActiveWindowScene(void)
{
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
    }
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)scene;
    }
    return nil;
}

static NSDictionary *ZXFloatingConfig(void)
{
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:getCommonConfigFilePath()];
    return [config isKindOfClass:[NSDictionary class]] ? config : @{};
}

static void ZXSaveFloatingPosition(NSString *side, CGFloat normalizedY)
{
    NSMutableDictionary *config = [NSMutableDictionary dictionaryWithDictionary:ZXFloatingConfig()];
    config[ZXFloatingSideKey] = side ?: @"right";
    config[ZXFloatingYKey] = @(MAX(0.0f, MIN(1.0f, normalizedY)));
    [[NSFileManager defaultManager] createDirectoryAtPath:[getCommonConfigFilePath() stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    [config writeToFile:getCommonConfigFilePath() atomically:YES];
}

static NSString *ZXFloatingIconPath(void)
{
    NSArray *candidates = @[
        jbroot(@"/Library/Application Support/zxtouch/zxtouch-floating-icon.png"),
        @"/var/jb/Library/Application Support/zxtouch/zxtouch-floating-icon.png",
        @"/Library/Application Support/zxtouch/zxtouch-floating-icon.png"
    ];
    for (NSString *path in candidates) {
        if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    }
    return nil;
}

static UIImage *ZXFallbackFloatingIcon(void)
{
    CGSize size = CGSizeMake(120.0f, 120.0f);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return nil;

    CGRect circle = CGRectMake(4.0f, 4.0f, 112.0f, 112.0f);
    [[UIColor colorWithRed:1.0f green:0.69f blue:0.16f alpha:1.0f] setFill];
    CGContextFillEllipseInRect(context, circle);

    [[UIColor whiteColor] setFill];
    UIBezierPath *head = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(29, 35, 62, 48) cornerRadius:15];
    [head fill];
    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(35, 78, 50, 32) cornerRadius:14];
    [body fill];

    [[UIColor colorWithRed:0.22f green:0.23f blue:0.34f alpha:1.0f] setFill];
    UIBezierPath *face = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(38, 47, 44, 25) cornerRadius:7];
    [face fill];

    [[UIColor colorWithRed:1.0f green:0.69f blue:0.16f alpha:1.0f] setFill];
    CGContextFillEllipseInRect(context, CGRectMake(46, 55, 8, 8));
    CGContextFillEllipseInRect(context, CGRectMake(66, 55, 8, 8));

    [[UIColor whiteColor] setStroke];
    CGContextSetLineWidth(context, 4.0f);
    CGContextMoveToPoint(context, 60, 35);
    CGContextAddLineToPoint(context, 60, 24);
    CGContextStrokePath(context);
    CGContextFillEllipseInRect(context, CGRectMake(55, 16, 10, 10));

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static UIImage *ZXFloatingIconImage(void)
{
    NSString *path = ZXFloatingIconPath();
    UIImage *image = path ? [UIImage imageWithContentsOfFile:path] : nil;
    return image ?: ZXFallbackFloatingIcon();
}

@implementation ZXFloatingControl

- (instancetype)init
{
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(scriptStateChanged:)
                                                     name:ZXScriptStateDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(orientationChanged:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self buildWindow];
        });
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildWindow
{
    if (self.window) return;

    UIWindowScene *scene = ZXActiveWindowScene();
    self.window = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                        : [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, ZXFloatingIconSize, ZXFloatingIconSize)];
    self.window.windowLevel = UIWindowLevelAlert + 2;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.rootViewController = [[UIViewController alloc] init];
    self.window.rootViewController.view.backgroundColor = [UIColor clearColor];
    self.window.userInteractionEnabled = YES;

    UIView *rootView = self.window.rootViewController.view;
    rootView.userInteractionEnabled = YES;

    self.button = [UIButton buttonWithType:UIButtonTypeCustom];
    self.button.frame = CGRectMake(0, 0, ZXFloatingIconSize, ZXFloatingIconSize);
    self.button.userInteractionEnabled = YES;
    self.button.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.button.layer.cornerRadius = ZXFloatingIconSize / 2.0f;
    self.button.layer.borderColor = [UIColor blackColor].CGColor;
    self.button.layer.borderWidth = 1.5f;
    self.button.clipsToBounds = YES;
    self.button.accessibilityLabel = @"Open ZXTouch Panel";
    [self.button setImage:ZXFloatingIconImage() forState:UIControlStateNormal];
    // Use an explicit tap recognizer instead of relying only on UIButton's
    // control-event delivery. This remains reliable in SpringBoard's extra
    // UIWindow hierarchy while the drag recognizer is attached to the same view.
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    tap.cancelsTouchesInView = NO;
    [self.button addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.cancelsTouchesInView = NO;
    [self.button addGestureRecognizer:pan];
    [rootView addSubview:self.button];

    [self layoutForCurrentScreen];
    rootView.frame = self.window.bounds;
    rootView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.window.hidden = NO;
}

- (void)handleTap:(UITapGestureRecognizer *)gesture
{
    if (self.didDrag) {
        self.didDrag = NO;
        return;
    }

    if (isScriptPlaying()) {
        if (!self.promptVisible) {
            pauseScriptPlaying();
            [Toast showPersistentToastWithContent:@"Script: Pause" type:2 position:0 fontSize:15];
            [self showStopPrompt];
        }
        return;
    }

    extern PopupWindow *popupWindow;
    if (!popupWindow) {
        popupWindow = [[PopupWindow alloc] init];
    }
    [popupWindow show];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture
{
    if (!self.window) return;
    CGPoint location = [gesture locationInView:nil];
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            self.dragStartFrame = self.window.frame;
            self.dragTouchOffset = CGPointMake(location.x - self.window.frame.origin.x,
                                               location.y - self.window.frame.origin.y);
            self.didDrag = NO;
            break;
        case UIGestureRecognizerStateChanged: {
            if (fabs(location.x - (self.dragStartFrame.origin.x + self.dragTouchOffset.x)) > 3.0f ||
                fabs(location.y - (self.dragStartFrame.origin.y + self.dragTouchOffset.y)) > 3.0f) {
                self.didDrag = YES;
            }
            CGRect frame = self.dragStartFrame;
            frame.origin.x = location.x - self.dragTouchOffset.x;
            frame.origin.y = location.y - self.dragTouchOffset.y;
            self.window.frame = [self clampedFrame:frame];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            [self snapToEdgeAndSave];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ self.didDrag = NO; });
            break;
        }
        default:
            break;
    }
}

- (CGRect)clampedFrame:(CGRect)frame
{
    CGRect bounds = [UIScreen mainScreen].bounds;
    CGFloat minX = CGRectGetMinX(bounds) + ZXFloatingIconMargin;
    CGFloat maxX = CGRectGetMaxX(bounds) - ZXFloatingIconMargin - ZXFloatingIconSize;
    CGFloat minY = CGRectGetMinY(bounds) + ZXFloatingIconMargin;
    CGFloat maxY = CGRectGetMaxY(bounds) - ZXFloatingIconMargin - ZXFloatingIconSize;
    frame.origin.x = MAX(minX, MIN(maxX, frame.origin.x));
    frame.origin.y = MAX(minY, MIN(maxY, frame.origin.y));
    frame.size = CGSizeMake(ZXFloatingIconSize, ZXFloatingIconSize);
    return frame;
}

- (void)snapToEdgeAndSave
{
    CGRect bounds = [UIScreen mainScreen].bounds;
    CGFloat centerX = CGRectGetMidX(self.window.frame);
    BOOL left = centerX <= CGRectGetMidX(bounds);
    CGRect frame = self.window.frame;
    frame.origin.x = left ? CGRectGetMinX(bounds) + ZXFloatingIconMargin
                           : CGRectGetMaxX(bounds) - ZXFloatingIconMargin - ZXFloatingIconSize;
    frame = [self clampedFrame:frame];
    [UIView animateWithDuration:0.2 animations:^{ self.window.frame = frame; }];

    CGFloat available = MAX(1.0f, CGRectGetHeight(bounds) - ZXFloatingIconSize - 2.0f * ZXFloatingIconMargin);
    CGFloat normalizedY = (frame.origin.y - CGRectGetMinY(bounds) - ZXFloatingIconMargin) / available;
    ZXSaveFloatingPosition(left ? @"left" : @"right", normalizedY);
}

- (void)layoutForCurrentScreen
{
    if (!self.window) return;
    CGRect bounds = [UIScreen mainScreen].bounds;
    NSDictionary *config = ZXFloatingConfig();
    NSString *side = [config[ZXFloatingSideKey] isEqualToString:@"left"] ? @"left" : @"right";
    CGFloat normalizedY = config[ZXFloatingYKey] ? [config[ZXFloatingYKey] doubleValue] : 0.5f;
    normalizedY = MAX(0.0f, MIN(1.0f, normalizedY));

    CGFloat available = MAX(1.0f, CGRectGetHeight(bounds) - ZXFloatingIconSize - 2.0f * ZXFloatingIconMargin);
    CGFloat x = [side isEqualToString:@"left"]
        ? CGRectGetMinX(bounds) + ZXFloatingIconMargin
        : CGRectGetMaxX(bounds) - ZXFloatingIconMargin - ZXFloatingIconSize;
    CGFloat y = CGRectGetMinY(bounds) + ZXFloatingIconMargin + available * normalizedY;
    self.window.frame = [self clampedFrame:CGRectMake(x, y, ZXFloatingIconSize, ZXFloatingIconSize)];
}

- (void)orientationChanged:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self layoutForCurrentScreen];
    });
}

- (void)showStopPrompt
{
    self.promptVisible = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene = ZXActiveWindowScene();
        self.alertWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                                 : [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        self.alertWindow.frame = [UIScreen mainScreen].bounds;
        self.alertWindow.windowLevel = UIWindowLevelAlert + 4;
        UIViewController *root = [[UIViewController alloc] init];
        root.view.backgroundColor = [UIColor clearColor];
        self.alertWindow.rootViewController = root;
        [self.alertWindow makeKeyAndVisible];

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Stop Script?"
                                                                         message:@"The script is paused. Stop it now?"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:@"No"
                                                   style:UIAlertActionStyleCancel
                                                 handler:^(UIAlertAction *action) {
            [weakSelf finishStopPromptWithStop:NO];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Yes"
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *action) {
            [weakSelf finishStopPromptWithStop:YES];
        }]];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.promptVisible) [root presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)finishStopPromptWithStop:(BOOL)stop
{
    if (!self.promptVisible) return;
    self.promptVisible = NO;
    if (stop) {
        NSError *error = nil;
        stopScriptPlaying(&error);
    } else {
        resumeScriptPlaying();
    }
    [Toast hideToast];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.alertWindow.hidden = YES;
        self.alertWindow = nil;
    });
}

- (void)scriptStateChanged:(NSNotification *)notification
{
    NSString *state = notification.userInfo[@"state"];
    if ([state isEqualToString:@"stopped"] || [state isEqualToString:@"finished"] ||
        [state isEqualToString:@"error"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.promptVisible) {
                self.promptVisible = NO;
                self.alertWindow.hidden = YES;
                self.alertWindow = nil;
                [Toast hideToast];
            }
        });
    }
}

@end

void initFloatingControl(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!floatingControl) floatingControl = [[ZXFloatingControl alloc] init];
    });
}

void dismissFloatingScriptPrompt(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (floatingControl && floatingControl.promptVisible) {
            floatingControl.promptVisible = NO;
            floatingControl.alertWindow.hidden = YES;
            floatingControl.alertWindow = nil;
            [Toast hideToast];
        }
    });
}
