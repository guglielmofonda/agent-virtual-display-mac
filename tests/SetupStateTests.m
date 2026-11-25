#import "../src/SetupState.h"

// In-memory defaults exercise relaunches without touching the user's setup or
// privacy grants, and work in build environments without a preference daemon.
@interface TestDefaults : NSUserDefaults
@property(strong) NSMutableDictionary *values;
@end
@implementation TestDefaults
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary new]; return self; }
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (NSInteger)integerForKey:(NSString *)key { return [self.values[key] integerValue]; }
- (BOOL)boolForKey:(NSString *)key { return [self.values[key] boolValue]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key { self.values[key] = @(value); }
- (void)setBool:(BOOL)value forKey:(NSString *)key { self.values[key] = @(value); }
@end

static void Check(BOOL condition, NSString *description) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", description.UTF8String); exit(1); }
}
int main(void) {
    @autoreleasepool {
        TestDefaults *defaults = [TestDefaults new];
        ADSetupState *first = [[ADSetupState alloc] initWithDefaults:defaults];
        Check(!first.completed && first.step == ADSetupWelcome, @"A clean install opens the welcome step.");
        [defaults setBool:NO forKey:@"WorkspaceStopped"];
        Check(![[[ADSetupState alloc] initWithDefaults:defaults] completed], @"Starting from the menu before finishing welcome still resumes setup.");
        first.step = ADSetupPermissions;
        ADSetupState *reopened = [[ADSetupState alloc] initWithDefaults:defaults];
        Check(!reopened.completed && reopened.step == ADSetupPermissions, @"Relaunch after a permission prompt resumes setup.");
        Check(![reopened completeWithLivePreview:NO] && !reopened.completed, @"Denied permission or a failed preview cannot complete setup.");
        reopened.step = ADSetupWorkspace;
        [defaults setBool:NO forKey:@"WorkspaceStopped"];
        ADSetupState *interrupted = [[ADSetupState alloc] initWithDefaults:defaults];
        Check(!interrupted.completed && interrupted.step == ADSetupWorkspace, @"Creating a display during unfinished setup is not mistaken for a legacy installation.");
        Check([interrupted completeWithLivePreview:YES], @"A received live preview can finish setup without requiring Accessibility.");
        ADSetupState *finished = [[ADSetupState alloc] initWithDefaults:defaults];
        Check(finished.completed, @"Completed setup stays completed across launches.");
        finished.step = ADSetupPermissions;
        Check(finished.completed, @"Revisiting permissions does not undo completed onboarding.");
        [defaults setInteger:999 forKey:@"AgentDisplaySetupStep"];
        Check(finished.step == ADSetupWelcome, @"Unknown progress values recover to welcome.");
        for (NSNumber *stopped in @[@NO, @YES]) {
            TestDefaults *legacyDefaults = [TestDefaults new];
            [legacyDefaults setBool:stopped.boolValue forKey:@"WorkspaceStopped"];
            ADSetupState *legacy = [[ADSetupState alloc] initWithDefaults:legacyDefaults];
            Check(legacy.completed, @"Existing installations preserve their running or stopped launch behavior.");
        }
        puts("Setup progress tests passed.");
    }
    return 0;
}
