APP := build/VirtualDesktop.app
BIN := $(APP)/Contents/MacOS/VirtualDesktop
-include Signing.local.mk
CODE_SIGN_IDENTITY ?= -
.PHONY: build sign test test-ui test-agent test-agent-unit
build: $(APP)/Contents/_CodeSignature/CodeResources

test: build/WindowMoverTests build/SetupStateTests
	./build/WindowMoverTests
	./build/SetupStateTests

build/SetupStateTests: tests/SetupStateTests.m src/SetupState.m src/SetupState.h Makefile
	mkdir -p build
	xcrun clang -fobjc-arc -fno-modules -mmacosx-version-min=15.2 -Wall -Wextra tests/SetupStateTests.m src/SetupState.m -framework Foundation -o "$@"

test-ui: build/SetupUITests
	./build/SetupUITests

test-agent: build/AgentServerFixture
	./build/AgentServerFixture --validate
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_agent_skill.py' -v

test-agent-unit: build/AgentServerFixture
	./build/AgentServerFixture --validate
	PYTHONPATH=tests PYTHONDONTWRITEBYTECODE=1 python3 -m unittest test_agent_skill.AgentClientTests test_agent_skill.AgentSafetyTests -v

build/AgentServerFixture: tests/AgentServerFixture.m src/AgentServer.m src/AgentServer.h Makefile
	mkdir -p build
	xcrun clang -fobjc-arc -fno-modules -mmacosx-version-min=15.2 -Wall -Wextra tests/AgentServerFixture.m src/AgentServer.m -framework Foundation -o "$@"

build/SetupUITests: tests/SetupUITests.m src/SetupState.m src/SetupState.h src/SetupWindowController.m src/SetupWindowController.h Makefile
	mkdir -p build
	xcrun clang -fobjc-arc -fno-modules -mmacosx-version-min=15.2 -Wall -Wextra -Wno-unused-parameter tests/SetupUITests.m src/SetupState.m src/SetupWindowController.m -framework Cocoa -framework ApplicationServices -framework CoreGraphics -framework QuartzCore -o "$@"

build/WindowMoverTests: tests/WindowMoverTests.m src/WindowMover.m src/WindowMover.h src/Display.m src/Display.h Makefile
	mkdir -p build
	xcrun clang -fobjc-arc -fno-modules -mmacosx-version-min=15.2 -Wall -Wextra -Wno-unused-parameter tests/WindowMoverTests.m src/Display.m -framework Cocoa -framework ApplicationServices -framework CoreGraphics -o "$@"

sign $(APP)/Contents/_CodeSignature/CodeResources: $(BIN) $(APP)/Contents/Info.plist $(APP)/Contents/Resources/AppIcon.icns $(wildcard Signing.local.mk)
	@if [ "$(CODE_SIGN_IDENTITY)" = "-" ]; then echo "Using ad-hoc signing: changed builds may need new privacy permissions. See README.md for stable signing." >&2; fi
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" "$(APP)"
	codesign --verify --strict "$(APP)"

$(BIN): src/Viewer.m src/Display.m src/Display.h src/WindowMover.m src/WindowMover.h src/SetupState.m src/SetupState.h src/SetupWindowController.m src/SetupWindowController.h src/AgentServer.m src/AgentServer.h Makefile
	mkdir -p "$(dir $@)"
	xcrun clang -fobjc-arc -fno-modules -mmacosx-version-min=15.2 -Wall -Wextra -Wno-unused-parameter src/Viewer.m src/Display.m src/WindowMover.m src/SetupState.m src/SetupWindowController.m src/AgentServer.m -framework Cocoa -framework ApplicationServices -framework CoreGraphics -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia -framework QuartzCore -o "$@"

$(APP)/Contents/Info.plist: Info.plist
	mkdir -p "$(dir $@)"
	plutil -lint "$<"
	cp "$<" "$@"

$(APP)/Contents/Resources/AppIcon.icns: assets/AppIcon.icns
	mkdir -p "$(dir $@)"
	cp "$<" "$@"
