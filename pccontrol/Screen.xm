#include "Screen.h"
#include "Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wavailability"
#pragma clang diagnostic ignored "-Wattributes"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include "headers/IOSurface/IOSurfaceAccelerator.h"
#include "headers/IOSurface/IOMobileFramebuffer.h"
#import "headers/IOSurface/IOSurface.h"
#include "headers/IOSurface/CoreSurface.h"
#pragma clang diagnostic pop

OBJC_EXTERN void CARenderServerRenderDisplay(kern_return_t a, CFStringRef b, IOSurfaceRef surface, int x, int y);
OBJC_EXTERN kern_return_t IOSurfaceLock(IOSurfaceRef buffer, IOSurfaceLockOptions options, uint32_t *seed);
OBJC_EXTERN kern_return_t IOSurfaceUnLock(IOSurfaceRef buffer, IOSurfaceLockOptions options, uint32_t *seed);
OBJC_EXTERN IOSurfaceRef IOSurfaceCreate(CFDictionaryRef dictionary);
OBJC_EXTERN CGImageRef UICreateCGImageFromIOSurface(IOSurfaceRef surface);

static CGFloat device_screen_width = 0;
static CGFloat device_screen_height = 0;

@implementation Screen
{
    // device screen size
}


/*
Get the size of the screen and set them.
*/
+ (void)setScreenSize:(CGFloat)x height:(CGFloat) y
{
	device_screen_width = x;
	device_screen_height = y;

	if (device_screen_width == 0 || device_screen_height == 0 || device_screen_width > 10000 || device_screen_height > 10000)
	{
		NSLog(@"com.zjx.springboard: Unable to initialze the screen size. screen width: %f, screen height: %f", device_screen_width, device_screen_height);
	}
	else
	{
		NSLog(@"com.zjx.springboard: successfully initialize the screen size. screen width: %f, screen height: %f", device_screen_width, device_screen_height);
	}
}

+ (int)getScreenOrientation
{
    __block int screenOrientation = -1;

    void (^readOrientation)(void) = ^{
        @try{
            SpringBoard *springboard = (SpringBoard*)[%c(SpringBoard) sharedApplication];
            screenOrientation = [springboard _frontMostAppOrientation];
            //NSLog(@"com.zjx.springboard: orientation %d", screenOrientation);
        }
        @catch (NSException *exception) {
            NSLog(@"com.zjx.springboard: Debug: %@", exception.reason);
        }
    };

    if ([NSThread isMainThread]) {
        readOrientation();
    } else {
        dispatch_sync(dispatch_get_main_queue(), readOrientation);
    }

    return screenOrientation;
}

+ (CGFloat)getScreenWidth
{
    if (device_screen_width == 0)
    {
        NSLog(@"com.zjx.springboard: Cannot get screen width. Maybe you call [Screen getScreenWidth] before springboard getting the screen size.");
    }
    return device_screen_width;
}

+ (CGFloat)getScreenHeight
{
    if (device_screen_height == 0)
    {
        NSLog(@"com.zjx.springboard: Cannot get screen height. Maybe you call [Screen getScreenHeight] before springboard getting the screen size.");
    }
    return device_screen_height;
}

+ (CGFloat)getScale
{    
    return [[UIScreen mainScreen] scale];
}

+ (CGRect)getBounds
{
    return [UIScreen mainScreen].bounds;
}


OBJC_EXTERN UIImage *_UICreateScreenUIImage(void);
+ (NSString*)screenShot
{
    UIImage *screenImage = _UICreateScreenUIImage();
    // Create path.
    NSString *filePath = [getDocumentRoot() stringByAppendingPathComponent:@"screenshot.png"];

    // Save image.
    [UIImagePNGRepresentation(screenImage) writeToFile:filePath atomically:NO];
    return filePath;
}

+ (UIImage*)screenShotUIImage // memory leak, need to be fixed
{
    return _UICreateScreenUIImage();
}

+ (CGImageRef)createScreenShotCGImageRef
{
    static IOSurfaceRef cachedSurface = NULL;
    static int cachedWidth = 0;
    static int cachedHeight = 0;
    static int cachedBytesPerRow = 0;
    @synchronized([Screen class]) {
    Boolean isiPad8orUp = false;

    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize screenSize = [UIScreen mainScreen].bounds.size;

    int height = (int)(screenSize.height * scale);
    int width = (int)(screenSize.width * scale);

    // check whether it is ipad8 or later
    NSString *searchText = getDeviceName();

    NSRange range = [searchText rangeOfString:@"^iPad[8-9]|iPad[1-9][0-9]+" options:NSRegularExpressionSearch];
    if (range.location != NSNotFound) { // ipad pro (3rd) or later
        isiPad8orUp = true;
    }

    if (isiPad8orUp)
    {
        if (width < height)
        {
            int temp = width;
            width = height;
            height = temp;
        }
    }
    else
    {
        if (width > height)
        {
            int temp = width;
            width = height;
            height = temp;
        }
    }

    int bytesPerElement = 4;
    int bytesPerRow = roundUp(bytesPerElement * width, 32);

    NSNumber *IOSurfaceBytesPerElement = [NSNumber numberWithInteger:bytesPerElement]; 
    NSNumber *IOSurfaceBytesPerRow = [NSNumber numberWithInteger:bytesPerRow]; // don't know why but it should be a multiple of 32
    NSNumber *IOSurfaceAllocSize = [NSNumber numberWithInteger:bytesPerRow * height]; 
    NSNumber *nheight = [NSNumber numberWithInteger:height]; 
    NSNumber *nwidth = [NSNumber numberWithInteger:width]; 
    NSNumber *IOSurfacePixelFormat = [NSNumber numberWithInteger:1111970369]; 
    NSNumber *IOSurfaceIsGlobal = [NSNumber numberWithInteger:1]; 

    NSDictionary *properties = [[NSDictionary alloc] initWithObjectsAndKeys:IOSurfaceAllocSize, @"IOSurfaceAllocSize"
                                , IOSurfaceBytesPerElement, @"IOSurfaceBytesPerElement", IOSurfaceBytesPerRow, @"IOSurfaceBytesPerRow", nheight, @"IOSurfaceHeight", 
                                IOSurfaceIsGlobal, @"IOSurfaceIsGlobal", IOSurfacePixelFormat, @"IOSurfacePixelFormat", nwidth, @"IOSurfaceWidth", nil];    

    BOOL cacheChanged = cachedSurface == NULL || cachedWidth != width ||
        cachedHeight != height || cachedBytesPerRow != bytesPerRow;
    if (cacheChanged) {
        if (cachedSurface) CFRelease(cachedSurface);
        cachedSurface = IOSurfaceCreate((__bridge CFDictionaryRef)(properties));
        cachedWidth = width;
        cachedHeight = height;
        cachedBytesPerRow = bytesPerRow;
        NSLog(@"[ZXTouch][OCR][capture] surface_create width=%d height=%d bytes=%d ok=%d",
              width, height, bytesPerRow * height, cachedSurface != NULL);
    } else {
        NSLog(@"[ZXTouch][OCR][capture] surface_reuse width=%d height=%d", width, height);
    }

    properties = nil;
    if (!cachedSurface) {
        NSLog(@"[ZXTouch][OCR][capture] surface_create_failed");
        return nil;
    }
    kern_return_t lockResult = IOSurfaceLock(cachedSurface, 0, NULL);
    if (lockResult != KERN_SUCCESS) {
        NSLog(@"[ZXTouch][OCR][capture] surface_lock_failed status=%d", lockResult);
        return nil;
    }
    NSLog(@"[ZXTouch][OCR][capture] render_start");
    CARenderServerRenderDisplay(0, CFSTR("LCD"), cachedSurface, 0, 0);
        
    CGImageRef cgImageRef = nil;
    if (cachedSurface) {
        cgImageRef = UICreateCGImageFromIOSurface(cachedSurface);
        if (!cgImageRef) {
            NSLog(@"[ZXTouch][OCR][capture] cgimage_create_failed");
        }
        if (!cgImageRef) {
            IOSurfaceUnlock(cachedSurface, 0, NULL);
            return nil;
        }
        CGImageRef detachedImage = CGImageCreateCopy(cgImageRef);
        CGImageRelease(cgImageRef);
        cgImageRef = detachedImage;
        if (!cgImageRef) {
            NSLog(@"[ZXTouch][OCR][capture] cgimage_detach_failed");
            IOSurfaceUnlock(cachedSurface, 0, NULL);
            return nil;
        }
        int targetWidth = CGImageGetWidth(cgImageRef);
        int targetHeight = CGImageGetHeight(cgImageRef);

        if (isiPad8orUp) // rotate 90 degrees counterclockwise
        {
            CGColorSpaceRef colorSpaceInfo = CGImageGetColorSpace(cgImageRef);
            CGContextRef bitmap;

            //if (sourceImage.imageOrientation == UIImageOrientationUp || sourceImage.imageOrientation == UIImageOrientationDown) {
                bitmap = CGBitmapContextCreate(NULL, targetHeight, targetWidth, CGImageGetBitsPerComponent(cgImageRef), CGImageGetBytesPerRow(cgImageRef), colorSpaceInfo, kCGImageAlphaPremultipliedFirst);
            //} else {
                //bitmap = CGBitmapContextCreate(NULL, targetHeight, targetWidth, CGImageGetBitsPerComponent(cgImageRef), CGImageGetBytesPerRow(imageRef), colorSpaceInfo, bitmapInfo);

            //}   

            CGFloat degrees = -90.f;
            CGFloat radians = degrees * (M_PI / 180.f);

            CGContextTranslateCTM (bitmap, 0.5*targetHeight, 0.5*targetWidth);
            CGContextRotateCTM (bitmap, radians);
            CGContextTranslateCTM (bitmap, -0.5*targetWidth, -0.5*targetHeight);

            CGContextDrawImage(bitmap, CGRectMake(0, 0, targetWidth, targetHeight), cgImageRef);
            
            CGImageRelease(cgImageRef);
            cgImageRef = CGBitmapContextCreateImage(bitmap);

            CGColorSpaceRelease(colorSpaceInfo);
            CGContextRelease(bitmap);
        }
    }
    IOSurfaceUnlock(cachedSurface, 0, NULL);
    NSLog(@"[ZXTouch][OCR][capture] render_complete image=1");

    return cgImageRef;
    }
}


+ (NSString*)screenShotAlwaysUp
{
     UIImage *screenImage = _UICreateScreenUIImage();
    int orientation = [self getScreenOrientation];

    UIImageOrientation after = UIImageOrientationUp;
    if (orientation == 4)
    {
        after = UIImageOrientationRight;
    }
    else if (orientation == 3)
    {
        after = UIImageOrientationLeft;
    }
    else if (orientation == 2)
    {
        after = UIImageOrientationDown;
    }

    UIImage *result = [UIImage imageWithCGImage:[screenImage CGImage]
              scale:[screenImage scale]
              orientation: after];

    // Create path.
    NSString *filePath = [getDocumentRoot() stringByAppendingPathComponent:@"screenshot.png"];

    // Save image.
    [UIImagePNGRepresentation(result) writeToFile:filePath atomically:NO];
    return filePath;
}
@end
