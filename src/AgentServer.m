#import "AgentServer.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

NSDictionary *ADAgentError(NSString *code, NSString *message) {
    return @{@"ok": @NO, @"error": @{@"code": code, @"message": message}};
}
NSString *ADValidateAgentRequest(id request) {
    if (![request isKindOfClass:NSDictionary.class]) return @"Expected a JSON object.";
    if (![request[@"version"] isEqual:@1]) return @"Expected protocol version 1.";
    NSSet *commands = [NSSet setWithArray:@[@"status", @"apps", @"start", @"show", @"hide", @"setup", @"open", @"move"]];
    if (![request[@"command"] isKindOfClass:NSString.class] || ![commands containsObject:request[@"command"]]) return @"Unknown command.";
    BOOL appCommand = [@[@"open", @"move"] containsObject:request[@"command"]];
    NSSet *keys = [NSSet setWithArray:appCommand ? @[@"version", @"command", @"app", @"destination", @"activate"] : @[@"version", @"command"]];
    for (NSString *key in request) if (![keys containsObject:key]) return @"Unexpected command argument.";
    if (appCommand) {
        NSString *app = request[@"app"];
        if (![app isKindOfClass:NSString.class] || app.length > 255 ||
            [app rangeOfString:@"^[A-Za-z0-9][A-Za-z0-9.-]*$" options:NSRegularExpressionSearch].location == NSNotFound)
            return @"Use an installed app’s bundle identifier, such as com.apple.Safari.";
        if (request[@"destination"] && ![@[@"agent", @"main"] containsObject:request[@"destination"]]) return @"Destination must be agent or main.";
        id activate = request[@"activate"];
        if (activate && CFGetTypeID((__bridge CFTypeRef)activate) != CFBooleanGetTypeID()) return @"activate must be a JSON boolean.";
    }
    return nil;
}

@interface ADAgentServer ()
@property(copy) NSString *directory;
@property(copy) ADAgentHandler handler;
@property(strong) dispatch_source_t source;
@property(strong) dispatch_queue_t queue;
@property int lockFD;
@property NSUInteger clients;
@property BOOL ownsSocket;
@end
@implementation ADAgentServer
- (instancetype)initWithDirectory:(NSString *)directory handler:(ADAgentHandler)handler {
    if ((self = [super init])) {
        _directory = directory.copy;
        _handler = [handler copy];
        _lockFD = -1;
        _queue = dispatch_queue_create("AgentDisplay.control.accept", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (void)dealloc { [self stop]; }
- (NSString *)socketPath { return [self.directory stringByAppendingPathComponent:@"control.sock"]; }
- (BOOL)fail:(NSError **)error message:(NSString *)message {
    if (error) *error = [NSError errorWithDomain:@"AgentDisplayControl" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
    [self stop];
    return NO;
}
- (BOOL)start:(NSError **)error {
    if (self.source) return YES;
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files createDirectoryAtPath:self.directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:error]) return NO;
    struct stat info;
    if (lstat(self.directory.fileSystemRepresentation, &info) || !S_ISDIR(info.st_mode) ||
        info.st_uid != getuid() || (info.st_mode & 0077))
        return [self fail:error message:@"Agent control requires a private directory owned by the signed-in user."];
    NSString *lockPath = [self.directory stringByAppendingPathComponent:@"control.lock"];
    self.lockFD = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (self.lockFD < 0 || fstat(self.lockFD, &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid() || (info.st_mode & 0077))
        return [self fail:error message:@"Could not safely open the agent control lock."];
    if (flock(self.lockFD, LOCK_EX | LOCK_NB)) return [self fail:error message:@"Another Agent Display instance already handles agent commands."];
    NSString *path = self.socketPath;
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    address.sun_len = sizeof(address);
    if (strlen(path.fileSystemRepresentation) >= sizeof(address.sun_path)) return [self fail:error message:@"The agent control socket path is too long."];
    strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));
    if (!lstat(path.fileSystemRepresentation, &info)) {
        if (!S_ISSOCK(info.st_mode) || info.st_uid != getuid()) return [self fail:error message:@"Refusing to replace an unexpected file at the control socket path."];
        if (unlink(path.fileSystemRepresentation)) return [self fail:error message:@"Could not remove the stale control socket."];
    } else if (errno != ENOENT) return [self fail:error message:@"Could not inspect the control socket path."];
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return [self fail:error message:@"Could not create the local control socket."];
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    fcntl(fd, F_SETFL, O_NONBLOCK);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address))) {
        NSString *reason = [NSString stringWithFormat:@"Could not bind the local control socket: %s", strerror(errno)];
        close(fd); return [self fail:error message:reason];
    }
    self.ownsSocket = YES;
    if (chmod(path.fileSystemRepresentation, 0600) || listen(fd, 4)) {
        close(fd); return [self fail:error message:@"Could not protect or listen on the control socket."];
    }
    self.source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, self.queue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.source, ^{
        typeof(self) owner = weakSelf;
        if (!owner) return;
        int client;
        while ((client = accept(fd, NULL, NULL)) >= 0) {
            uid_t uid; gid_t gid;
            if (owner.clients >= 4 || getpeereid(client, &uid, &gid) || uid != getuid()) { close(client); continue; }
            fcntl(client, F_SETFL, 0);
            fcntl(client, F_SETFD, FD_CLOEXEC);
            owner.clients++;
            int connection = client;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                @autoreleasepool { [owner handleClient:connection]; }
                close(connection);
                dispatch_async(owner.queue, ^{ owner.clients--; });
            });
        }
    });
    dispatch_source_set_cancel_handler(self.source, ^{ close(fd); });
    dispatch_resume(self.source);
    return YES;
}
- (void)stop {
    if (self.source) { dispatch_source_cancel(self.source); self.source = nil; }
    if (self.ownsSocket) { unlink(self.socketPath.fileSystemRepresentation); self.ownsSocket = NO; }
    if (self.lockFD >= 0) { close(self.lockFD); self.lockFD = -1; }
}
- (void)handleClient:(int)fd {
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct timeval timeout = {.tv_sec = 2};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    NSMutableData *data = [NSMutableData new];
    char byte;
    BOOL complete = NO;
    // Bound total read time as well as byte count; slow clients cannot hold a
    // worker forever by sending one byte per socket timeout.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (data.length <= 4096 && deadline.timeIntervalSinceNow > 0 && recv(fd, &byte, 1, 0) == 1) {
        if (byte == '\n') { complete = YES; break; }
        [data appendBytes:&byte length:1];
    }
    id request = complete && data.length <= 4096 ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil] : nil;
    NSString *invalid = ADValidateAgentRequest(request);
    __block NSDictionary *response = invalid ? ADAgentError(@"invalid_request", invalid) : nil;
    if (!response) {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        NSObject *guard = [NSObject new];
        __block BOOL expired = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            @synchronized (guard) { if (expired) return; }
            self.handler(request, ^(NSDictionary *value) {
                @synchronized (guard) { if (expired || response) return; response = value; }
                dispatch_semaphore_signal(done);
            });
        });
        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC))) {
            @synchronized (guard) {
                expired = YES;
                response = ADAgentError(@"command_timeout", @"The app did not respond in time. Check status before retrying; the action may already have started.");
            }
        }
    }
    NSMutableData *output = [[NSJSONSerialization dataWithJSONObject:response options:0 error:nil] mutableCopy];
    [output appendBytes:"\n" length:1];
    const char *bytes = output.bytes;
    size_t remaining = output.length;
    while (remaining) {
        ssize_t count = send(fd, bytes, remaining, 0);
        if (count <= 0) break;
        bytes += count; remaining -= count;
    }
}
@end
