// Compile the implementation into this small test executable so its inventory
// helpers can be tested without asking macOS for screen or Accessibility access.
#import "../src/WindowMover.m"

@interface TestApplication : NSObject
@property pid_t processIdentifier;
@property NSApplicationActivationPolicy activationPolicy;
@property(getter=isTerminated) BOOL terminated;
@property(copy) NSString *localizedName;
@end
@implementation TestApplication
@end

static TestApplication *App(pid_t pid, NSString *name, NSApplicationActivationPolicy policy, BOOL terminated) {
    TestApplication *app = [TestApplication new];
    app.processIdentifier = pid;
    app.localizedName = name;
    app.activationPolicy = policy;
    app.terminated = terminated;
    return app;
}

static NSDictionary *Window(pid_t pid, CGRect bounds, BOOL onScreen, NSInteger layer, double alpha) {
    return @{
        (__bridge NSString *)kCGWindowOwnerPID: @(pid),
        (__bridge NSString *)kCGWindowBounds: CFBridgingRelease(CGRectCreateDictionaryRepresentation(bounds)),
        (__bridge NSString *)kCGWindowIsOnscreen: @(onScreen),
        (__bridge NSString *)kCGWindowLayer: @(layer),
        (__bridge NSString *)kCGWindowAlpha: @(alpha)
    };
}

static void Check(BOOL condition, NSString *description) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", description.UTF8String);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        NSArray *running = @[
            App(10, @"Zebra", NSApplicationActivationPolicyRegular, NO),
            App(20, @"alpha", NSApplicationActivationPolicyRegular, NO),
            App(30, @"Quit app", NSApplicationActivationPolicyRegular, YES),
            App(40, @"Menu bar helper", NSApplicationActivationPolicyAccessory, NO),
            App(50, @"Background service", NSApplicationActivationPolicyProhibited, NO),
            App(60, @"Windowless app", NSApplicationActivationPolicyRegular, NO),
            App(999, @"Self", NSApplicationActivationPolicyRegular, NO)
        ];
        NSArray *apps = UserApplications(running, 999);
        Check([[apps valueForKey:@"processIdentifier"] isEqual:@[@20, @60, @10]],
              @"All running desktop apps are included, even without windows; quit/helper/self processes are excluded and names sorted.");
        Check(UserApplications(@[], 999).count == 0, @"No running apps produces an empty menu.");

        CGRect agent = CGRectMake(-1920, 0, 1920, 1080);
        CGRect onAgent = CGRectMake(-1600, 100, 600, 400);
        CGRect onMain = CGRectMake(100, 100, 600, 400);
        NSArray *windows = @[
            Window(10, onAgent, YES, 0, 1),
            Window(10, onAgent, YES, 0, 1),
            Window(20, onMain, YES, 0, 1),
            Window(30, onAgent, NO, 0, 1), // hidden, minimized, or another Space
            Window(40, onAgent, YES, 0, 0), // transparent cached window
            Window(50, onAgent, YES, 24, 1), // menu/overlay
            Window(60, CGRectMake(-100, 100, 0, 0), YES, 0, 1),
            Window(70, CGRectMake(-40, 100, 200, 200), YES, 0, 1), // center on main
            Window(80, CGRectMake(-160, 100, 200, 200), YES, 0, 1), // center on Agent
            Window(90, onMain, YES, 0, 1),
            Window(90, onAgent, YES, 0, 1), // app has windows on both displays
            @{(__bridge NSString *)kCGWindowOwnerPID: @100,
              (__bridge NSString *)kCGWindowIsOnscreen: @YES,
              (__bridge NSString *)kCGWindowAlpha: @1} // incomplete bounds
        ];
        Check([VisibleWindowOwners(windows, agent) isEqual:[NSSet setWithArray:@[@10, @80, @90]]],
              @"Return menu includes only visible Agent Display window owners, once per app, with negative coordinates handled correctly.");
        Check(VisibleWindowOwners(@[], agent).count == 0, @"An empty Agent Display has no return candidates.");
        Check(VisibleWindowOwners(windows, CGRectZero).count == 0, @"A disconnected display has no return candidates.");
        puts("Window inventory tests passed.");
    }
    return 0;
}
