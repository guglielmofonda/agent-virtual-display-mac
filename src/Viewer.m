#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <AVFoundation/AVFoundation.h>

#import "Display.h"

@interface PreviewView : NSView
@property (strong) AVSampleBufferDisplayLayer *video;
@property BOOL live;
@end
@implementation PreviewView
- (void)layout { [super layout]; self.video.frame = self.bounds; }
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

@interface Viewer : NSObject <NSApplicationDelegate, SCStreamDelegate, SCStreamOutput>
@property (strong) id displayOwner;
@property (strong) NSPanel *panel;
@property (strong) PreviewView *preview;
@property (strong) NSTextField *message;
@property (strong) NSButton *choose;
@property (strong) SCStream *stream;
@end
@implementation Viewer
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    NSString *displayError = nil;
    if (!WorkspaceDisplayID()) self.displayOwner = CreateWorkspaceDisplay(&displayError);
    NSScreen *builtin = nil;
    for (NSScreen *screen in NSScreen.screens)
        if (CGDisplayIsBuiltin([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue])) builtin = screen;
    NSRect usable = (builtin ?: NSScreen.mainScreen).visibleFrame;
    CGFloat width = MIN(480, usable.size.width * 0.4);
    NSRect frame = NSMakeRect(NSMaxX(usable)-width-16, NSMinY(usable)+16, width, width*9/16);
    self.panel = [[NSPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.panel.title = @"Codex Workspace";
    self.panel.level = NSFloatingWindowLevel;
    self.panel.hidesOnDeactivate = NO;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;
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
    for (NSView *v in @[self.message,self.choose]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self.preview addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [self.message.centerXAnchor constraintEqualToAnchor:self.preview.centerXAnchor],
        [self.message.centerYAnchor constraintEqualToAnchor:self.preview.centerYAnchor constant:-17],
        [self.message.widthAnchor constraintLessThanOrEqualToAnchor:self.preview.widthAnchor constant:-24],
        [self.choose.centerXAnchor constraintEqualToAnchor:self.preview.centerXAnchor],
        [self.choose.topAnchor constraintEqualToAnchor:self.message.bottomAnchor constant:12]]];
    self.preview.toolTip = @"Click a point to move your pointer there. Then click or type in the workspace. Move right to return.";
    [self.panel orderFrontRegardless];
    [self status:@"Watch the virtual display in this window."];
    if (displayError) [self status:displayError];
    else if (CGPreflightScreenCaptureAccess()) [self connect:nil];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    [self.panel orderFrontRegardless];
    return YES;
}
- (void)status:(NSString *)message {
    self.preview.live = NO; self.message.hidden = NO; self.choose.hidden = NO;
    self.message.stringValue = message;
}
- (void)connect:(id)sender {
    CGDirectDisplayID target = WorkspaceDisplayID();
    if (!target) { [self status:@"Codex Workspace is disconnected. Close this window and reopen the app."]; return; }
    self.choose.enabled = NO;
    self.message.stringValue = @"Connecting to Codex Workspace…";
    [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *content, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.choose.enabled = YES;
            if (error) {
                NSString *reason = error.code == SCStreamErrorUserDeclined ?
                    @"Screen access is off. Allow Mac Agent Display in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen it." :
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
    config.width = 1280; config.height = 720;
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
        self.panel.title=@"Codex Workspace · Live";
    }
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.stream==stream) {
        self.stream=nil; self.panel.title=@"Codex Workspace"; [self status:error.localizedDescription];
    }});
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {return YES;}
@end
int main(void) {
    @autoreleasepool {
        NSApplication *app=NSApplication.sharedApplication;
        __attribute__((objc_precise_lifetime)) Viewer *viewer=[Viewer new];
        app.delegate=viewer; [app run];
    }
}
