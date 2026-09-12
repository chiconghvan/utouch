#include "DebugOverlay.h"
#include "Screen.h"
#include "Common.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// ---------------------------------------------------------------------------
// ZXDebugOverlay — module vẽ debug riêng, giống module Toast (Toast.xm).
//
//  * 1 UIWindow trong suốt, fullscreen, không chặn touch.
//  * Mỗi shape là 1 CAShapeLayer màu đỏ, tự mờ dần rồi remove sau `duration`.
//  * Tọa độ vào là DEVICE PIXELS (cùng hệ với tap/OCR/image), convert sang
//    points bằng scale để vẽ đúng trên mọi máy @2x/@3x.
//  * Kích thước tối thiểu ép ở native để luôn đủ nhìn:
//      rect: viền >= 3pt + fill đỏ mờ
//      circle (tap): r >= 20pt, viền 3pt + fill mờ + chấm tâm
//      line (swipe): dày >= 4pt + 2 vòng tròn ở 2 đầu
// ---------------------------------------------------------------------------

static UIWindow *_dbgWindow = nil;
static UIView *_dbgCanvas = nil;

static UIColor *ZXDbgRed(void) {
    return [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0];
}

static UIColor *ZXDbgFill(void) {
    return [[UIColor redColor] colorWithAlphaComponent:0.15];
}

static void ZXDbgEnsureWindow(void) {
    if (_dbgWindow && _dbgCanvas) {
        _dbgWindow.hidden = NO;
        return;
    }
    CGRect bounds = [UIScreen mainScreen].bounds;
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
    if (scene) {
        _dbgWindow = [[UIWindow alloc] initWithWindowScene:scene];
        _dbgWindow.frame = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    } else {
        _dbgWindow = [[UIWindow alloc] initWithFrame:bounds];
    }
    _dbgWindow.windowLevel = UIWindowLevelAlert + 10; // trên cả toast/popup
    _dbgWindow.backgroundColor = [UIColor clearColor];
    _dbgWindow.userInteractionEnabled = NO; // tuyệt đối không chặn tap thật
    _dbgWindow.rootViewController = [[UIViewController alloc] init];
    _dbgWindow.rootViewController.view.backgroundColor = [UIColor clearColor];
    _dbgWindow.rootViewController.view.userInteractionEnabled = NO;

    _dbgCanvas = [[UIView alloc] initWithFrame:_dbgWindow.bounds];
    _dbgCanvas.backgroundColor = [UIColor clearColor];
    _dbgCanvas.userInteractionEnabled = NO;
    _dbgCanvas.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_dbgWindow.rootViewController.view addSubview:_dbgCanvas];
    _dbgWindow.hidden = NO;
}

// pixels (thiết bị) -> points (UIKit)
static CGFloat ZXDbgScale(void) {
    CGFloat s = [Screen getScale];
    return s > 0 ? s : 2.0;
}

static void ZXDbgScheduleRemove(CAShapeLayer *layer, CGFloat duration) {
    CGFloat d = duration < 0.3 ? 0.3 : (duration > 5.0 ? 5.0 : duration);
    // Fade out ở 0.25s cuối để user thấy rõ rồi mất, không để lại rác hình.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((d - 0.25) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.25];
        layer.opacity = 0.0;
        [CATransaction commit];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [layer removeFromSuperlayer];
    });
}

static void ZXDbgDrawRect(CGRect boxPx, CGFloat duration) {
    CGFloat s = ZXDbgScale();
    CGRect box = CGRectMake(boxPx.origin.x / s, boxPx.origin.y / s,
                            boxPx.size.width / s, boxPx.size.height / s);
    // Ép kích thước tối thiểu để box OCR nhỏ (vd label "OK") vẫn đủ nhìn.
    if (box.size.width < 24) {
        box.origin.x -= (24 - box.size.width) / 2.0;
        box.size.width = 24;
    }
    if (box.size.height < 24) {
        box.origin.y -= (24 - box.size.height) / 2.0;
        box.size.height = 24;
    }
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.path = [UIBezierPath bezierPathWithRect:box].CGPath;
    layer.strokeColor = ZXDbgRed().CGColor;
    layer.fillColor = ZXDbgFill().CGColor;
    layer.lineWidth = 3.0; // pt — đủ nhìn trên cả @2x/@3x
    [_dbgCanvas.layer addSublayer:layer];
    ZXDbgScheduleRemove(layer, duration);
}

static void ZXDbgDrawCircle(CGPoint cPx, CGFloat rPx, CGFloat duration) {
    CGFloat s = ZXDbgScale();
    // Ép bán kính tối thiểu 20pt (~60px @3x): đường kính 40pt ~ 14mm, đủ nhìn.
    CGFloat rPt = rPx / s;
    if (rPt < 20.0) rPt = 20.0;
    CGPoint c = CGPointMake(cPx.x / s, cPx.y / s);
    CGRect frame = CGRectMake(c.x - rPt, c.y - rPt, rPt * 2, rPt * 2);

    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.path = [UIBezierPath bezierPathWithOvalInRect:frame].CGPath;
    ring.strokeColor = ZXDbgRed().CGColor;
    ring.fillColor = ZXDbgFill().CGColor;
    ring.lineWidth = 3.0;
    [_dbgCanvas.layer addSublayer:ring];
    ZXDbgScheduleRemove(ring, duration);

    // Chấm tâm 4pt để biết chính xác điểm tap.
    CGRect dot = CGRectMake(c.x - 2, c.y - 2, 4, 4);
    CAShapeLayer *center = [CAShapeLayer layer];
    center.path = [UIBezierPath bezierPathWithOvalInRect:dot].CGPath;
    center.fillColor = ZXDbgRed().CGColor;
    center.strokeColor = nil;
    [_dbgCanvas.layer addSublayer:center];
    ZXDbgScheduleRemove(center, duration);
}

static void ZXDbgDrawLine(CGPoint aPx, CGPoint bPx, CGFloat duration) {
    CGFloat s = ZXDbgScale();
    CGPoint a = CGPointMake(aPx.x / s, aPx.y / s);
    CGPoint b = CGPointMake(bPx.x / s, bPx.y / s);

    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:a];
    [path addLineToPoint:b];
    CAShapeLayer *line = [CAShapeLayer layer];
    line.path = path.CGPath;
    line.strokeColor = ZXDbgRed().CGColor;
    line.fillColor = nil;
    line.lineWidth = 4.0; // pt — swipe thấy rõ
    line.lineCap = kCALineCapRound;
    [_dbgCanvas.layer addSublayer:line];
    ZXDbgScheduleRemove(line, duration);

    // 2 vòng tròn r=10pt ở đầu/cuối để phân biệt hướng vuốt.
    for (int i = 0; i < 2; i++) {
        CGPoint p = (i == 0) ? a : b;
        CGRect f = CGRectMake(p.x - 10, p.y - 10, 20, 20);
        CAShapeLayer *cap = [CAShapeLayer layer];
        cap.path = [UIBezierPath bezierPathWithOvalInRect:f].CGPath;
        cap.strokeColor = ZXDbgRed().CGColor;
        cap.fillColor = (i == 0) ? ZXDbgRed().CGColor : ZXDbgFill().CGColor;
        cap.lineWidth = 3.0;
        [_dbgCanvas.layer addSublayer:cap];
        ZXDbgScheduleRemove(cap, duration);
    }
}

static NSArray *ZXDbgSplit(UInt8 *eventData) {
    NSString *s = [NSString stringWithUTF8String:(char *)eventData] ?: @"";
    return [s componentsSeparatedByString:@";;"];
}

static NSString *ZXDbgError(NSString *msg) {
    return [NSString stringWithFormat:@"-1;;%@\r\n", msg];
}

NSString *debugMarkFromRawData(UInt8 *eventData, NSError **error) {
    NSArray *parts = ZXDbgSplit(eventData);
    if ([parts count] == 0) {
        if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey: ZXDbgError(@"DebugMark format: rect;;x,y,w,h | circle;;x,y,r | line;;x1,y1,x2,y2 | clear.")}];
        return nil;
    }
    NSString *op = [parts objectAtIndex:0];
    __block NSString *result = @"0\r\n";
    __block NSError *uiError = nil;

    // Vẽ UI bắt buộc trên main thread; socket thread chỉ parse số.
    dispatch_sync(dispatch_get_main_queue(), ^{
        @try {
            if ([op isEqualToString:@"clear"]) {
                _dbgWindow.hidden = YES;
                _dbgWindow = nil;
                _dbgCanvas = nil;
                return;
            }
            if ([parts count] < 2) {
                uiError = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                    userInfo:@{NSLocalizedDescriptionKey: ZXDbgError(@"DebugMark needs payload: op;;coords[;;duration].")}];
                return;
            }
            NSArray *nums = [[parts objectAtIndex:1] componentsSeparatedByString:@","];
            CGFloat duration = 1.5;
            if ([parts count] >= 3) duration = [[parts objectAtIndex:2] floatValue];
            if (!(duration > 0)) duration = 1.5;
            ZXDbgEnsureWindow();

            if ([op isEqualToString:@"rect"]) {
                if ([nums count] != 4) {
                    uiError = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                        userInfo:@{NSLocalizedDescriptionKey: ZXDbgError(@"rect format: rect;;x,y,w,h[;;duration].")}];
                    return;
                }
                CGRect box = CGRectMake([nums[0] floatValue], [nums[1] floatValue],
                                        [nums[2] floatValue], [nums[3] floatValue]);
                ZXDbgDrawRect(box, duration);
            } else if ([op isEqualToString:@"circle"]) {
                if ([nums count] != 3) {
                    uiError = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                        userInfo:@{NSLocalizedDescriptionKey: ZXDbgError(@"circle format: circle;;x,y,r[;;duration].")}];
                    return;
                }
                ZXDbgDrawCircle(CGPointMake([nums[0] floatValue], [nums[1] floatValue]),
                                [nums[2] floatValue], duration);
            } else if ([op isEqualToString:@"line"]) {
                if ([nums count] != 4) {
                    uiError = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                        userInfo:@{NSLocalizedDescriptionKey: ZXDbgError(@"line format: line;;x1,y1,x2,y2[;;duration].")}];
                    return;
                }
                ZXDbgDrawLine(CGPointMake([nums[0] floatValue], [nums[1] floatValue]),
                              CGPointMake([nums[2] floatValue], [nums[3] floatValue]),
                              duration);
            } else {
                uiError = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                    userInfo:@{NSLocalizedDescriptionKey: ZXDbgError(@"Unknown debug op (rect|circle|line|clear).")}];
            }
        } @catch (NSException *e) {
            uiError = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
                userInfo:@{NSLocalizedDescriptionKey: ZXDbgError([@"Exception: " stringByAppendingString:e.reason ?: @""])}];
        }
    });

    if (uiError && error) *error = uiError;
    return (uiError ? nil : result);
}
