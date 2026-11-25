#import "SetupWindowController.h"
#import "WindowMover.h"
#import <QuartzCore/QuartzCore.h>

@interface ADSetupWindowController () <NSWindowDelegate, NSMenuDelegate>
@property(strong) ADSetupState *state;
@property(weak) id<ADSetupDelegate> setupDelegate;
@property(strong) NSStackView *body;
@property(strong) NSTextField *stepLabel;
@property(strong) NSTextField *heading;
@property(strong) NSTextField *subtitle;
@property(strong) NSTextField *screenStatus;
@property(strong) NSTextField *accessibilityStatus;
@property(strong) NSTextField *previewStatus;
@property(strong) NSTextField *moveStatus;
@property(strong) NSButton *screenButton;
@property(strong) NSButton *accessibilityButton;
@property(strong) NSButton *primary;
@property(strong) NSButton *back;
@property(strong) NSButton *retry;
@property(strong) NSPopUpButton *apps;
@property(strong) NSTimer *permissionTimer;
@property(strong) NSTimer *previewTimer;
@property(copy) NSString *previewMessage;
@property BOOL previewLive;
@property BOOL previewRequested;
@end

@implementation ADSetupWindowController
- (instancetype)initWithState:(ADSetupState *)state delegate:(id<ADSetupDelegate>)delegate {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 650)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        _state = state;
        _setupDelegate = delegate;
        window.title = @"Welcome to Agent Display";
        window.releasedWhenClosed = NO;
        window.delegate = self;
        window.level = NSFloatingWindowLevel;
        [self buildWindow];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshPermissions)
            name:NSApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}
- (void)dealloc {
    [_permissionTimer invalidate];
    [_previewTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (NSTextField *)label:(NSString *)text size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:bold ? NSFontWeightSemibold : NSFontWeightRegular];
    label.textColor = bold ? NSColor.labelColor : NSColor.secondaryLabelColor;
    [label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    return label;
}
- (NSStackView *)stack:(NSArray<NSView *> *)views vertical:(BOOL)vertical spacing:(CGFloat)spacing {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = vertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}
- (void)buildWindow {
    NSView *content = self.window.contentView;
    NSImageView *icon = [NSImageView imageViewWithImage:NSApp.applicationIconImage];
    [icon.widthAnchor constraintEqualToConstant:64].active = YES;
    [icon.heightAnchor constraintEqualToConstant:64].active = YES;
    self.stepLabel = [self label:@"" size:11 bold:YES];
    self.stepLabel.textColor = NSColor.secondaryLabelColor;
    NSTextField *brand = [self label:@"Agent Display" size:19 bold:YES];
    NSStackView *brandText = [self stack:@[brand, self.stepLabel] vertical:YES spacing:5];
    NSStackView *header = [self stack:@[icon, brandText] vertical:NO spacing:14];
    self.heading = [self label:@"" size:28 bold:YES];
    self.subtitle = [self label:@"" size:14 bold:NO];
    self.body = [self stack:@[] vertical:YES spacing:14];
    NSStackView *top = [self stack:@[header, self.heading, self.subtitle, self.body] vertical:YES spacing:18];
    [content addSubview:top];
    self.back = [NSButton buttonWithTitle:@"Back" target:self action:@selector(goBack:)];
    NSButton *later = [NSButton buttonWithTitle:@"Set Up Later" target:self action:@selector(deferSetup:)];
    self.primary = [NSButton buttonWithTitle:@"Get Started" target:self action:@selector(continueSetup:)];
    self.primary.keyEquivalent = @"\r";
    NSView *spacer = [NSView new];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *footer = [self stack:@[self.back, later, spacer, self.primary] vertical:NO spacing:10];
    [content addSubview:footer];
    [NSLayoutConstraint activateConstraints:@[
        [top.topAnchor constraintEqualToAnchor:content.topAnchor constant:28],
        [top.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:32],
        [top.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-32],
        [self.heading.widthAnchor constraintEqualToAnchor:top.widthAnchor],
        [self.subtitle.widthAnchor constraintEqualToAnchor:top.widthAnchor],
        [self.body.widthAnchor constraintEqualToAnchor:top.widthAnchor],
        [top.bottomAnchor constraintLessThanOrEqualToAnchor:footer.topAnchor constant:-24],
        [footer.leadingAnchor constraintEqualToAnchor:top.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:top.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24]
    ]];
}
- (void)addBodyView:(NSView *)view {
    [self.body addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:self.body.widthAnchor].active = YES;
}
- (void)addCardWithSymbol:(NSString *)symbol title:(NSString *)title detail:(NSString *)detail
                  status:(NSTextField *)status button:(NSButton *)button {
    NSImageView *image = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]];
    image.contentTintColor = NSColor.controlAccentColor;
    [image.widthAnchor constraintEqualToConstant:26].active = YES;
    [image.heightAnchor constraintEqualToConstant:26].active = YES;
    NSTextField *text = [self label:detail size:13 bold:NO];
    NSMutableArray *labels = [NSMutableArray arrayWithArray:@[[self label:title size:14 bold:YES], text]];
    if (status) [labels addObject:status];
    NSStackView *copy = [self stack:labels vertical:YES spacing:5];
    [text.widthAnchor constraintEqualToAnchor:copy.widthAnchor].active = YES;
    if (status) [status.widthAnchor constraintEqualToAnchor:copy.widthAnchor].active = YES;
    NSMutableArray *items = [NSMutableArray arrayWithArray:@[image, copy]];
    if (button) {
        [button setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [items addObject:button];
    }
    NSStackView *row = [self stack:items vertical:NO spacing:14];
    NSBox *card = [NSBox new];
    card.boxType = NSBoxCustom;
    card.borderWidth = 1;
    card.borderColor = NSColor.separatorColor;
    card.fillColor = NSColor.controlBackgroundColor;
    card.cornerRadius = 12;
    card.contentViewMargins = NSZeroSize;
    [card.contentView addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-16],
        [row.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:14],
        [row.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor constant:-14]
    ]];
    [self addBodyView:card];
}
- (void)renderStep {
    for (NSView *view in self.body.arrangedSubviews.copy) {
        [self.body removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    self.screenStatus = nil; self.accessibilityStatus = nil; self.previewStatus = nil;
    self.screenButton = nil; self.accessibilityButton = nil; self.apps = nil; self.retry = nil;
    self.moveStatus = nil;
    ADSetupStep step = self.state.step;
    self.stepLabel.stringValue = [NSString stringWithFormat:@"STEP %ld OF 3", (long)step + 1];
    self.back.hidden = step == ADSetupWelcome;
    if (step == ADSetupWelcome) {
        self.heading.stringValue = @"A little space for your agent.";
        self.subtitle.stringValue = @"Give apps a second screen, and keep an eye on them from your desktop.";
        [self addCardWithSymbol:@"display.2" title:@"Make room to work"
            detail:@"A Retina display appears to the left of your screens. Your main screen stays primary." status:nil button:nil];
        [self addCardWithSymbol:@"rectangle.on.rectangle" title:@"Keep the work in view"
            detail:@"Watch a floating live preview. Resize it, or hide it while apps keep running." status:nil button:nil];
        [self addCardWithSymbol:@"arrow.left.arrow.right" title:@"Move apps in and out"
            detail:@"Use the two-display icon in your menu bar to send an app over or bring it back." status:nil button:nil];
        [self addBodyView:[self label:@"Both screens share your mouse and keyboard. This is an extra workspace on your Mac, not a separate computer." size:12 bold:NO]];
    } else if (step == ADSetupPermissions) {
        self.heading.stringValue = @"Two permissions. You’re in control.";
        self.subtitle.stringValue = @"macOS lists this app as Virtual Desktop. Enable it in the settings below.";
        self.screenStatus = [self label:@"" size:12 bold:YES];
        self.screenButton = [NSButton buttonWithTitle:@"Allow Preview" target:self action:@selector(requestScreen:)];
        [self addCardWithSymbol:@"rectangle.inset.filled.on.rectangle" title:@"Screen Recording · Required"
            detail:@"Shows only Agent Display; macOS grants screen access app-wide. No audio capture or saved recordings."
            status:self.screenStatus button:self.screenButton];
        self.accessibilityStatus = [self label:@"" size:12 bold:YES];
        self.accessibilityButton = [NSButton buttonWithTitle:@"Allow Movement" target:self action:@selector(requestAccessibility:)];
        [self addCardWithSymbol:@"arrow.up.left.and.arrow.down.right" title:@"Accessibility · Optional"
            detail:@"Lets the menu move other apps’ windows. You can enable this later."
            status:self.accessibilityStatus button:self.accessibilityButton];
        [self addBodyView:[self label:@"Under Privacy & Security, turn on Virtual Desktop. If macOS asks to quit and reopen, accept: setup will resume here." size:12 bold:NO]];
        [self addBodyView:[self label:@"Already enabled but still waiting? Quit Agent Display from its menu bar and reopen the same app. We recheck permissions while this window is open." size:12 bold:NO]];
    } else {
        self.heading.stringValue = @"Your new workspace is one click away.";
        self.subtitle.stringValue = @"Start the preview, then try moving an open app when you’re ready.";
        self.previewStatus = [self label:@"" size:13 bold:YES];
        self.previewStatus.maximumNumberOfLines = 3;
        self.retry = [NSButton buttonWithTitle:@"Start Preview" target:self action:@selector(startPreview:)];
        [self addCardWithSymbol:@"display" title:@"Agent Display"
            detail:@"The floating preview shows what’s on your second screen."
            status:self.previewStatus button:self.retry];
        self.apps = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        self.apps.target = self;
        self.apps.action = @selector(moveFirstApp:);
        self.apps.menu.delegate = self;
        [self populateApps];
        [self addBodyView:self.apps];
        self.moveStatus = [self label:@"" size:12 bold:NO];
        [self addBodyView:self.moveStatus];
        [self addCardWithSymbol:@"menubar.rectangle" title:@"Find us in the menu bar"
            detail:@"Look for the two-display icon. Bring App to Main Display brings your windows back. Closing the preview only hides it."
            status:nil button:nil];
        [self addBodyView:[self label:@"Clicking the preview moves your real pointer to Agent Display. Move right to return. Use Stop Virtual Desktop when you’re done." size:12 bold:NO]];
    }
    [self refreshPermissions];
    [self.window makeFirstResponder:self.primary];
}
- (void)showSetup {
    [self renderStep];
    NSScreen *screen = MainPhysicalScreen() ?: NSScreen.mainScreen;
    if (screen) {
        NSRect frame = self.window.frame;
        frame.origin = NSMakePoint(NSMidX(screen.visibleFrame) - frame.size.width / 2,
                                  NSMidY(screen.visibleFrame) - frame.size.height / 2);
        [self.window setFrame:frame display:NO];
    }
    [self showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.permissionTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.permissionTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshPermissions];
    }];
}
- (void)showPermissions {
    self.state.step = ADSetupPermissions;
    [self showSetup];
}
- (void)refreshPermissions {
    BOOL screen = CGPreflightScreenCaptureAccess();
    BOOL movement = WindowMovementAllowed();
    self.screenStatus.stringValue = screen ? @"✓ Allowed" : @"Waiting for screen access";
    self.screenStatus.textColor = screen ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;
    self.screenButton.title = screen ? @"Allowed" :
        ([NSUserDefaults.standardUserDefaults boolForKey:@"AgentDisplayRequestedScreenAccess"] ? @"Open Settings" : @"Allow Preview");
    self.screenButton.enabled = !screen;
    self.accessibilityStatus.stringValue = movement ? @"✓ Allowed" : @"You can skip this for now";
    self.accessibilityStatus.textColor = movement ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;
    self.accessibilityButton.title = movement ? @"Allowed" : @"Allow Movement";
    self.accessibilityButton.enabled = !movement;
    self.primary.title = self.state.step == ADSetupWelcome ? @"Get Started" :
        (self.state.step == ADSetupPermissions ? @"Continue" : @"Finish Setup");
    self.primary.enabled = self.state.step == ADSetupWelcome ||
        (self.state.step == ADSetupPermissions ? screen : self.previewLive);
    self.previewStatus.stringValue = self.previewLive ? self.previewMessage :
        (self.previewMessage.length ? self.previewMessage : @"Ready when you are.");
    self.previewStatus.textColor = self.previewLive ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;
    self.previewStatus.toolTip = self.previewMessage;
    self.retry.hidden = self.previewLive;
    self.retry.enabled = !self.previewRequested;
    self.retry.title = self.previewRequested ? @"Connecting…" : @"Start Preview";
    self.apps.enabled = movement && self.previewLive;
    if (!movement) self.moveStatus.stringValue = @"Enable Accessibility using Back to try moving an app. You can also finish setup and enable it later.";
    else if (!self.moveStatus.stringValue.length || [self.moveStatus.stringValue hasPrefix:@"Enable Accessibility"])
        self.moveStatus.stringValue = @"Optional: choose an app to move its windows to Agent Display. You can bring them back from the menu bar.";
}
- (void)requestScreen:(id)sender {
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"AgentDisplayRequestedScreenAccess"]) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"AgentDisplayRequestedScreenAccess"];
        CGRequestScreenCaptureAccess();
    }
    [self refreshPermissions];
    if (!CGPreflightScreenCaptureAccess())
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"]];
}
- (void)requestAccessibility:(id)sender {
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES});
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
    [self refreshPermissions];
}
- (void)continueSetup:(id)sender {
    if (self.state.step == ADSetupWelcome) self.state.step = ADSetupPermissions;
    else if (self.state.step == ADSetupPermissions) {
        if (!CGPreflightScreenCaptureAccess()) { [self refreshPermissions]; return; }
        self.state.step = ADSetupWorkspace;
    } else {
        if (![self.state completeWithLivePreview:self.previewLive]) return;
        [self close];
        [self.setupDelegate setupDidFinish];
        return;
    }
    [self renderStep];
}
- (void)goBack:(id)sender {
    if (self.state.step > ADSetupWelcome) self.state.step--;
    [self renderStep];
}
- (void)deferSetup:(id)sender { [self close]; }
- (void)windowWillClose:(NSNotification *)notification {
    [self.permissionTimer invalidate];
    self.permissionTimer = nil;
}
- (void)startPreview:(id)sender {
    if (!CGPreflightScreenCaptureAccess()) { [self showPermissions]; return; }
    [self updatePreviewConnecting];
    [self.setupDelegate setupStartPreview];
}
- (void)updatePreviewConnecting {
    self.previewLive = NO;
    self.previewRequested = YES;
    self.previewMessage = @"Connecting to Agent Display…";
    [self.previewTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.previewTimer = [NSTimer scheduledTimerWithTimeInterval:20 repeats:NO block:^(NSTimer *timer) {
        if (!weakSelf.previewLive) {
            [weakSelf updatePreviewLive:NO message:@"No preview arrived yet. Retry, or use Back to check screen access. If you just enabled it, quit and reopen the app."];
        }
    }];
    [self refreshPermissions];
}
- (void)updatePreviewLive:(BOOL)live message:(NSString *)message {
    [self.previewTimer invalidate];
    self.previewTimer = nil;
    self.previewLive = live;
    self.previewMessage = message;
    self.previewRequested = NO;
    [self refreshPermissions];
}
- (void)populateApps {
    [self.apps removeAllItems];
    [self.apps addItemWithTitle:@"Move an open app to Agent Display…"];
    self.apps.lastItem.enabled = NO;
    for (NSRunningApplication *app in OpenApplications()) {
        [self.apps addItemWithTitle:app.localizedName ?: @"App"];
        NSMenuItem *item = self.apps.lastItem;
        item.representedObject = app;
        NSImage *icon = app.icon.copy;
        icon.size = NSMakeSize(16, 16);
        item.image = icon;
    }
    [self.apps selectItemAtIndex:0];
}
- (void)menuWillOpen:(NSMenu *)menu { [self populateApps]; }
- (void)moveFirstApp:(id)sender {
    NSRunningApplication *app = self.apps.selectedItem.representedObject;
    if (!app || !self.previewLive) return;
    NSString *error = [self.setupDelegate setupMoveApplication:app];
    self.moveStatus.stringValue = error ?: [NSString stringWithFormat:@"%@ is on Agent Display. Look for it in the live preview.", app.localizedName ?: @"The app"];
    [self.apps selectItemAtIndex:0];
}
@end
