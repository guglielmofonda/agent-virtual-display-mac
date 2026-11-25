#import "WindowMover.h"
#import "Display.h"
#import <ApplicationServices/ApplicationServices.h>

NSScreen *MainPhysicalScreen(void) {
    CGDirectDisplayID workspace = WorkspaceDisplayID();
    NSScreen *fallback = nil;
    for (NSScreen *screen in NSScreen.screens) {
        CGDirectDisplayID display = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        if (display == workspace) continue;
        if (display == CGMainDisplayID()) return screen;
        if (!fallback || CGDisplayIsBuiltin(display)) fallback = screen;
    }
    return fallback;
}

static BOOL WindowIsOnDisplay(CGRect window, CGDirectDisplayID display) {
    if (!display || CGRectIsEmpty(window)) return NO;
    CGPoint center = CGPointMake(CGRectGetMidX(window), CGRectGetMidY(window));
    return CGRectContainsPoint(CGDisplayBounds(display), center);
}

static BOOL WindowMatchesSource(CGRect window, CGDirectDisplayID workspace, BOOL toWorkspace) {
    if (!toWorkspace) return WindowIsOnDisplay(window, workspace);
    if (WindowIsOnDisplay(window, workspace)) return NO;
    for (NSScreen *screen in NSScreen.screens) {
        CGDirectDisplayID display = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        if (display != workspace && WindowIsOnDisplay(window, display)) return YES;
    }
    return NO;
}

static NSArray<NSRunningApplication *> *UserApplications(NSArray<NSRunningApplication *> *runningApplications, pid_t ownPID) {
    NSMutableArray<NSRunningApplication *> *apps = [NSMutableArray array];
    for (NSRunningApplication *app in runningApplications) {
        if (!app.terminated && app.processIdentifier != ownPID &&
            app.activationPolicy == NSApplicationActivationPolicyRegular) {
            [apps addObject:app];
        }
    }
    return [apps sortedArrayUsingComparator:^NSComparisonResult(NSRunningApplication *a, NSRunningApplication *b) {
        return [(a.localizedName ?: @"App") localizedCaseInsensitiveCompare:(b.localizedName ?: @"App")];
    }];
}

NSArray<NSRunningApplication *> *OpenApplications(void) {
    // Running applications are the source of truth, including hidden apps,
    // minimized apps, and open apps that currently have no windows.
    return UserApplications(NSWorkspace.sharedWorkspace.runningApplications,
                            NSProcessInfo.processInfo.processIdentifier);
}

static NSSet<NSNumber *> *VisibleWindowOwners(NSArray<NSDictionary *> *windows, CGRect displayBounds) {
    NSMutableSet *pids = [NSMutableSet set];
    if (CGRectIsEmpty(displayBounds)) return pids;
    for (NSDictionary *window in windows) {
        if (![window[(__bridge NSString *)kCGWindowIsOnscreen] boolValue]) continue;
        if ([window[(__bridge NSString *)kCGWindowLayer] intValue] != 0) continue;
        if ([window[(__bridge NSString *)kCGWindowAlpha] doubleValue] <= 0) continue;
        NSDictionary *description = window[(__bridge NSString *)kCGWindowBounds];
        CGRect bounds;
        if (![description isKindOfClass:NSDictionary.class] ||
            !CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)description, &bounds) ||
            CGRectIsEmpty(bounds)) continue;
        CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
        NSNumber *pid = window[(__bridge NSString *)kCGWindowOwnerPID];
        if (pid && CGRectContainsPoint(displayBounds, center)) [pids addObject:pid];
    }
    return pids;
}

NSArray<NSRunningApplication *> *ApplicationsOnWorkspace(void) {
    CGDirectDisplayID workspace = WorkspaceDisplayID();
    if (!workspace) return @[];
    // All-window snapshots include minimized windows and other Spaces. Only
    // currently displayed app windows belong in the return-to-main menu.
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    NSSet<NSNumber *> *pids = VisibleWindowOwners(windows, CGDisplayBounds(workspace));
    NSMutableArray<NSRunningApplication *> *apps = [NSMutableArray array];
    for (NSRunningApplication *app in OpenApplications()) {
        if ([pids containsObject:@(app.processIdentifier)]) [apps addObject:app];
    }
    return apps;
}

BOOL WindowMovementAllowed(void) {
    return AXIsProcessTrusted();
}

static id Attribute(AXUIElementRef element, CFStringRef name) {
    CFTypeRef value = NULL;
    AXUIElementCopyAttributeValue(element, name, &value);
    return CFBridgingRelease(value);
}

static BOOL WindowBounds(AXUIElementRef window, CGRect *bounds) {
    id position = Attribute(window, kAXPositionAttribute);
    id size = Attribute(window, kAXSizeAttribute);
    if (!position || !size || CFGetTypeID((__bridge CFTypeRef)position) != AXValueGetTypeID() ||
        CFGetTypeID((__bridge CFTypeRef)size) != AXValueGetTypeID()) return NO;
    return AXValueGetValue((__bridge AXValueRef)position, kAXValueCGPointType, &bounds->origin) &&
           AXValueGetValue((__bridge AXValueRef)size, kAXValueCGSizeType, &bounds->size);
}

static NSString *MoveApplication(NSRunningApplication *application, BOOL toWorkspace) {
    if (!WindowMovementAllowed()) return @"Enable Accessibility for Virtual Desktop in System Settings, then try moving the app again.";
    if (application.terminated) return @"That app has quit. Open the menu again to refresh the app list.";
    CGDirectDisplayID workspace = WorkspaceDisplayID();
    NSScreen *destination = toWorkspace ? nil : MainPhysicalScreen();
    if (toWorkspace) {
        for (NSScreen *screen in NSScreen.screens) {
            if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == workspace) {
                destination = screen;
                break;
            }
        }
    }
    if (!workspace || !destination) return @"Both Agent Display and a physical display must be connected.";

    // AppKit is bottom-left based. AX and CG use top-left coordinates, including negative display origins.
    CGDirectDisplayID destinationID = [destination.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
    CGRect displayBounds = CGDisplayBounds(destinationID);
    NSRect visible = destination.visibleFrame;
    CGRect usable = CGRectMake(displayBounds.origin.x + visible.origin.x - destination.frame.origin.x,
                               displayBounds.origin.y + NSMaxY(destination.frame) - NSMaxY(visible),
                               visible.size.width, visible.size.height);
    AXUIElementRef appElement = AXUIElementCreateApplication(application.processIdentifier);
    AXUIElementSetMessagingTimeout(appElement, 1.0);
    id windowList = Attribute(appElement, kAXWindowsAttribute);
    if (![windowList isKindOfClass:NSArray.class]) {
        CFRelease(appElement);
        return @"macOS could not read this app’s windows. Check Accessibility permission and try again.";
    }
    NSUInteger moved = 0, failed = 0, fullscreen = 0;
    for (id item in windowList) {
        AXUIElementRef window = (__bridge AXUIElementRef)item;
        CGRect bounds;
        if (!WindowBounds(window, &bounds) || !WindowMatchesSource(bounds, workspace, toWorkspace)) continue;
        if ([Attribute(window, CFSTR("AXFullScreen")) boolValue]) { fullscreen++; continue; }
        if ([Attribute(window, kAXMinimizedAttribute) boolValue])
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute, kCFBooleanFalse);

        CGSize size = CGSizeMake(MIN(bounds.size.width, usable.size.width), MIN(bounds.size.height, usable.size.height));
        AXValueRef sizeValue = AXValueCreate(kAXValueCGSizeType, &size);
        AXUIElementSetAttributeValue(window, kAXSizeAttribute, sizeValue);
        CFRelease(sizeValue);
        // Re-read size because apps can impose minimum sizes or refuse resizing.
        CGRect resized;
        if (WindowBounds(window, &resized)) size = resized.size;
        CGFloat offset = (moved % 5) * 24;
        CGPoint point = CGPointMake(usable.origin.x + MAX(0, (usable.size.width - size.width) / 2 + offset),
                                   usable.origin.y + MAX(0, (usable.size.height - size.height) / 2 + offset));
        point.x = MIN(point.x, usable.origin.x + MAX(0, usable.size.width - size.width));
        point.y = MIN(point.y, usable.origin.y + MAX(0, usable.size.height - size.height));
        AXValueRef positionValue = AXValueCreate(kAXValueCGPointType, &point);
        AXError result = AXUIElementSetAttributeValue(window, kAXPositionAttribute, positionValue);
        CFRelease(positionValue);
        CGRect actual;
        if (result == kAXErrorSuccess && WindowBounds(window, &actual) &&
            fabs(actual.origin.x - point.x) < 4 && fabs(actual.origin.y - point.y) < 4) {
            AXUIElementPerformAction(window, kAXRaiseAction);
            moved++;
        } else failed++;
    }
    CFRelease(appElement);
    if (moved) [application activateWithOptions:0];
    if (fullscreen || failed) {
        NSMutableArray *messages = [NSMutableArray array];
        if (moved) [messages addObject:[NSString stringWithFormat:@"Moved %lu window(s).", (unsigned long)moved]];
        if (fullscreen) [messages addObject:@"Exit full screen for the remaining window(s), then try again."];
        if (failed) [messages addObject:@"The app did not move one or more windows. Try its Window → Move to Display command."];
        return [messages componentsJoinedByString:@" "];
    }
    if (moved) return nil;
    return toWorkspace ? @"This app has no movable windows on your physical displays. Open the menu to refresh the list." :
                         @"This app has no movable windows on Agent Display. Open the menu to refresh the list.";
}

NSString *MoveApplicationToMainDisplay(NSRunningApplication *application) {
    return MoveApplication(application, NO);
}

NSString *MoveApplicationToWorkspace(NSRunningApplication *application) {
    return MoveApplication(application, YES);
}
