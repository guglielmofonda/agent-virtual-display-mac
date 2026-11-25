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
        if (CGDisplayVendorNumber(ids[i]) == 17240 &&
            (CGDisplaySerialNumber(ids[i]) == 914225 || CGDisplaySerialNumber(ids[i]) == 914226))
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
    [desc setValue:@"Agent Display" forKey:@"name"];
    [desc setValue:@3840 forKey:@"maxPixelsWide"];
    [desc setValue:@2160 forKey:@"maxPixelsHigh"];
    [desc setValue:@17240 forKey:@"vendorID"];
    [desc setValue:@1314 forKey:@"productID"];
    [desc setValue:@914226 forKey:@"serialNum"];
    [desc setValue:@914226 forKey:@"serialNumber"];
    [desc setQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)];
    [desc setSizeInMillimeters:CGSizeMake(480,270)];
    id display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:desc];
    if (!display) { *error = @"macOS could not create the virtual display."; return nil; }
    id mode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:1920 height:1080 refreshRate:60];
    id settings = [NSClassFromString(@"CGVirtualDisplaySettings") new];
    // Keep a 1920 × 1080-point desktop, rendered at 2× for sharp Retina text.
    [settings setValue:@YES forKey:@"hiDPI"];
    [settings setValue:@[mode] forKey:@"modes"];
    if (![display applySettings:settings]) { *error = @"macOS could not set the virtual display mode."; return nil; }

    CGDirectDisplayID target = [display displayID];
    for (unsigned attempt = 0; attempt < 100 && CGDisplayIsOnline(target) != 1; attempt++)
        [NSThread sleepForTimeInterval:0.1];
    if (CGDisplayIsOnline(target) != 1) {
        *error = [NSString stringWithFormat:@"macOS created display %u but did not connect it.", target]; return nil;
    }
    CGDisplayConfigRef config = NULL;
    CGError result = CGBeginDisplayConfiguration(&config);
    if (result == kCGErrorSuccess) {
        // Prefer the Retina mode even if macOS remembers this display at 1×.
        CFArrayRef modes = CGDisplayCopyAllDisplayModes(target, NULL);
        for (CFIndex i = 0; modes && i < CFArrayGetCount(modes); i++) {
            CGDisplayModeRef candidate = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
            if (CGDisplayModeGetWidth(candidate) == 1920 && CGDisplayModeGetHeight(candidate) == 1080 &&
                CGDisplayModeGetPixelWidth(candidate) == 3840 && CGDisplayModeGetPixelHeight(candidate) == 2160) {
                result = CGConfigureDisplayWithDisplayMode(config, target, candidate, NULL);
                break;
            }
        }
        if (modes) CFRelease(modes);
        if (result == kCGErrorSuccess)
            result = CGConfigureDisplayOrigin(config, target, CGRectGetMinX(left) - 1920, CGRectGetMinY(left));
        if (result == kCGErrorSuccess) result = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
        else CGCancelDisplayConfiguration(config);
    }
    if (result != kCGErrorSuccess) {
        *error = [NSString stringWithFormat:@"Could not position the virtual display (macOS error %d).", result]; return nil;
    }
    for (unsigned attempt = 0; attempt < 50; attempt++) {
        if (WorkspaceDisplayID() == target && CGMainDisplayID() == main && CGDisplayIsActive(target) == 1 && CGDisplayIsInMirrorSet(target) == 0) return display;
        [NSThread sleepForTimeInterval:0.1];
    }
    *error = [NSString stringWithFormat:@"macOS could not enable the extended display (online %d, active %d, mirrored %d).", CGDisplayIsOnline(target), CGDisplayIsActive(target), CGDisplayIsInMirrorSet(target)];
    return nil;
}
