#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <IOSurface/IOSurfaceRef.h>
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

extern "C" void CARenderServerRenderDisplay(kern_return_t, CFStringRef, IOSurfaceRef, int, int);
extern "C" IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties);
extern "C" kern_return_t IOSurfaceLock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
extern "C" kern_return_t IOSurfaceUnlock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
extern "C" CGImageRef UICreateCGImageFromIOSurface(IOSurfaceRef);

// Private UIScreen API (same one TrollVNC's daemon uses): the only reliable
// way to get the real pixel size inside a launchd daemon that has no
// UIApplication scene. mainScreen.bounds is CGRectZero there.
@interface UIScreen (ZXOcrPrivate)
- (CGRect)_unjailedReferenceBoundsInPixels;
@end

static void ZXScreenPixelSize(int *outWidth, int *outHeight) {
    int width = 0, height = 0;
    UIScreen *screen = [UIScreen mainScreen];
    if ([screen respondsToSelector:@selector(_unjailedReferenceBoundsInPixels)]) {
        CGSize pixels = [screen _unjailedReferenceBoundsInPixels].size;
        width = (int)round(pixels.width);
        height = (int)round(pixels.height);
        NSLog(@"[ZXTouch][OCRD][capture] size_source=unjailedReferenceBounds w=%d h=%d", width, height);
    }
    if (width <= 0 || height <= 0) {
        CGSize bounds = screen.bounds.size;
        CGFloat scale = screen.scale;
        width = (int)round(bounds.width * scale);
        height = (int)round(bounds.height * scale);
        NSLog(@"[ZXTouch][OCRD][capture] size_source=bounds*scale bounds=%@ scale=%.2f w=%d h=%d",
              NSStringFromCGSize(bounds), (double)scale, width, height);
    }
    if (width <= 0 || height <= 0) {
        CGSize native = screen.nativeBounds.size;
        width = (int)round(native.width);
        height = (int)round(native.height);
        NSLog(@"[ZXTouch][OCRD][capture] size_source=nativeBounds w=%d h=%d", width, height);
    }
    if (outWidth) *outWidth = width;
    if (outHeight) *outHeight = height;
}

static NSString *const kSocketPath = @"/var/mobile/Library/ZXTouch/ocrd.sock";
static IOSurfaceRef sSurface = NULL;
static int sWidth = 0, sHeight = 0, sBytesPerRow = 0;

static BOOL readExact(int fd, void *buffer, size_t length) {
    uint8_t *p = (uint8_t *)buffer;
    while (length) { ssize_t n = recv(fd, p, length, 0); if (n <= 0) return NO; p += n; length -= (size_t)n; }
    return YES;
}
static BOOL writeExact(int fd, const void *buffer, size_t length) {
    const uint8_t *p = (const uint8_t *)buffer;
    while (length) { ssize_t n = send(fd, p, length, MSG_NOSIGNAL); if (n <= 0) return NO; p += n; length -= (size_t)n; }
    return YES;
}

static CGImageRef captureScreen(void) {
    int width = 0, height = 0;
    ZXScreenPixelSize(&width, &height);
    if (width <= 0 || height <= 0) {
        NSLog(@"[ZXTouch][OCRD][capture] invalid_size w=%d h=%d", width, height);
        return nil;
    }
    int bytesPerRow = (width * 4 + 31) & ~31;
    @synchronized([NSValue class]) {
        if (!sSurface || width != sWidth || height != sHeight || bytesPerRow != sBytesPerRow) {
            if (sSurface) CFRelease(sSurface);
            NSDictionary *properties = @{
                // NOTE: no IOSurfaceIsGlobal here — global surfaces can only
                // be created by the window-server host (SpringBoard). In a
                // daemon it makes IOSurfaceCreate return NULL. TrollVNC's
                // daemon captures with the same non-global properties.
                @"IOSurfaceAllocSize": @(bytesPerRow * height),
                @"IOSurfaceBytesPerElement": @4,
                @"IOSurfaceBytesPerRow": @(bytesPerRow),
                @"IOSurfaceWidth": @(width),
                @"IOSurfaceHeight": @(height),
                @"IOSurfacePixelFormat": @0x42475241,
            };
            sSurface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
            sWidth = width; sHeight = height; sBytesPerRow = bytesPerRow;
            NSLog(@"[ZXTouch][OCRD][capture] surface_create width=%d height=%d bytes=%d ok=%d", width, height, bytesPerRow * height, sSurface != NULL);
        } else {
            NSLog(@"[ZXTouch][OCRD][capture] surface_reuse width=%d height=%d", width, height);
        }
        if (!sSurface) {
            NSLog(@"[ZXTouch][OCRD][capture] surface_create_failed");
            return nil;
        }

        // The render server is the producer of this surface. Do not hold an
        // IOSurface lock while asking it to render; daemon captures such as
        // TrollVNC render first and lock only when reading the pixels.
        NSLog(@"[ZXTouch][OCRD][capture] render_start");
        CARenderServerRenderDisplay(0, CFSTR("LCD"), sSurface, 0, 0);
        NSLog(@"[ZXTouch][OCRD][capture] render_complete");

        kern_return_t lockResult = IOSurfaceLock(sSurface, 0, NULL);
        if (lockResult != KERN_SUCCESS) {
            NSLog(@"[ZXTouch][OCRD][capture] surface_lock_failed status=%d", lockResult);
            return nil;
        }
        CGImageRef image = UICreateCGImageFromIOSurface(sSurface);
        CGImageRef detachedImage = image ? CGImageCreateCopy(image) : NULL;
        if (image) CGImageRelease(image);
        IOSurfaceUnlock(sSurface, 0, NULL);
        NSLog(@"[ZXTouch][OCRD][capture] image_copy_complete image=%d", detachedImage != NULL);
        if (!detachedImage) NSLog(@"[ZXTouch][OCRD][capture] cgimage_detach_failed");
        return detachedImage;
    }
}

static NSString *recognize(NSString *payload, NSError **error) {
    NSArray *parts = [payload componentsSeparatedByString:@";;"];
    if (parts.count < 8 || [parts[0] intValue] != 1) return nil;
    NSArray *rect = [parts[1] componentsSeparatedByString:@",,"];
    if (rect.count < 4) return nil;
    CGRect area = CGRectMake([rect[0] floatValue], [rect[1] floatValue], [rect[2] floatValue], [rect[3] floatValue]);
    NSString *requestId = parts.count > 9 ? parts[9] : @"0";
    NSLog(@"[ZXTouch][OCRD][id=%@] request_start", requestId);
    CGImageRef screenshot = captureScreen();
    if (!screenshot) { NSLog(@"[ZXTouch][OCRD][id=%@][capture] failed", requestId); if (error) *error = [NSError errorWithDomain:@"com.zjx.zxtouch.ocrd" code:11 userInfo:@{NSLocalizedDescriptionKey:@"screen capture failed"}]; return nil; }
    CIImage *image = [[CIImage alloc] initWithCGImage:screenshot];
    CFRelease(screenshot);
    int orientation = parts.count > 8 ? [parts[8] intValue] : 1;
    int after = kCGImagePropertyOrientationUp;
    if (orientation == 4) after = kCGImagePropertyOrientationRight;
    else if (orientation == 3) after = kCGImagePropertyOrientationLeft;
    else if (orientation == 2) after = kCGImagePropertyOrientationDown;
    image = [image imageByApplyingOrientation:after];
    CGRect crop = CGRectMake(area.origin.x, image.extent.size.height - area.origin.y - area.size.height, area.size.width, area.size.height);
    if (area.size.width <= 0 || area.size.height <= 0) crop = image.extent;
    image = [image imageByCroppingToRect:crop];
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:nil];
    if (@available(iOS 14.0, *)) request.revision = 2;
    else if (@available(iOS 13.0, *)) request.revision = 1;
    request.recognitionLevel = [parts[4] intValue] == 1 ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
    // Keep the v0.3.12 behavior: an omitted minimum height means no
    // minimum-height filter, so small labels are still eligible for OCR.
    request.minimumTextHeight = [parts[3] floatValue] > 0 ? [parts[3] floatValue] : 0.0f;
    if ([parts[2] length]) request.customWords = [parts[2] componentsSeparatedByString:@",,"];
    if ([parts[5] length]) request.recognitionLanguages = [parts[5] componentsSeparatedByString:@",,"];
    request.usesLanguageCorrection = [parts[6] boolValue];
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCIImage:image options:@{}];
    NSError *visionError = nil;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    [handler performRequests:@[request] error:&visionError];
    if (visionError) { if (error) *error = visionError; NSLog(@"[ZXTouch][OCRD][id=%@][vision] failed elapsed_ms=%.1f error=%@", requestId, (CFAbsoluteTimeGetCurrent() - start) * 1000.0, visionError); return nil; }
    NSMutableArray *items = [NSMutableArray array];
    for (VNRecognizedTextObservation *observation in request.results) {
        NSArray *candidates = [observation topCandidates:1];
        if (!candidates.count) continue;
        VNRecognizedText *text = candidates[0]; NSString *value = text.string ?: @"";
         NSError *boxError = nil;
         VNRectangleObservation *box = [text boundingBoxForRange:NSMakeRange(0, value.length) error:&boxError];
        if (!box) box = (VNRectangleObservation *)observation;
        int x = (int)lroundf(box.topLeft.x * area.size.width + area.origin.x);
        int y = (int)lroundf((1 - box.topLeft.y) * area.size.height + area.origin.y);
        int w = (int)lroundf((box.topRight.x - box.topLeft.x) * area.size.width);
         int h = (int)lround((double)fabs(box.topLeft.y - box.bottomLeft.y) * area.size.height);
        [items addObject:[NSString stringWithFormat:@"%@,,%d,,%d,,%d,,%d", value, x, y, w, h]];
    }
    NSLog(@"[ZXTouch][OCRD][id=%@][vision] complete elapsed_ms=%.1f observations=%lu results=%lu", requestId, (CFAbsoluteTimeGetCurrent() - start) * 1000.0, (unsigned long)request.results.count, (unsigned long)items.count);
    return [items componentsJoinedByString:@";;"];
}

static void serveClient(int fd) {
    @autoreleasepool {
        uint32_t length = 0; if (!readExact(fd, &length, sizeof(length))) return; length = ntohl(length);
        if (!length || length > 64 * 1024) return;
        NSMutableData *data = [NSMutableData dataWithLength:length + 1]; if (!readExact(fd, data.mutableBytes, length)) return;
        ((char *)data.mutableBytes)[length] = 0; NSError *error = nil;
        NSString *payload = [[NSString alloc] initWithBytes:data.bytes length:length encoding:NSUTF8StringEncoding];
        NSString *response = recognize(payload, &error); if (!response) response = [NSString stringWithFormat:@"-1;;%@", error.localizedDescription ?: @"OCR failed"];
        NSData *out = [response dataUsingEncoding:NSUTF8StringEncoding]; uint32_t n = htonl((uint32_t)out.length);
        writeExact(fd, &n, sizeof(n)); writeExact(fd, out.bytes, out.length);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *dir = [kSocketPath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        unlink(kSocketPath.UTF8String); int server = socket(AF_UNIX, SOCK_STREAM, 0); if (server < 0) return 2;
        struct sockaddr_un address = {}; address.sun_family = AF_UNIX; strlcpy(address.sun_path, kSocketPath.UTF8String, sizeof(address.sun_path));
        if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(server, 1) != 0) return 3;
        chmod(kSocketPath.UTF8String, 0660); chown(kSocketPath.UTF8String, 501, 501);
        NSLog(@"[ZXTouch][OCRD] ready socket=%@", kSocketPath);
        for (;;) { int client = accept(server, NULL, NULL); if (client >= 0) { serveClient(client); close(client); } }
    }
}
