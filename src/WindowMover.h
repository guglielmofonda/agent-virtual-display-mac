#import <Cocoa/Cocoa.h>

// Window coordinates in this module use CoreGraphics' top-left origin.
NSScreen *MainPhysicalScreen(void);
NSArray<NSRunningApplication *> *ApplicationsOnWorkspace(void);
NSArray<NSRunningApplication *> *OpenApplications(void);
BOOL WindowMovementAllowed(void);
NSString *MoveApplicationToMainDisplay(NSRunningApplication *application);
NSString *MoveApplicationToWorkspace(NSRunningApplication *application);
// Agent calls preserve keyboard focus by default and return verified counts.
NSDictionary *MoveApplicationForAgent(NSRunningApplication *application, BOOL toWorkspace, BOOL activate);
