#import <Cocoa/Cocoa.h>
#import "SetupState.h"

@protocol ADSetupDelegate <NSObject>
- (void)setupStartPreview;
- (NSString *)setupMoveApplication:(NSRunningApplication *)application;
- (void)setupDidFinish;
@end

@interface ADSetupWindowController : NSWindowController
- (instancetype)initWithState:(ADSetupState *)state delegate:(id<ADSetupDelegate>)delegate;
- (void)showSetup;
- (void)showPermissions;
- (void)updatePreviewConnecting;
- (void)updatePreviewLive:(BOOL)live message:(NSString *)message;
@end
