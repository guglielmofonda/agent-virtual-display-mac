#import <Cocoa/Cocoa.h>

// Window coordinates in this module use CoreGraphics' top-left origin.
NSScreen *MainPhysicalScreen(void);
NSArray<NSRunningApplication *> *ApplicationsOnWorkspace(void);
NSArray<NSRunningApplication *> *OpenApplications(void);
BOOL WindowMovementAllowed(void);
NSString *MoveApplicationToMainDisplay(NSRunningApplication *application);
NSString *MoveApplicationToWorkspace(NSRunningApplication *application);
