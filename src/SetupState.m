#import "SetupState.h"

@interface ADSetupState ()
@property(strong) NSUserDefaults *defaults;
@end

@implementation ADSetupState
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) {
        _defaults = defaults;
        // A previous version writes WorkspaceStopped after creating or stopping
        // its display. Preserve that installation's normal launch behavior.
        if (![defaults objectForKey:@"AgentDisplaySetupCompleted"] &&
            ![defaults objectForKey:@"AgentDisplaySetupStep"] &&
            [defaults objectForKey:@"WorkspaceStopped"]) {
            [defaults setBool:YES forKey:@"AgentDisplaySetupCompleted"];
        }
        if (!self.completed && ![defaults objectForKey:@"AgentDisplaySetupStep"])
            self.step = ADSetupWelcome;
    }
    return self;
}
- (ADSetupStep)step {
    NSInteger value = [self.defaults integerForKey:@"AgentDisplaySetupStep"];
    return value >= ADSetupWelcome && value <= ADSetupWorkspace ? value : ADSetupWelcome;
}
- (void)setStep:(ADSetupStep)step {
    [self.defaults setInteger:step forKey:@"AgentDisplaySetupStep"];
}
- (BOOL)completed { return [self.defaults boolForKey:@"AgentDisplaySetupCompleted"]; }
- (BOOL)completeWithLivePreview:(BOOL)live {
    if (!live) return NO;
    [self.defaults setBool:YES forKey:@"AgentDisplaySetupCompleted"];
    return YES;
}
@end
