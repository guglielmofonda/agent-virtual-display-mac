#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <AVFoundation/AVFoundation.h>

#import "Display.h"
#import "WindowMover.h"
#import "SetupWindowController.h"

@interface MonitorPanel : NSPanel
@end
@implementation MonitorPanel
- (NSString *)accessibilityHelp {
    BOOL visible = self.onActiveSpace && (self.occlusionState & NSWindowOcclusionStateVisible);
    return visible ? @"The preview is visible on the current desktop."
                   : @"The preview is outside the visible desktop.";
}
@end

@interface PreviewView : NSView
@property (strong) AVSampleBufferDisplayLayer *video;
@property BOOL live;
@end
@implementation PreviewView
- (void)layout { [super layout]; self.video.frame = self.bounds; }
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    self.video.contentsScale = self.window.backingScaleFactor ?: 1;
}
- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    self.video.contentsScale = self.window.backingScaleFactor ?: 1;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event {
    CGDirectDisplayID target = WorkspaceDisplayID();
    if (!self.live || !target) return;
    CGRect screen = CGDisplayBounds(target);
    CGRect image = AVMakeRectWithAspectRatioInsideRect(screen.size, self.bounds);
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(point, image)) return;
    CGFloat x = (point.x - CGRectGetMinX(image)) / image.size.width;
    CGFloat y = (CGRectGetMaxY(image) - point.y) / image.size.height;
    CGWarpMouseCursorPosition(CGPointMake(screen.origin.x + x * (screen.size.width-1),
                                          screen.origin.y + y * (screen.size.height-1)));
}
@end

@interface Viewer : NSObject <NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, SCStreamDelegate, SCStreamOutput, ADSetupDelegate>
@property (strong) id displayOwner;
@property (strong) NSPanel *panel;
@property (strong) PreviewView *preview;
@property (strong) NSTextField *message;
@property (strong) NSButton *choose;
@property (strong) NSButton *setupHelp;
@property (strong) ADSetupState *setupState;
@property (strong) ADSetupWindowController *setup;
@property (strong) SCStream *stream;
@property (strong) NSStatusItem *statusItem;
@property BOOL transitioning;
@property BOOL connecting;
@property NSUInteger capturesStopping;
@property NSUInteger captureGeneration;
@property CGDirectDisplayID lastDisplayID;
@end
@implementation Viewer
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.setupState = [[ADSetupState alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    [self installMenu];
    NSRect usable = (MainPhysicalScreen() ?: NSScreen.mainScreen).visibleFrame;
    CGFloat width = MIN(480, usable.size.width * 0.4);
    NSRect frame = NSMakeRect(NSMaxX(usable)-width-16, NSMinY(usable)+16, width, width*9/16);
    self.panel = [[MonitorPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.panel.title = @"Agent Display";
    self.panel.delegate = self;
    self.panel.releasedWhenClosed = NO;
    NSTitlebarAccessoryViewController *controls = [NSTitlebarAccessoryViewController new];
    NSButton *controlsButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"ellipsis.circle" accessibilityDescription:@"Desktop Controls"] target:self action:@selector(showControls:)];
    controlsButton.bordered = NO;
    controlsButton.toolTip = @"Desktop Controls";
    controlsButton.accessibilityLabel = @"Desktop Controls";
    controlsButton.frame = NSMakeRect(0, 0, 32, 22);
    controls.view = controlsButton;
    controls.layoutAttribute = NSLayoutAttributeRight;
    [self.panel addTitlebarAccessoryViewController:controls];
    [self.panel setFrameAutosaveName:@"WorkspacePreview"];
    self.panel.floatingPanel = YES;
    self.panel.becomesKeyOnlyIfNeeded = YES;
    self.panel.canHide = NO;
    self.panel.level = NSFloatingWindowLevel;
    self.panel.hidesOnDeactivate = NO;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                    NSWindowCollectionBehaviorFullScreenAuxiliary |
                                    NSWindowCollectionBehaviorCanJoinAllApplications;
    self.panel.contentAspectRatio = NSMakeSize(16,9);
    self.panel.contentMinSize = NSMakeSize(320,180);
    self.preview = [PreviewView new];
    self.preview.wantsLayer = YES;
    self.preview.layer.backgroundColor = NSColor.blackColor.CGColor;
    self.preview.video = [AVSampleBufferDisplayLayer layer];
    self.preview.video.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.preview.layer addSublayer:self.preview.video];
    self.panel.contentView = self.preview;
    self.message = [NSTextField wrappingLabelWithString:@""];
    self.message.alignment = NSTextAlignmentCenter;
    self.message.textColor = NSColor.whiteColor;
    self.choose = [NSButton buttonWithTitle:@"Start preview" target:self action:@selector(connect:)];
    self.setupHelp = [NSButton buttonWithTitle:@"Setup & Permissions…" target:self action:@selector(openSetupPermissions:)];
    for (NSView *v in @[self.message,self.choose,self.setupHelp]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self.preview addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [self.message.centerXAnchor constraintEqualToAnchor:self.preview.centerXAnchor],
        [self.message.centerYAnchor constraintEqualToAnchor:self.preview.centerYAnchor constant:-30],
        [self.message.widthAnchor constraintLessThanOrEqualToAnchor:self.preview.widthAnchor constant:-24],
        [self.choose.centerXAnchor constraintEqualToAnchor:self.preview.centerXAnchor],
        [self.choose.topAnchor constraintEqualToAnchor:self.message.bottomAnchor constant:12],
        [self.setupHelp.centerXAnchor constraintEqualToAnchor:self.preview.centerXAnchor],
        [self.setupHelp.topAnchor constraintEqualToAnchor:self.choose.bottomAnchor constant:8]]];
    self.preview.toolTip = @"Click a point to move your pointer there. Then click or type in the workspace. Move right to return.";
    NSNotificationCenter *workspaceEvents = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspaceEvents addObserver:self selector:@selector(restoreMonitorOrder:)
                            name:NSWorkspaceDidActivateApplicationNotification object:nil];
    [workspaceEvents addObserver:self selector:@selector(restoreMonitorOrder:)
                            name:NSWorkspaceActiveSpaceDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(displaysChanged:)
                                               name:NSApplicationDidChangeScreenParametersNotification object:nil];
    self.setup = [[ADSetupWindowController alloc] initWithState:self.setupState delegate:self];
    if (!self.setupState.completed || [NSProcessInfo.processInfo.arguments containsObject:@"--show-setup"]) {
        [self status:@"Finish setup to start your Agent Display preview."];
        [self.setup showSetup];
    } else if (![NSUserDefaults.standardUserDefaults boolForKey:@"WorkspaceStopped"] || WorkspaceDisplayID()) {
        [self startDesktop:nil];
        [self showPreview:nil];
    } else [self status:@"Virtual desktop is stopped."];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    if (!self.setupState.completed) { [self.setup showSetup]; return YES; }
    if (!WorkspaceDisplayID()) [self startDesktop:nil];
    [self showPreview:nil];
    return YES;
}
- (void)installMenu {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"display.2" accessibilityDescription:@"Virtual Desktop"];
    icon.template = YES;
    self.statusItem.button.image = icon;
    self.statusItem.button.accessibilityLabel = @"Virtual Desktop";
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Virtual Desktop"];
    menu.autoenablesItems = NO;
    menu.delegate = self;
    self.statusItem.menu = menu;
    NSMenu *mainMenu = [NSMenu new];
    NSMenuItem *applicationItem = [NSMenuItem new];
    NSMenu *applicationMenu = [NSMenu new];
    applicationMenu.delegate = self;
    applicationMenu.autoenablesItems = NO;
    NSMenuItem *quit = [self addItem:@"Quit Virtual Desktop" action:@selector(quit:) toMenu:applicationMenu enabled:YES];
    quit.keyEquivalent = @"q";
    applicationItem.submenu = applicationMenu;
    [mainMenu addItem:applicationItem];
    NSApp.mainMenu = mainMenu;
    [self updateMenu];
}
- (NSMenuItem *)addItem:(NSString *)title action:(SEL)action toMenu:(NSMenu *)menu enabled:(BOOL)enabled {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.enabled = enabled;
    [menu addItem:item];
    return item;
}
- (void)showControls:(NSButton *)sender {
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    [self populateMenu:menu];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, 0) inView:sender];
}
- (void)menuWillOpen:(NSMenu *)menu { [self populateMenu:menu]; }
- (void)updateMenu {
    [self populateMenu:self.statusItem.menu];
}
- (void)addApplicationMenu:(NSString *)title toWorkspace:(BOOL)toWorkspace toMenu:(NSMenu *)menu enabled:(BOOL)enabled {
    NSMenuItem *move = [self addItem:title action:NULL toMenu:menu enabled:enabled];
    NSMenu *apps = [[NSMenu alloc] initWithTitle:title];
    apps.autoenablesItems = NO;
    if (!WindowMovementAllowed()) {
        [self addItem:@"Enable Accessibility…" action:@selector(openAccessibility:) toMenu:apps enabled:YES];
    } else {
        NSArray *applications = toWorkspace ? OpenApplications() : ApplicationsOnWorkspace();
        for (NSRunningApplication *application in applications) {
            NSMenuItem *item = [self addItem:application.localizedName ?: @"App" action:@selector(moveApplication:) toMenu:apps enabled:YES];
            item.representedObject = application;
            item.tag = toWorkspace;
            NSImage *image = application.icon.copy;
            image.size = NSMakeSize(16,16);
            item.image = image;
        }
        if (!applications.count) [self addItem:toWorkspace ? @"No open apps" : @"No apps on Agent Display"
                                         action:NULL toMenu:apps enabled:NO];
    }
    move.submenu = apps;
}
- (void)populateMenu:(NSMenu *)menu {
    BOOL running = WorkspaceDisplayID() != 0;
    [menu removeAllItems];
    NSString *state = self.transitioning ? @"Virtual Desktop · Updating…" :
        (running ? @"Virtual Desktop · Running" : @"Virtual Desktop · Stopped");
    self.statusItem.button.toolTip = state;
    [self addItem:state action:NULL toMenu:menu enabled:NO];
    [menu addItem:NSMenuItem.separatorItem];
    [self addItem:self.panel.visible ? @"Hide Preview" : @"Show Preview"
           action:@selector(togglePreview:) toMenu:menu enabled:running && !self.transitioning];

    [self addApplicationMenu:@"Move App to Agent Display" toWorkspace:YES toMenu:menu enabled:running && !self.transitioning];
    [self addApplicationMenu:@"Bring App to Main Display" toWorkspace:NO toMenu:menu enabled:running && !self.transitioning];
    [menu addItem:NSMenuItem.separatorItem];
    [self addItem:running ? @"Stop Virtual Desktop" : @"Start Virtual Desktop"
           action:running ? @selector(stopDesktop:) : @selector(startDesktop:)
           toMenu:menu enabled:!self.transitioning && (!running || self.displayOwner != nil)];
    [self addItem:@"Restart Virtual Desktop" action:@selector(restartDesktop:)
           toMenu:menu enabled:running && self.displayOwner != nil && !self.transitioning];
    if (running && !self.displayOwner && !self.transitioning)
        [self addItem:@"Display is managed by another instance" action:NULL toMenu:menu enabled:NO];
    [menu addItem:NSMenuItem.separatorItem];
    [self addItem:@"Setup & Permissions…" action:@selector(openSetup:) toMenu:menu enabled:YES];
    [self addItem:@"Quit Virtual Desktop" action:@selector(quit:) toMenu:menu enabled:!self.transitioning];
    menu.itemArray.lastObject.keyEquivalent = @"q";
}
- (void)showPreview:(id)sender {
    NSScreen *screen = MainPhysicalScreen();
    if (screen && !NSIntersectsRect(self.panel.frame, screen.visibleFrame)) {
        NSRect frame = self.panel.frame;
        frame.origin = NSMakePoint(NSMaxX(screen.visibleFrame)-frame.size.width-16, NSMinY(screen.visibleFrame)+16);
        [self.panel setFrame:frame display:NO];
    }
    [self.panel orderFrontRegardless];
    if (WorkspaceDisplayID() && !self.stream && !self.connecting && CGPreflightScreenCaptureAccess()) [self connect:nil];
    [self updateMenu];
}
- (void)togglePreview:(id)sender {
    if (self.panel.visible) [self hidePreview];
    else [self showPreview:sender];
}
- (void)hidePreview {
    [self.panel orderOut:nil];
    [self status:@"Preview paused. Open it from the menu bar to resume."];
    [self stopCaptureWithCompletion:^{}];
    [self updateMenu];
}
- (BOOL)windowShouldClose:(NSWindow *)window { [self hidePreview]; return NO; }
- (void)startDesktop:(id)sender {
    if (self.transitioning) return;
    self.transitioning = YES;
    [self updateMenu];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error = nil;
        id owner = nil;
        if (!WorkspaceDisplayID()) owner = CreateWorkspaceDisplay(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (owner) self.displayOwner = owner;
            self.transitioning = NO;
            if (error || !WorkspaceDisplayID()) {
                [self status:error ?: @"macOS could not start the virtual desktop."];
                [self.panel orderFrontRegardless];
            } else {
                self.lastDisplayID = WorkspaceDisplayID();
                [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"WorkspaceStopped"];
                [self status:@"Watch the virtual display in this window."];
                [self showPreview:nil];
            }
            [self updateMenu];
        });
    });
}
- (void)stopDesktop:(id)sender { [self stopDesktopThenRestart:NO]; }
- (void)restartDesktop:(id)sender { [self stopDesktopThenRestart:YES]; }
- (void)stopDesktopThenRestart:(BOOL)restart {
    if (self.transitioning || !self.displayOwner) return;
    self.transitioning = YES;
    [self updateMenu];
    [self stopCaptureWithCompletion:^{
        self.displayOwner = nil;
        [self waitForDisconnectThenRestart:restart attempts:50];
    }];
}
- (void)waitForDisconnectThenRestart:(BOOL)restart attempts:(NSUInteger)attempts {
    if (WorkspaceDisplayID() && attempts) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [self waitForDisconnectThenRestart:restart attempts:attempts-1];
        });
        return;
    }
    if (WorkspaceDisplayID()) {
        self.transitioning = NO;
        [self status:@"The display is still connected. Another process may be keeping it alive."];
        [self.panel orderFrontRegardless];
    } else {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"WorkspaceStopped"];
        [self status:@"Virtual desktop is stopped."];
        [self.panel orderOut:nil];
        // WindowServer finishes publishing the old display's removal asynchronously.
        // Keep commands disabled until that layout change has settled.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            self.transitioning = NO;
            if (restart) [self startDesktop:nil];
            [self updateMenu];
        });
    }
    [self updateMenu];
}
- (void)stopCaptureWithCompletion:(void (^)(void))completion {
    self.captureGeneration++;
    self.connecting = NO;
    self.preview.live = NO;
    [self.setup updatePreviewLive:NO message:@"Preview paused. Start it again when you’re ready."];
    SCStream *stream = self.stream;
    self.stream = nil;
    [self.preview.video.sampleBufferRenderer flushWithRemovalOfDisplayedImage:YES completionHandler:nil];
    if (!stream) { completion(); return; }
    self.capturesStopping++;
    [stream stopCaptureWithCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.capturesStopping--;
            completion();
            if (self.panel.visible && !self.transitioning && WorkspaceDisplayID() && CGPreflightScreenCaptureAccess()) [self connect:nil];
        });
    }];
}
- (void)displaysChanged:(NSNotification *)note {
    if (self.transitioning) return;
    CGDirectDisplayID target = WorkspaceDisplayID();
    if (!target && self.lastDisplayID) {
        [self status:@"Virtual desktop is disconnected. Start it from the menu bar."];
        [self stopCaptureWithCompletion:^{}];
        // A layout change can temporarily omit a display. Keep our ownership alive
        // until an explicit Stop, Restart, or Quit operation releases it.
    } else if (target && self.panel.visible && !self.stream && !self.connecting && CGPreflightScreenCaptureAccess()) [self connect:nil];
    self.lastDisplayID = target;
    [self updateMenu];
}
- (void)openAccessibility:(id)sender {
    [self openSetupPermissions:sender];
}
- (void)openSetup:(id)sender { [self.setup showSetup]; }
- (void)openSetupPermissions:(id)sender { [self.setup showPermissions]; }
- (void)setupStartPreview {
    if (!WorkspaceDisplayID()) [self startDesktop:nil];
    else if (!self.preview.live && (self.stream || self.connecting)) {
        [self stopCaptureWithCompletion:^{ [self showPreview:nil]; }];
    } else [self showPreview:nil];
}
- (NSString *)setupMoveApplication:(NSRunningApplication *)application {
    return MoveApplicationToWorkspace(application);
}
- (void)setupDidFinish { [self showPreview:nil]; }
- (void)moveApplication:(NSMenuItem *)item {
    if (!WindowMovementAllowed()) { [self openAccessibility:nil]; return; }
    BOOL toWorkspace = item.tag != 0;
    NSString *error = toWorkspace ? MoveApplicationToWorkspace(item.representedObject) : MoveApplicationToMainDisplay(item.representedObject);
    if (error) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = toWorkspace ? @"Move to Agent Display" : @"Move to main display";
        alert.informativeText = error;
        [NSApp activateIgnoringOtherApps:YES];
        [alert runModal];
    } else if (toWorkspace) [self showPreview:nil];
}
- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (void)applicationWillTerminate:(NSNotification *)note {
    self.captureGeneration++;
    [self.stream stopCaptureWithCompletionHandler:nil];
    self.stream = nil;
    self.displayOwner = nil;
}
- (void)restoreMonitorOrder:(NSNotification *)notification {
    // Reorder the panel without making the viewer the active app.
    if (self.panel.visible && !self.panel.miniaturized) [self.panel orderFrontRegardless];
}
- (void)status:(NSString *)message {
    self.preview.live = NO; self.message.hidden = NO;
    self.setupHelp.hidden = NO;
    self.choose.hidden = NO;
    self.choose.title = WorkspaceDisplayID() ? @"Start preview" : @"Start desktop";
    self.choose.enabled = !self.connecting && !self.transitioning;
    self.panel.title = @"Agent Display";
    self.panel.subtitle = @"";
    self.message.stringValue = message;
    [self.setup updatePreviewLive:NO message:message];
}
- (void)connect:(id)sender {
    if (self.connecting || self.stream || self.transitioning || self.capturesStopping) return;
    CGDirectDisplayID target = WorkspaceDisplayID();
    if (!target) { [self startDesktop:nil]; return; }
    self.connecting = YES;
    NSUInteger generation = ++self.captureGeneration;
    self.choose.enabled = NO;
    self.message.stringValue = @"Connecting to Agent Display…";
    [self.setup updatePreviewConnecting];
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *content, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.captureGeneration) return;
            self.connecting = NO;
            self.choose.enabled = YES;
            if (target != WorkspaceDisplayID()) { [self status:@"The virtual desktop disconnected. Start it from the menu bar."]; return; }
            if (error) {
                NSString *reason = error.code == SCStreamErrorUserDeclined ?
                    @"macOS declined the capture request. If this viewer already has screen access, quit and reopen it. First-time setup is in Privacy & Security → Screen & System Audio Recording." :
                    error.localizedDescription;
                [self status:reason]; return;
            }
            for (SCDisplay *display in content.displays) {
                if (display.displayID != target) continue;
                SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
                [self start:filter]; return;
            }
            [self status:@"The virtual display disconnected. Reconnect it and retry."];
        });
    }];
}
- (void)start:(SCContentFilter *)filter {
    CGDirectDisplayID target = WorkspaceDisplayID();
    if (!target || filter.includedDisplays.count != 1 || filter.includedDisplays.firstObject.displayID != target) {
        [self status:@"The virtual display is unavailable. Reconnect it and retry."]; return;
    }
    SCStreamConfiguration *config = [SCStreamConfiguration new];
    // Capture the display's actual pixels, including its Retina backing scale.
    config.width = (size_t)ceil(filter.contentRect.size.width * filter.pointPixelScale);
    config.height = (size_t)ceil(filter.contentRect.size.height * filter.pointPixelScale);
    if (!config.width || !config.height) {
        [self status:@"The display resolution is unavailable. Retry the preview."]; return;
    }
    config.captureResolution = SCCaptureResolutionBest;
    config.pixelFormat = kCVPixelFormatType_32BGRA;
    config.queueDepth = 3;
    config.showsCursor = YES; config.capturesAudio = NO;
    config.minimumFrameInterval = CMTimeMake(1,24);
    SCStream *stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
    NSError *error = nil;
    if (![stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:dispatch_get_main_queue() error:&error]) {
        [self status:error.localizedDescription]; return;
    }
    self.stream = stream;
    [stream startCaptureWithCompletionHandler:^(NSError *err) {
        if (err) dispatch_async(dispatch_get_main_queue(), ^{ if (self.stream==stream) { self.stream=nil; [self status:err.localizedDescription]; }});
    }];
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    if (stream != self.stream || !CMSampleBufferGetImageBuffer(sample)) return;
    NSArray *info = (__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample, NO);
    NSNumber *status = [info.firstObject objectForKey:SCStreamFrameInfoStatus];
    if (!status || status.integerValue != SCFrameStatusComplete) return;
    NSMutableDictionary *attachment = [info firstObject];
    attachment[(__bridge NSString *)kCMSampleAttachmentKey_DisplayImmediately] = @YES;
    AVSampleBufferVideoRenderer *renderer = self.preview.video.sampleBufferRenderer;
    if (renderer.requiresFlushToResumeDecoding) [renderer flush];
    if (!renderer.readyForMoreMediaData) return;
    [renderer enqueueSampleBuffer:sample];
    if (!self.preview.live) {
        self.preview.live=YES; self.message.hidden=YES; self.choose.hidden=YES;
        self.setupHelp.hidden=YES;
        self.panel.title=@"Agent Display · Live";
        CVImageBufferRef image = CMSampleBufferGetImageBuffer(sample);
        self.panel.subtitle = [NSString stringWithFormat:@"%zu × %zu", CVPixelBufferGetWidth(image), CVPixelBufferGetHeight(image)];
        [self.setup updatePreviewLive:YES message:[@"✓ Preview is live · " stringByAppendingString:self.panel.subtitle]];
    }
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.stream==stream) {
        self.stream=nil; self.panel.title=@"Agent Display"; [self status:error.localizedDescription];
    }});
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {return NO;}
@end
int main(void) {
    @autoreleasepool {
        NSApplication *app=NSApplication.sharedApplication;
        __attribute__((objc_precise_lifetime)) Viewer *viewer=[Viewer new];
        app.delegate=viewer; [app run];
    }
}
