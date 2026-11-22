# Set up a visible workspace for Mac computer use

Use this procedure on the receiving user’s signed-in Mac. A cloud-only agent can build or explain the setup, but verifying the display and moving a window require a connection to that Mac’s GUI.

1. Clone this repository to its own directory. Run `make build` there. Open `build/MacAgentDisplay.app` in the Mac GUI. The source builds locally with Apple Command Line Tools. Existing installations can simply reopen the app.
2. If **Start preview** appears, use it. macOS may require **Screen & System Audio Recording** permission for MacAgentDisplay. Explain the scope, obtain the owner’s approval, and follow the system prompt. The app reads frames from Codex Workspace and displays them locally with audio off. Reopen after a permission change if needed. Avoid the full-screen sharing picker.
3. Confirm **Codex Workspace · Live** before reporting a working preview. If no separate screen appears, check System Settings → Displays. Keep the original main screen primary. The app places a newly created workspace to the left of the leftmost active screen and respects an existing workspace’s arrangement.
4. Create a separate window in the requested browser, using the user’s normal profile when the task needs its login. Use the browser’s Window menu to move only that window to **Codex Workspace**. If the command is disabled, exit full screen for the dedicated window and retry. If the app lacks the menu, use the native window move controls.
5. Verify the floating preview shows the dedicated window. For subsequent work, target the specific tab or window. Ask before an action that would interrupt an actively typing user. The preview is for observing; clicking inside it intentionally moves the real pointer. Leave the app running for the user and use its close button when they ask to stop.

If input is blocked by a macOS sharing overlay, Escape dismisses it. If the build succeeds but the shell sees zero displays, launch the app through Finder. If an OS update prevents display creation, report the error and the macOS version.
