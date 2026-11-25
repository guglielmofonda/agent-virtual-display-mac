#import <Foundation/Foundation.h>

typedef void (^ADAgentReply)(NSDictionary *response);
typedef void (^ADAgentHandler)(NSDictionary *request, ADAgentReply reply);
NSDictionary *ADAgentError(NSString *code, NSString *message);
NSString *ADValidateAgentRequest(id request);

// Same-user, local-only transport. The handler runs on the main queue.
@interface ADAgentServer : NSObject
- (instancetype)initWithDirectory:(NSString *)directory handler:(ADAgentHandler)handler;
- (BOOL)start:(NSError **)error;
- (void)stop;
@end
