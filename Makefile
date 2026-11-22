APP := build/AgentVirtualDisplayMac.app
BIN := $(APP)/Contents/MacOS/AgentVirtualDisplayMac
.PHONY: build
build: $(APP)/Contents/_CodeSignature/CodeResources

$(APP)/Contents/_CodeSignature/CodeResources: $(BIN) $(APP)/Contents/Info.plist
	codesign --force --sign - "$(APP)"
	codesign --verify --strict "$(APP)"

$(BIN): src/Viewer.m src/Display.m src/Display.h Makefile
	mkdir -p "$(dir $@)"
	xcrun clang -fobjc-arc -fno-modules -mmacosx-version-min=15.2 -Wall -Wextra -Wno-unused-parameter src/Viewer.m src/Display.m -framework Cocoa -framework CoreGraphics -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia -framework QuartzCore -o "$@"

$(APP)/Contents/Info.plist: Info.plist
	mkdir -p "$(dir $@)"
	plutil -lint "$<"
	cp "$<" "$@"
