# Commands and recovery

Run `python3 <skill-directory>/scripts/agent_display.py --help`. Python 3.9+ and a signed-in macOS desktop are required. The app must be version 0.5.0 or newer.

| Command | Result |
| --- | --- |
| `status` | App version, display ID/bounds, live preview status, permission status, and setup completion. No mutations. |
| `launch --app-path /path/to/VirtualDesktop.app` | Open the existing installation and wait for its local interface. No compilation or signing. |
| `apps` | Running desktop apps, bundle IDs, process IDs, and visible presence on Agent Display. |
| `apps --on-agent` | Apps with a visible normal window on Agent Display, excluding hidden/minimized/other-Space windows. |
| `start` / `show` | Start or reuse the display, show the preview, and wait for a live frame. |
| `hide` | Hide the preview and pause capture; retain the display. |
| `setup` | Open the permission guide. The user approves system prompts. |
| `open BUNDLE_ID [--to agent\|main] [--activate]` | Launch/reopen, wait for a window, then move the app’s eligible source windows. |
| `move BUNDLE_ID [--to agent\|main] [--activate]` | Move an already-running app’s eligible source windows. |

Global options go **before** the command: `--timeout 30 open com.apple.Safari`. The timeout (1–60 seconds) bounds polling for a live preview or a newly created app window. Each local request has a separate transport deadline. Operational results and errors are JSON on stdout, with exit 0 for success and exit 1 for failure; invalid command syntax uses argparse’s usage error on stderr.

## Common failures

| Code | Action |
| --- | --- |
| `app_unavailable` | Launch the existing signed app. An old running app may lack the interface; check its version before retrying. |
| `update_required` | Update the app with its established signing identity. Keep its bundle identifier and packaged icon. |
| `setup_required`, `permission_required` | Open `setup`; explain the needed permission. Let the user approve it in macOS, then reopen the same app if required. |
| `access_denied` | The agent sandbox cannot reach the local Mac interface. Report the limitation; do not change sandbox rules or use another execution channel to bypass it. |
| `mac_required` | Run on the Mac. A cloud-hosted Linux agent cannot reach this socket. |
| `app_not_found` | Check the installed app’s bundle identifier. |
| `no_windows` | The app has no movable source window. Open a window in it, then retry `move`. Do not assume launch created one. |
| `fullscreen` | Exit full screen for the relevant window before retrying. |
| `multiple_instances` | Use the target app’s own Window menu for the intended instance. |
| `busy`, `command_timeout`, `move_failed` | Inspect status and any partial `moved_windows` count before retrying; the earlier action may have started. |
| `preview_not_live` | Inspect the returned status. Check screen permission and the app’s preview error. Hiding/showing can retry capture without removing the display. |

## Portability and boundaries

The skill uses the open `SKILL.md` format and a standard-library Python client. Install the **whole folder**, including scripts and references, in the agent’s skill directory. It does not depend on Claude-specific substitutions, Codex tools, MCP, or an API key. An agent without automatic skill discovery can read SKILL.md and execute the same helper.

The app listens on a private Unix socket at `~/Library/Application Support/AgentDisplay/control.sock`. The directory is mode 0700, the socket is mode 0600, and the server checks the peer’s user ID. There is no TCP listener. Other processes running as the same user can issue these limited app/display commands. Normal agent approval and sandbox rules still apply.

`AGENT_DISPLAY_APP` may specify the existing app location for `launch`. The helper’s `--socket` option is for an explicitly selected private local endpoint, such as a test fixture; it is not a remote-control transport. Do not point it at another user’s socket.
