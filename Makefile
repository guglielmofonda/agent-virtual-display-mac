APP := build/VirtualDesktop.app
BIN := $(APP)/Contents/MacOS/VirtualDesktop
-include Signing.local.mk
CODE_SIGN_IDENTITY ?= -
.PHONY: build sign test
build: $(APP)/Contents/_CodeSignature/CodeResources

test: build/WindowMoverTests
	./build/WindowMoverTests

build/WindowMoverTests: tests/WindowMoverTests.m src/WindowMover.m src/WindowMover.h src/Display.m src/Display.h Makefile
	mkdir -p build
	xcrun clang -fobjc-arc -fno-modules -mmacosx-version-min=15.2 -Wall -Wextra -Wno-unused-parameter tests/WindowMoverTests.m src/Display.m -framework Cocoa -framework ApplicationServices -framework CoreGraphics -o "$@"

sign $(APP)/Contents/_CodeSignature/CodeResources: $(BIN) $(APP)/Contents/Info.plist $(APP)/Contents/Resources/AppIcon.icns $(wildcard Signing.local.mk)
	@if [ "$(CODE_SIGN_IDENTITY)" = "-" ]; then echo "Using ad-hoc signing: changed builds may need new privacy permissions. See README.md for stable signing." >&2; fi
	codesign --force --sign "$(CODE_SIGN_IDENTITY)" "$(APP)"
	codesign --verify --strict "$(APP)"

$(BIN): src/Viewer.m src/Display.m src/Display.h src/WindowMover.m src/WindowMover.h Makefile
	mkdir -p "$(dir $@)"
	xcrun clang -fobjc-arc -fno-modules -mmacosx-version-min=15.2 -Wall -Wextra -Wno-unused-parameter src/Viewer.m src/Display.m src/WindowMover.m -framework Cocoa -framework ApplicationServices -framework CoreGraphics -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia -framework QuartzCore -o "$@"

$(APP)/Contents/Info.plist: Info.plist
	mkdir -p "$(dir $@)"
	plutil -lint "$<"
	cp "$<" "$@"

$(APP)/Contents/Resources/AppIcon.icns: assets/AppIcon.icns
	mkdir -p "$(dir $@)"
	cp "$<" "$@"
