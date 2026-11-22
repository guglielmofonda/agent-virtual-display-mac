#import "Display.h"

@interface NSObject (Display)
- (id)initWithDescriptor:(id)desc;
- (id)initWithWidth:(unsigned)width height:(unsigned)height refreshRate:(double)rate;
- (BOOL)applySettings:(id)settings;
- (unsigned)displayID;
- (void)setSizeInMillimeters:(CGSize)size;
- (void)setQueue:(dispatch_queue_t)queue;
@end

CGDirectDisplayID WorkspaceDisplayID(void) {
    CGDirectDisplayID ids[32];
    uint32_t count = 0;
    if (CGGetActiveDisplayList(32, ids, &count) != kCGErrorSuccess) return 0;
    for (unsigned i = 0; i < count; i++) {
        if (CGDisplayVendorNumber(ids[i]) == 17240 && CGDisplaySerialNumber(ids[i]) == 914225)
            return ids[i];
    }
    return 0;
}

id CreateWorkspaceDisplay(NSString **error) {
    CGDirectDisplayID main = CGMainDisplayID();
    if (!main) { *error = @"Open the app from Finder in your signed-in Mac desktop."; return nil; }
    CGDirectDisplayID screens[32];
    uint32_t count = 0;
    if (CGGetActiveDisplayList(32, screens, &count) != kCGErrorSuccess || !count) {
        *error = @"Could not read the current screen layout."; return nil;
    }
    CGRect left = CGDisplayBounds(main);
    for (unsigned i = 0; i < count; i++) {
        CGRect bounds = CGDisplayBounds(screens[i]);
        if (CGRectGetMinX(bounds) < CGRectGetMinX(left)) left = bounds;
    }
    if (!NSClassFromString(@"CGVirtualDisplayDescriptor") || !NSClassFromString(@"CGVirtualDisplay")) {
        *error = @"This macOS version lacks virtual display support."; return nil;
    }
    id desc = [NSClassFromString(@"CGVirtualDisplayDescriptor") new];
    [desc setValue:@"Codex Workspace" forKey:@"name"];
    [desc setValue:@1920 forKey:@"maxPixelsWide"];
    [desc setValue:@1080 forKey:@"maxPixelsHigh"];
    [desc setValue:@17240 forKey:@"vendorID"];
    [desc setValue:@1314 forKey:@"productID"];
    [desc setValue:@914225 forKey:@"serialNum"];
    [desc setValue:@914225 forKey:@"serialNumber"];
    [desc setQueue:dispatch_get_main_queue()];
    [desc setSizeInMillimeters:CGSizeMake(480,270)];
    id display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:desc];
    if (!display) { *error = @"macOS could not create the virtual display."; return nil; }
    id mode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:1920 height:1080 refreshRate:60];
    id settings = [NSClassFromString(@"CGVirtualDisplaySettings") new];
    [settings setValue:@[mode] forKey:@"modes"];
    if (![display applySettings:settings]) { *error = @"macOS could not set the virtual display mode."; return nil; }

    CGDirectDisplayID target = [display displayID];
    for (unsigned attempt = 0; attempt < 50 && !CGDisplayIsActive(target); attempt++)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
    if (WorkspaceDisplayID() != target || CGMainDisplayID() != main || CGDisplayIsInMirrorSet(target)) {
        *error = @"macOS could not enable a separate secondary screen."; return nil;
    }
    CGRect screen = CGDisplayBounds(target);
    CGDisplayConfigRef config = NULL;
    CGError result = CGBeginDisplayConfiguration(&config);
    if (result == kCGErrorSuccess) {
        result = CGConfigureDisplayOrigin(config, target, CGRectGetMinX(left) - screen.size.width, CGRectGetMinY(left));
        if (result == kCGErrorSuccess) result = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
        else CGCancelDisplayConfiguration(config);
    }
    if (result != kCGErrorSuccess) {
        *error = @"Could not place the virtual display to the left."; return nil;
    }
    return display;
}
