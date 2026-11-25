#!/usr/bin/env python3
"""Local Agent Display client. Python standard library only; no agent SDK."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import socket
import stat
import subprocess
import sys
import time

BUNDLE_ID = "io.github.guglielmofonda.virtual-desktop"
DEFAULT_SOCKET = Path.home() / "Library/Application Support/AgentDisplay/control.sock"


def error(code, message, **details):
    return {"ok": False, "error": {"code": code, "message": message}, **details}


def request(path, command, **arguments):
    try:
        parent, endpoint = path.parent.lstat(), path.lstat()
        if (not stat.S_ISDIR(parent.st_mode) or parent.st_uid != os.getuid()
                or parent.st_mode & 0o077 or not stat.S_ISSOCK(endpoint.st_mode)
                or endpoint.st_uid != os.getuid() or endpoint.st_mode & 0o077):
            return error("unsafe_socket", "Refusing a socket that is not private and owned by this user.")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(35)
            client.connect(str(path))
            payload = {"version": 1, "command": command, **arguments}
            client.sendall(json.dumps(payload).encode() + b"\n")
            data = bytearray()
            deadline = time.monotonic() + 35
            while b"\n" not in data and len(data) <= 1024 * 1024:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("Response deadline exceeded")
                client.settimeout(remaining)
                chunk = client.recv(65536)
                if not chunk:
                    break
                data.extend(chunk)
        if len(data) > 1024 * 1024 or b"\n" not in data:
            return error("invalid_response", "The app returned an incomplete or oversized response.")
        result = json.loads(bytes(data).split(b"\n", 1)[0])
        if not isinstance(result, dict) or type(result.get("ok")) is not bool:
            return error("invalid_response", "The app returned an unexpected response.")
        return result
    except (FileNotFoundError, ConnectionRefusedError):
        return error("app_unavailable", "Open Agent Display 0.5.0 or newer on this Mac. Use launch --app-path with the existing signed app; do not rebuild just to retry a connection.")
    except PermissionError:
        return error("access_denied", "This agent cannot access the local app socket. Use a local session with access to the signed-in Mac; do not bypass its sandbox.")
    except (TimeoutError, socket.timeout):
        return error("command_timeout", "The command timed out. Check status before retrying; a window may already have moved.")
    except (OSError, ValueError) as exc:
        return error("connection_failed", str(exc))


def wait_live(path, timeout):
    deadline = time.monotonic() + timeout
    result = request(path, "status")
    while result.get("ok") and not (result.get("display_running") and result.get("preview_live")):
        if not result.get("permissions", {}).get("screen_recording"):
            return error("permission_required", "Screen Recording is required for the live preview. Open setup.", status=result)
        if time.monotonic() >= deadline:
            return error("preview_not_live", "The preview has not become live. Inspect status and the app’s setup guide before continuing.", status=result)
        time.sleep(0.25)
        result = request(path, "status")
    return result


def open_and_move(path, app, destination, activate, timeout):
    opened = request(path, "open", app=app, activate=activate)
    if not opened.get("ok"):
        return opened
    deadline = time.monotonic() + timeout
    while True:
        moved = request(path, "move", app=opened.get("app", app), destination=destination, activate=activate)
        # Retry only confirmed absence of windows, not partial moves/timeouts.
        if moved.get("ok") or moved.get("error", {}).get("code") != "no_windows":
            return {**moved, "opened": True}
        if time.monotonic() >= deadline:
            return error("no_windows", "The app opened but did not expose a movable window. Create a window in the app, then use move. Opening does not promise a new window for an already-running app.", opened=True, app=app)
        time.sleep(0.25)


def find_app(explicit=None):
    if explicit:
        return Path(explicit).expanduser()
    if os.environ.get("AGENT_DISPLAY_APP"):
        return Path(os.environ["AGENT_DISPLAY_APP"]).expanduser()
    candidates = [Path(__file__).resolve().parents[3] / "build/VirtualDesktop.app"]
    for folder in [Path("/Applications"), Path.home() / "Applications"]:
        candidates.extend(folder / name for name in ["VirtualDesktop.app", "Virtual Desktop.app", "Agent Display.app"])
    existing = list(dict.fromkeys(p.resolve() for p in candidates if p.exists()))
    return existing[0] if len(existing) == 1 else None


def launch(path, explicit, timeout):
    current = request(path, "status")
    if current.get("ok"):
        return current
    if current.get("error", {}).get("code") != "app_unavailable":
        return current
    app = find_app(explicit)
    if app is None:
        return error("app_path_required", "Pass launch --app-path /path/to/VirtualDesktop.app to select the existing signed installation.")
    try:
        with (app / "Contents/Info.plist").open("rb") as file:
            info = plistlib.load(file)
        if not isinstance(info, dict) or info.get("CFBundleIdentifier") != BUNDLE_ID:
            return error("invalid_app", "That bundle is not Agent Display.")
        if int(info.get("CFBundleVersion", 0)) < 5:
            return error("update_required", "This installation predates agent commands. Update to 0.5.0+ using the same signing identity, then retry.")
        subprocess.run(["/usr/bin/open", "-g", str(app)], check=True, capture_output=True, timeout=10)
    except (OSError, ValueError, TypeError, plistlib.InvalidFileException, subprocess.SubprocessError) as exc:
        return error("launch_failed", str(exc))
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = request(path, "status")
        if result.get("ok") or result.get("error", {}).get("code") != "app_unavailable":
            return result
        time.sleep(0.25)
    return error("launch_timeout", "The app opened but its command interface did not respond. Check the menu bar for Agent commands unavailable, and confirm you opened version 0.5.0+.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", type=Path, default=DEFAULT_SOCKET, help="Private local socket (normally leave unchanged)")
    parser.add_argument("--timeout", type=float, default=20, help="Seconds to wait for preview or app windows (1–60)")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ["status", "start", "show", "hide", "setup"]:
        commands.add_parser(name)
    apps = commands.add_parser("apps")
    apps.add_argument("--on-agent", action="store_true")
    launcher = commands.add_parser("launch")
    launcher.add_argument("--app-path")
    for name in ["open", "move"]:
        command = commands.add_parser(name)
        command.add_argument("app", help="Bundle ID, such as com.apple.Safari")
        command.add_argument("--to", choices=["agent", "main"], default="agent")
        command.add_argument("--activate", action="store_true", help="Explicitly bring the app to the foreground")
    args = parser.parse_args(argv)
    if not 1 <= args.timeout <= 60:
        parser.error("--timeout must be between 1 and 60 seconds")
    if sys.platform != "darwin":
        result = error("mac_required", "Run this skill on the signed-in Mac, not in a remote Linux or cloud sandbox.")
    elif args.command == "launch":
        result = launch(args.socket, args.app_path, args.timeout)
    elif args.command == "open":
        result = open_and_move(args.socket, args.app, args.to, args.activate, args.timeout)
    elif args.command == "move":
        result = request(args.socket, "move", app=args.app, destination=args.to, activate=args.activate)
    else:
        result = request(args.socket, args.command)
        if result.get("ok") and args.command in ["start", "show"]:
            result = wait_live(args.socket, args.timeout)
        elif result.get("ok") and args.command == "apps" and args.on_agent:
            if not result.get("display_inventory_available"):
                result = error("permission_required", "Screen access is needed to identify apps on Agent Display.")
            else:
                result["apps"] = [app for app in result["apps"] if app["on_agent_display"]]
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
