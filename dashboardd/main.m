#import <Foundation/Foundation.h>

// Implemented in ../zxtouch/zxtouch/RemoteDashboardServer.m
// (compiled with ZX_DASHBOARD_SPRINGBOARD_SERVER=1). Owns the runloop forever.
int ZXDashboardDaemonMain(void);

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return ZXDashboardDaemonMain();
    }
}
