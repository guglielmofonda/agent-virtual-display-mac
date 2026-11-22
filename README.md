# Agent Virtual Display Mac

Give your Mac agent a second screen and watch its work in a small floating window. The app creates a 1920 × 1080 extended display called **Codex Workspace** to the left of your existing screens. Your usual screen stays primary. Reopening the app brings the viewer back.

## Give this to your agent

> Set up https://github.com/guglielmofonda/agent-virtual-display-mac on my Mac. Read AGENTS.md, open the live viewer, and move a dedicated browser window onto Codex Workspace. Keep my working window available and verify that the preview shows the browser.

For an agent that receives A2A messages, send the same task with the [A2A handoff](examples/README.md).

## Run it yourself

Use a signed-in Mac desktop, macOS 15.2 or newer, and Apple Command Line Tools with the macOS 15.2+ SDK. Run `xcode-select --install` if the tools are missing.

```sh
git clone https://github.com/guglielmofonda/agent-virtual-display-mac.git
cd agent-virtual-display-mac
./Start.command
```

1. Click **Start preview**. On the first run, enable **AgentVirtualDisplayMac** or **Agent Virtual Display Mac** in **System Settings → Privacy & Security → Screen & System Audio Recording**. Reopen the app if macOS asks.
2. Open a separate window in your browser. Exit full screen for that window, then use **Window → Move to Codex Workspace**. The floating viewer shows it once the title reads **Codex Workspace · Live**.
3. Keep typing in your regular app. Drag or resize the preview to suit your desk. To interact, click a spot in the preview to move your pointer there, then click again to act. Move right across the virtual screen’s edge to return to the adjacent physical screen.

Double-click **Start.command** next time, or open **build/AgentVirtualDisplayMac.app** directly. Close the viewer to stop. A display created by this app disconnects when it quits. If an existing compatible display was reused, its original owner controls its lifetime.

## What the app can access

macOS grants app-wide screen capture permission. The viewer selects the workspace by display identity, displays its frames in memory, and disables audio. The app has no network client or recording feature. Rebuilding or moving it may trigger a new permission request.

Both displays share the Mac’s keyboard focus and pointer. Agents should use controls targeted to the dedicated tab or window when available. System-wide clicks, keyboard shortcuts, and dialogs can still interrupt the person working. This utility supplies the display and viewer. The receiving agent supplies its own Mac or browser controls.

## Compatibility

The original display and live viewer were exercised on an Apple silicon Mac running macOS 26.6.2. The standalone build targets macOS 15.2+. Creating the virtual screen uses the private CoreGraphics virtual display API, which Apple may change. Capturing it uses ScreenCaptureKit. A shell that cannot see the logged-in desktop can still build the app. Launch the built app from Finder in the actual desktop session.
