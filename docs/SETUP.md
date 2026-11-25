# Setup & troubleshooting

[← Agent Display](../README.md)

## Requirements

- A signed-in Mac desktop running macOS 15.2 or newer.
- Apple Command Line Tools with a macOS 15.2+ SDK, or a compatible Xcode installation.
- Screen & System Audio Recording permission for the live preview.
- Accessibility permission if you want the menu to move other apps’ windows.

Run `xcode-select --install` if the compiler tools are missing. Start the app with `./Start.command` from the repository, or double-click that file in Finder. The app bundle is `build/VirtualDesktop.app`; its macOS name is **Virtual Desktop**.

## Keep permissions across updates

The default local build uses ad-hoc signing. Its identity changes with the binary, which can invalidate Screen Recording and Accessibility grants even when System Settings still shows the switches enabled.

For repeated local builds, use the same **Apple Development** identity:

1. In Xcode, open **Settings → Accounts / Apple Accounts**, select your account and team, then open **Manage Certificates** and create an **Apple Development** certificate.
2. Run this from the repository in your own Terminal:

   ```sh
   ./Start.command --setup-signing
   ```

3. Select a certificate number if more than one is available. Quit **Virtual Desktop** using its menu, then press Return when the launcher asks.
4. Allow Screen Recording and Accessibility again if macOS requests them after the identity change.

The launcher builds and verifies a signed replacement before installing it. It saves only the chosen certificate fingerprint in `Signing.local.mk`, which Git ignores. Your private key stays in Keychain. Later updates reuse the saved certificate automatically.

Keep the bundle ID and signing identity consistent, and keep opening the same installation. Do not replace a certificate-signed app with an ad-hoc build. A missing configured identity fails signing instead of silently falling back.

Stable signing preserves code identity; it does not disable macOS’s periodic capture reminders. See [Apple’s explanation of code identity and privacy permissions](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements/). Notarization for distribution is a separate step.

<details>
<summary>Manual signing configuration</summary>

List usable identities:

```sh
security find-identity -v -p codesigning
```

Save your chosen identity in `Signing.local.mk`:

```make
CODE_SIGN_IDENTITY = Apple Development: Your Name (CERTIFICATE_ID)
```

You can use the certificate’s exact fingerprint instead of its name. Quit the app, run `make sign`, and reopen `build/VirtualDesktop.app`. Subsequent builds reuse the identity. For a staged, verified replacement, prefer `./Start.command --setup-signing`.

</details>

## Update an existing installation

Quit **Virtual Desktop**, then run from the repository:

```sh
git pull --ff-only
./Start.command --setup-signing
```

That command requires an Apple Development certificate. For an installation still using ad-hoc signing, use `./Start.command`; macOS may require renewed permissions after rebuilding.

Reopening creates the new Retina display: **3840 × 2160 pixels**, with a **1920 × 1080-point** workspace. The preview’s subtitle reports the actual frame size. A display owned by an older launcher retains that launcher’s resolution until it is stopped and recreated.

## Common issues

### The upgraded preview still shows 1920 × 1080

macOS can remember the old low-resolution display mode. Open **System Settings → Displays → Agent Display** and choose **1920 × 1080 (Default)**, not **1920 × 1080 (low resolution)**. The default is the Retina mode: it keeps the same workspace size while rendering 3840 × 2160 pixels. Toggle **Show all resolutions** if you need to distinguish the two entries.

Then **Hide Preview** and **Show Preview** to restart capture at the new resolution. The subtitle should read **3840 × 2160**. Do this after changing display modes while the preview is already running.

### The preview is blank or says macOS declined capture

Confirm that **Virtual Desktop** is enabled in **System Settings → Privacy & Security → Screen & System Audio Recording**. Quit and reopen the app after changing permission, then choose **Start preview** if needed.

If you recently changed signing identities and the enabled switch no longer works, reset this app’s screen-capture grant from your own Terminal:

```sh
tccutil reset ScreenCapture io.github.guglielmofonda.virtual-desktop
```

Then reopen the app and grant permission again. This is a recovery step for a stale grant, not a routine update step.

### An app is missing from a move menu

**Move App to Agent Display** lists running regular desktop apps, including apps with no windows. It excludes background services and the viewer itself. Open the app, then reopen the menu to refresh it.

**Bring App to Main Display** lists only apps with a visible normal window on Agent Display. Unhide or restore a minimized window, or switch to its Space, if necessary. A window spanning screens is assigned by its center point.

### A window won’t move

Enable **Virtual Desktop** under **Privacy & Security → Accessibility**. Exit full screen for the window and try again. Some apps refuse programmatic movement or enforce a minimum window size; try their own **Window → Move to Display** command.

If Accessibility stopped working after a signing-identity change, reset only this app’s grant and enable it again:

```sh
tccutil reset Accessibility io.github.guglielmofonda.virtual-desktop
```

### The menu says another instance manages the display

Stop the launcher that originally created it, then choose **Start Virtual Desktop** in this app. If you used the legacy Terminal launcher, stop it with Control-C in its original Terminal session. The viewer can observe an existing Agent Display, but only its owner can disconnect it.

### The shell sees no displays, or no certificate

An agent sandbox or remote shell may lack access to your GUI session or login Keychain. Launch `build/VirtualDesktop.app` through Finder in your signed-in desktop. Run `./Start.command --setup-signing` in your own Terminal if the sandbox cannot see your signing identity. Do not export the private key.

### Closing the preview didn’t stop the display

This is intentional. Close hides the viewer and pauses capture. Use **Stop Virtual Desktop** to disconnect the display, or **Quit Virtual Desktop** to quit the app.

### It stopped working after a macOS update

Virtual display creation uses a private CoreGraphics API. [Open an issue](https://github.com/guglielmofonda/agent-virtual-display-mac/issues) with your macOS version, the error text, and whether the preview reaches **Agent Display · Live**. Remove personal desktop content from any screenshots you share.
