#ifndef DEBUG_OVERLAY_H
#define DEBUG_OVERLAY_H

#import <Foundation/Foundation.h>

// TASK_DEBUG_MARK=48 — runtime debug shapes for scripts.
// All coordinates are DEVICE PIXELS (same unit as tap/OCR/image match).
// Shapes are drawn in solid red, non-interactive, auto-fade.
//
// Wire payload (eventData after the 2-digit task id):
//   "rect;;x,y,w,h[;;duration]"          — bounding box of OCR / image match
//   "circle;;x,y,r[;;duration]"          — tap point (r in pixels)
//   "line;;x1,y1,x2,y2[;;duration]"      — swipe segment
//   "clear"                             — hide all immediately
//
// duration: seconds each shape stays visible (default 1.5, clamped 0.3..5).
// Minimum visible sizes are enforced natively so callers can pass raw
// match boxes: rect border >= 3pt, circle r >= 20pt, line width >= 4pt.
NSString *debugMarkFromRawData(UInt8 *eventData, NSError **error);

#endif
