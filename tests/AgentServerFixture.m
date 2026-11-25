// Test-only transport fixture. It never opens apps, captures, or moves windows.
#import "../src/AgentServer.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        if (!strcmp(argv[1], "--validate")) {
            NSArray *invalid = @[NSNull.null, @[], @{@"version": @2, @"command": @"status"},
                @{@"version": @1, @"command": @"quit"}, @{@"version": @1, @"command": @"open", @"app": @"$(touch x)"},
                @{@"version": @1, @"command": @"move", @"app": @"com.apple.Safari", @"destination": @"elsewhere"},
                @{@"version": @1, @"command": @"move", @"app": @"com.apple.Safari", @"activate": @"yes"},
                @{@"version": @1, @"command": @"status", @"output_path": @"/tmp/x"}];
            for (id request in invalid) if (!ADValidateAgentRequest(request)) { fputs("Invalid request accepted\n", stderr); return 1; }
            NSArray *valid = @[@{@"version": @1, @"command": @"status"},
                @{@"version": @1, @"command": @"move", @"app": @"com.apple.Safari", @"destination": @"main", @"activate": @NO}];
            for (id request in valid) if (ADValidateAgentRequest(request)) { fputs("Valid request rejected\n", stderr); return 1; }
            puts("Agent request validation passed."); return 0;
        }
        NSMutableDictionary *moves = [NSMutableDictionary new];
        ADAgentServer *server = [[ADAgentServer alloc] initWithDirectory:@(argv[1]) handler:^(NSDictionary *request, ADAgentReply reply) {
            NSString *command = request[@"command"];
            if ([command isEqual:@"status"] || [command isEqual:@"start"] || [command isEqual:@"show"]) {
                reply(@{@"ok": @YES, @"protocol_version": @1, @"display_running": @YES, @"preview_live": @YES,
                    @"permissions": @{@"screen_recording": @YES, @"accessibility": @YES}, @"moves": moves.copy});
            } else if ([command isEqual:@"apps"]) {
                reply(@{@"ok": @YES, @"display_inventory_available": @YES, @"apps": @[
                    @{@"bundle_id": @"test.agent", @"on_agent_display": @YES},
                    @{@"bundle_id": @"test.main", @"on_agent_display": @NO}]});
            } else if ([command isEqual:@"open"]) reply(@{@"ok": @YES, @"app": request[@"app"]});
            else if ([command isEqual:@"move"]) {
                NSString *app = request[@"app"];
                NSUInteger count = [moves[app] unsignedIntegerValue] + 1;
                moves[app] = @(count);
                if ([app isEqual:@"test.partial"]) reply(@{@"ok": @NO, @"moved_windows": @1, @"error": @{@"code": @"move_failed", @"message": @"Partial test move"}});
                else if ([app isEqual:@"test.denied"]) reply(ADAgentError(@"permission_required", @"Test permission denied"));
                else if ([app isEqual:@"test.empty"] || ([app isEqual:@"test.delayed"] && count == 1)) reply(ADAgentError(@"no_windows", @"No test windows yet"));
                else reply(@{@"ok": @YES, @"moved_windows": @1, @"destination": request[@"destination"] ?: @"agent", @"activate": request[@"activate"] ?: @NO});
            } else reply(@{@"ok": @YES});
        }];
        NSError *error = nil;
        if (![server start:&error]) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 1; }
        puts("READY"); fflush(stdout);
        [NSRunLoop.currentRunLoop run];
        [server stop];
    }
    return 0;
}
