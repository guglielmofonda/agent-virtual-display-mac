# Use Agent Display with your agent

[← Agent Display](../README.md)

The repository includes a portable **Agent Display** skill that can open apps on the virtual screen, move running apps there, bring them back, and verify the live preview. It uses the open [Agent Skills format](https://agentskills.io/specification) and a Python client, with no model API keys or agent-specific runtime dependency.

## Install the skill

First update and open **Agent Display 0.5.0+** on the Mac where the agent runs. Keep your existing signing identity and complete the app’s permission setup. Screen Recording is needed for the preview and Accessibility for moving windows. Installing the skill does not grant either permission.

From this repository, install for both Codex and Claude Code:

```sh
python3 tools/install-skill.py --agent both
```

| Agent | Personal skill location | How to request it |
| --- | --- | --- |
| Codex | `~/.agents/skills/agent-display/` | “Use $agent-display to open Safari on Agent Display.” |
| Claude Code | `~/.claude/skills/agent-display/` | “/agent-display Open Safari on Agent Display.” |
| Other Agent Skills clients | That client’s configured skill directory | Ask it to use the Agent Display skill. |
| Agents with a local shell but no skill discovery | Read `skills/agent-display/SKILL.md` directly | Run the same bundled helper following those instructions. |

These are the documented [Codex discovery locations](https://developers.openai.com/codex/skills) and [Claude Code discovery locations](https://code.claude.com/docs/en/skills). Discovery and approval behavior depend on the agent’s version and configuration. This is intended for **local Mac sessions**; installing it in a cloud sandbox does not give that sandbox control of your Mac. The agent must also be allowed to access the app’s local socket.

Install just one with `--agent codex` or `--agent claude`. To install for a particular project:

```sh
python3 tools/install-skill.py --agent both --scope project --project /path/to/project
```

For another client, use `--skills-dir /path/to/its/skills`. The installer copies the complete skill, including its script, so it works outside this checkout. It skips an identical installation and refuses to overwrite a different or customized skill; back up or rename that folder before installing an updated version.

## Ask in plain language

- “Open Safari on Agent Display.”
- “Move VS Code to the agent monitor.”
- “Bring Chrome back to my main display.”
- “Which apps are currently on Agent Display?”
- “Hide the preview but leave the apps running.”

Opening an already-running app can move its existing windows. The command operates on all eligible source windows for that app; it is not a single-tab or single-window command. For a dedicated browser window, the skill tells the agent to create that window using its browser tools and move it through the browser’s own Window menu.

## Try the commands directly

From the repository:

```sh
python3 skills/agent-display/scripts/agent_display.py status
python3 skills/agent-display/scripts/agent_display.py launch --app-path "$PWD/build/VirtualDesktop.app"
python3 skills/agent-display/scripts/agent_display.py start
python3 skills/agent-display/scripts/agent_display.py open com.apple.Safari
python3 skills/agent-display/scripts/agent_display.py move com.apple.Safari --to main
python3 skills/agent-display/scripts/agent_display.py apps --on-agent
```

If setup is incomplete, run `python3 skills/agent-display/scripts/agent_display.py setup` and complete the macOS prompts before continuing. `start` waits for a live frame; it does not equate a connected display with a working preview. `open` waits for a movable app window, and returns an error if the app does not create one. Results are JSON, with nonzero exit codes on failure.

Agents normally use the helper’s absolute path so their working directory does not matter. Commands avoid explicitly taking keyboard focus unless `--activate` is supplied. An app may still activate itself when opened or restored.

## How it works

The Python helper talks to the running app through a private Unix socket. The **signed app** performs window operations with its existing Accessibility grant, so each agent does not need a separate window-moving executable approved in System Settings.

The socket is `~/Library/Application Support/AgentDisplay/control.sock`. The app restricts the directory to its owner (0700), the socket to its owner (0600), and checks the connecting process’s user ID. Commands are limited to status, app inventory, preview/display start, setup, opening installed apps by bundle ID, and window movement. There is no TCP listener, shell execution, arbitrary file writing, or remote agent connection in this interface. Any local process running as the same user can issue these commands; normal agent sandbox and approval rules remain in effect.

Read [the skill’s command reference](../skills/agent-display/references/commands.md) for failure codes and recovery. If the menu says **Agent commands unavailable**, its tooltip explains the startup error. A second app instance cannot take over an active control socket.

## Validation

`make test-agent-unit` checks request validation, client orchestration, failed/partial movement handling, installer portability, and protection against overwriting customized skills. `make test-agent` additionally runs the native socket fixture and exchanges real local requests. The fixture never moves your windows or changes permissions.

A live end-to-end check still requires the updated, signed app on the Mac: complete setup, run `start`, open a harmless test app, verify it in the live preview, and move it back. An agent sandbox may prohibit binding or connecting local sockets even when the app and skill are installed. Do not interpret a sandbox-blocked test as a successful live verification.
