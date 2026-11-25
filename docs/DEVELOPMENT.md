# Development

[← Agent Display](../README.md)

## Build and test

The project builds directly with Apple’s compiler tools; no package manager is needed.

```sh
make build
make test
make test-ui
```

`make build` packages `build/VirtualDesktop.app`, includes the app icon, signs it with the identity in `Signing.local.mk` when configured, and verifies the signature. Without a configured identity it uses ad-hoc signing. Quit a running installation before rebuilding it.

To check a change without replacing your signed installation:

```sh
make build \
  APP=build/check/VirtualDesktop.app \
  BIN=build/check/VirtualDesktop.app/Contents/MacOS/VirtualDesktop \
  CODE_SIGN_IDENTITY=-
make test
zsh -n Start.command
git diff --check
```

Do not launch the ad-hoc check bundle alongside your signed installation: they share a bundle ID but have different code identities. Use the [signing setup](SETUP.md#keep-permissions-across-updates) for an installation you’ll run.

Keep custom `APP` and `BIN` paths relative and free of spaces. The repository’s enclosing directory can contain spaces; relative Make targets keep that path out of target names.

## Code map

| File | Responsibility |
| --- | --- |
| `src/Display.m` | Create and identify Agent Display, configure its Retina mode, and place it to the left of physical screens. |
| `src/Viewer.m` | Menu bar controls, floating AppKit preview, ScreenCaptureKit capture, and display lifecycle. |
| `src/SetupWindowController.m` | Native first-run setup, permission checks, preview verification, and an optional first-app picker. |
| `src/SetupState.m` | Saved setup progress, completion, and migration of existing installations. |
| `src/WindowMover.m` | Running-app inventory, visible-window filtering, and Accessibility-based window movement. |
| `tests/WindowMoverTests.m` | App and window inventory checks that run without GUI privacy grants. |
| `tests/SetupStateTests.m` / `tests/SetupUITests.m` | Setup persistence and migration; permission/preview gates and light/dark layout checks. |
| `Start.command` | Build/open entry point and staged certificate-signing setup. |
| `assets/AppIcon.png` / `AppIcon.icns` | App artwork and the packaged macOS icon. |
| `AGENTS.md` | Instructions for agents operating or updating the app. |

## Display and capture

The display has a 1920 × 1080-point logical workspace and 3840 × 2160 backing pixels. Pointer mapping and window movement use logical display coordinates. Capture dimensions come from `SCContentFilter.contentRect × pointPixelScale`, avoiding a fixed low-resolution preview.

Capture uses BGRA frames at up to 24 fps, a three-frame queue, and no audio. Frames are displayed in memory using `AVSampleBufferDisplayLayer`. Hiding the preview stops capture while retaining ownership of the virtual display.

## Verification

`make test` checks running-app filtering, sorting, deduplication, negative display coordinates, windows spanning displays, and exclusion of hidden, minimized, transparent, overlay, and other-Space windows from the return menu.

It also checks setup progress across launches, migration of existing users, and completion only after a live preview. `make test-ui` uses an isolated AppKit executable with stubbed permission checks and a test delegate: it never starts a display, changes privacy grants, or moves an app. It checks permission denial, enabling access, optional Accessibility, capture failure/retry, and successful completion. It exports the real setup views in light and dark appearances to `build/setup-ui/` for inspection. These checks do not replace a real macOS permission-prompt test.

To review setup in the certificate-signed app, use **Setup & Permissions…**, or quit and run `open build/VirtualDesktop.app --args --show-setup`. The flag shows the guide without clearing completion or existing macOS permissions. New installations start at Welcome; incomplete setup remembers its last step. Existing installations with the legacy `WorkspaceStopped` preference skip automatic onboarding.

GUI behavior requires a signed-in Mac and the relevant privacy grants. Before reporting a working change, check:

1. The original physical display stays primary and the preview reaches **Agent Display · Live**.
2. The Retina preview reports **3840 × 2160**, with readable text at a larger window size.
3. A test app can move to Agent Display and return; both menus refresh correctly.
4. Hiding/showing the preview preserves the display; stopping/restarting it behaves as expected.
5. Rebuilding with the same certificate preserves the app’s identity and packaged icon.
6. A fresh installation shows Welcome before creating a display or requesting capture. Screen permission is requested only from its button, returning from Settings refreshes status, and a quit/reopen resumes setup. Accessibility can be skipped. Verify a real live frame before finishing, then confirm setup stays dismissed on subsequent launches.

The 4K implementation has passed a local build and the inventory tests. A live **3840 × 2160** preview was verified on Apple silicon running macOS 26.6.2. An upgraded installation retained macOS’s old low-resolution mode until the Retina default was selected in Displays and the preview reopened; see the [recovery steps](SETUP.md#the-upgraded-preview-still-shows-1920--1080).
