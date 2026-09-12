#ifndef CRANE_BRIDGE_H
#define CRANE_BRIDGE_H

#import <Foundation/Foundation.h>

// Phase 2 (Crane parity, ioscontrol.md sec-crane). Single task, JSON protocol:
//   TASK_CRANE(47) in:  base64({"op":"list|switch|create|delete|wipe|rename|clearData|backup|restore|size", ...})
//   reply: "0;;base64(json result)" or "-1;;message".
// Crane (paid, com.opa334.crane) is loaded dynamically via dlopen +
// NSClassFromString, so this tweak builds without libcrane.tbd and runs
// fine when Crane is not installed (calls fail with a clear error).
// Requires full Crane — NOT Crane Lite.
NSString *craneFromRawData(UInt8 *eventData, NSError **error);

#endif
