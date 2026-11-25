# Set up a visible workspace for Mac computer use

Package a proper app icon in every build so Finder and System Settings show it; a menu bar symbol alone is not sufficient. Preserve `assets/AppIcon.png` and the Makefile’s icon packaging when rebuilding this app.

For updates, preserve the bundle identifier and reuse the configured `CODE_SIGN_IDENTITY` in `Signing.local.mk`. Do not replace a certificate-signed installation with an ad-hoc build: it invalidates the user’s privacy grants. If no signing identity is configured, explain the limitation before repeatedly rebuilding and refreshing permissions.

Use this procedure on the receiving user’s signed-in Mac. A cloud-only agent can build or explain the setup, but verifying the display and moving a window require a connection to that Mac’s GUI.

1. Clone this repository to its own directory. Run `make build` there. Open `build/VirtualDesktop.app` in the Mac GUI. The source builds locally with Apple Command Line Tools. Existing installations can simply reopen the app.
2. If **Start preview** appears, use it. macOS may require **Screen & System Audio Recording** permission for VirtualDesktop. Explain the scope, obtain the owner’s approval, and follow the system prompt. The app reads frames from Agent Display and displays them locally with audio off. Reopen after a permission change if needed. Avoid the full-screen sharing picker.
3. Confirm **Agent Display · Live** before reporting a working preview. If no separate screen appears, check System Settings → Displays. Keep the original main screen primary. The app places a newly created workspace to the left of the leftmost active screen and respects an existing workspace’s arrangement.
4. Create a separate window in the requested browser, using the user’s normal profile when the task needs its login. Use the browser’s Window menu to move only that window to **Agent Display**. If the command is disabled, exit full screen for the dedicated window and retry. If the app lacks the menu, use the native window move controls.
5. Verify the floating preview shows the dedicated window. For subsequent work, target the specific tab or window. Ask before an action that would interrupt an actively typing user. The preview is for observing; clicking inside it intentionally moves the real pointer. Leave the app running for the user. Closing the preview hides it. Use **Stop Virtual Desktop** from the menu bar or **Desktop Controls** to disconnect the display.

After Accessibility permission is granted, the menu can move an app’s windows from physical displays to Agent Display or bring its Agent Display windows back to the main display. If the display is managed by another instance, stop its original launcher first. The legacy Terminal launcher exits with Control-C. Then start the display from this app’s menu to enable Stop and Restart.

The Move App to Agent Display menu lists all running regular desktop apps. The Bring App to Main Display menu lists only apps with visible normal windows on Agent Display; hidden/minimized windows and windows on other Spaces must not populate it. Refresh these lists whenever the menu opens. Run `make test` when changing the window inventory/filtering.

Agent Display uses a 1920 × 1080-point HiDPI mode with 3840 × 2160 backing pixels. Preserve logical coordinates for window movement and pointer mapping. Capture at `SCContentFilter.contentRect` multiplied by `pointPixelScale`; do not downsample the preview to a fixed 720p size. The preview subtitle reports the actual received frame dimensions.

If input is blocked by a macOS sharing overlay, Escape dismisses it. If the build succeeds but the shell sees zero displays, launch the app through Finder. If an OS update prevents display creation, report the error and the macOS version.
