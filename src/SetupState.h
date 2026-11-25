#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ADSetupStep) {
    ADSetupWelcome,
    ADSetupPermissions,
    ADSetupWorkspace
};

// Progress survives the quit/reopen that macOS can require for screen access.
@interface ADSetupState : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
@property ADSetupStep step;
@property(readonly) BOOL completed;
- (BOOL)completeWithLivePreview:(BOOL)live;
@end
