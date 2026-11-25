// Isolated AppKit checks. These stubs never request OS permissions, create a
// display, or move a real window. Do not link them into the shipping app.
#import <Cocoa/Cocoa.h>
#import "../src/SetupWindowController.h"
#import "../src/WindowMover.h"

static BOOL screenAllowed, movementAllowed;
static NSUInteger permissionRequests;
bool CGPreflightScreenCaptureAccess(void) { return screenAllowed; }
bool CGRequestScreenCaptureAccess(void) { permissionRequests++; return screenAllowed; }
NSScreen *MainPhysicalScreen(void) { return NSScreen.mainScreen; }
NSArray *OpenApplications(void) { return @[]; }
BOOL WindowMovementAllowed(void) { return movementAllowed; }

@interface ADSetupWindowController (Testing)
- (void)renderStep;
- (void)refreshPermissions;
- (void)continueSetup:(id)sender;
- (void)startPreview:(id)sender;
- (void)goBack:(id)sender;
@end
@interface SetupTestDefaults : NSUserDefaults
@property(strong) NSMutableDictionary *values;
@end
@implementation SetupTestDefaults
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary new]; return self; }
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (NSInteger)integerForKey:(NSString *)key { return [self.values[key] integerValue]; }
- (BOOL)boolForKey:(NSString *)key { return [self.values[key] boolValue]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key { self.values[key] = @(value); }
- (void)setBool:(BOOL)value forKey:(NSString *)key { self.values[key] = @(value); }
@end
@interface SetupTestDelegate : NSObject <ADSetupDelegate>
@property NSUInteger starts;
@property NSUInteger finishes;
@end
@implementation SetupTestDelegate
- (void)setupStartPreview { self.starts++; }
- (NSString *)setupMoveApplication:(NSRunningApplication *)application { return nil; }
- (void)setupDidFinish { self.finishes++; }
@end
static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static void Render(ADSetupWindowController *controller, NSString *name) {
    NSView *view = controller.window.contentView;
    [view layoutSubtreeIfNeeded];
    NSView *body = [controller valueForKey:@"body"];
    NSButton *primary = [controller valueForKey:@"primary"];
    NSRect bodyFrame = [body convertRect:body.bounds toView:view];
    NSRect footerFrame = [primary.superview convertRect:primary.superview.bounds toView:view];
    Check(NSMinY(bodyFrame) >= NSMaxY(footerFrame), @"Setup content must not overlap the footer.");
    Check(NSContainsRect(view.bounds, bodyFrame), @"Setup content must fit inside the window.");
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    // The standard window background lives behind contentView; include it in
    // the export so light and dark text can be inspected without transparency.
    NSImage *image = [[NSImage alloc] initWithSize:view.bounds.size];
    NSImage *snapshot = [[NSImage alloc] initWithSize:view.bounds.size];
    [snapshot addRepresentation:bitmap];
    [controller.window.effectiveAppearance performAsCurrentDrawingAppearance:^{
        [image lockFocus];
        [NSColor.windowBackgroundColor setFill];
        NSRectFill(view.bounds);
        [snapshot drawInRect:view.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        [image unlockFocus];
    }];
    NSBitmapImageRep *opaque = [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
    NSString *path = [@"build/setup-ui/" stringByAppendingFormat:@"%@.png", name];
    Check([[opaque representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"Write setup render.");
}
int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        app.applicationIconImage = [[NSImage alloc] initWithContentsOfFile:@"assets/AppIcon.icns"];
        [[NSFileManager defaultManager] createDirectoryAtPath:@"build/setup-ui" withIntermediateDirectories:YES attributes:nil error:nil];
        ADSetupState *state = [[ADSetupState alloc] initWithDefaults:[SetupTestDefaults new]];
        SetupTestDelegate *delegate = [SetupTestDelegate new];
        ADSetupWindowController *controller = [[ADSetupWindowController alloc] initWithState:state delegate:delegate];
        NSButton *primary = [controller valueForKey:@"primary"];
        for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            controller.window.appearance = [NSAppearance appearanceNamed:appearance];
            NSString *theme = [appearance isEqual:NSAppearanceNameAqua] ? @"light" : @"dark";
            for (NSInteger step = ADSetupWelcome; step <= ADSetupWorkspace; step++) {
                state.step = step;
                [controller renderStep];
                Render(controller, [NSString stringWithFormat:@"%@-%ld", theme, (long)step]);
            }
        }
        Check(permissionRequests == 0 && delegate.starts == 0, @"Simply viewing setup cannot prompt or start capture.");
        state.step = ADSetupWelcome;
        [controller renderStep];
        [controller continueSetup:nil];
        Check(state.step == ADSetupPermissions && !primary.enabled, @"Screen access is required before continuing.");
        [controller continueSetup:nil];
        Check(state.step == ADSetupPermissions, @"A disabled action cannot bypass the permission gate.");
        screenAllowed = YES;
        [controller refreshPermissions];
        Check(primary.enabled, @"A permission change is detected without rebuilding the window.");
        [controller continueSetup:nil];
        Check(state.step == ADSetupWorkspace && !primary.enabled, @"Accessibility is optional; a real preview is still required.");
        [controller startPreview:nil];
        Check(delegate.starts == 1 && !primary.enabled, @"Starting capture does not mark setup as finished.");
        [controller updatePreviewLive:NO message:@"macOS declined the capture request. Check Screen & System Audio Recording, then quit and reopen Agent Display if permission was just enabled."];
        Check(!primary.enabled && !state.completed && [[controller valueForKey:@"retry"] isEnabled], @"A failed preview remains retryable and cannot finish setup.");
        Render(controller, @"dark-error");
        [controller updatePreviewLive:YES message:@"✓ Preview is live · 3840 × 2160"];
        Check(primary.enabled && ![[controller valueForKey:@"apps"] isEnabled], @"Preview-only setup can finish without Accessibility.");
        movementAllowed = YES;
        [controller refreshPermissions];
        Check([[controller valueForKey:@"apps"] isEnabled], @"The app picker unlocks after Accessibility is enabled.");
        Render(controller, @"dark-live");
        [controller updatePreviewConnecting];
        Check(!primary.enabled, @"Restarting capture invalidates the previously live preview.");
        [[controller valueForKey:@"previewTimer"] fire];
        Check(!primary.enabled && [[controller valueForKey:@"retry"] isEnabled], @"A stalled preview times out into a retryable state.");
        [controller updatePreviewLive:YES message:@"✓ Preview is live · 3840 × 2160"];
        [controller continueSetup:nil];
        Check(state.completed && delegate.finishes == 1, @"Finish persists completion only after a live preview.");
        puts("Setup UI checks passed; light/dark renders are in build/setup-ui/.");
    }
    return 0;
}
