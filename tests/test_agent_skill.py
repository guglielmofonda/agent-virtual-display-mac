import importlib.util
import json
import os
from pathlib import Path
import plistlib
import socket
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "skills/agent-display/scripts/agent_display.py"
INSTALLER = ROOT / "tools/install-skill.py"
FIXTURE = ROOT / "build/AgentServerFixture"
spec = importlib.util.spec_from_file_location("agent_display", SCRIPT)
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


class AgentTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="ad-tests-", dir="/tmp")
        cls.directory = Path(cls.temp.name)
        cls.path = cls.directory / "control.sock"
        cls.server = subprocess.Popen([str(FIXTURE), str(cls.directory)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if cls.server.stdout.readline().strip() != "READY":
            _, details = cls.server.communicate(timeout=5)
            cls.temp.cleanup()
            raise RuntimeError(details)

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.communicate(timeout=5)
        cls.temp.cleanup()

    def cli(self, *args):
        run = subprocess.run([sys.executable, str(SCRIPT), "--socket", str(self.path), *args], cwd="/tmp", capture_output=True, text=True, timeout=40)
        return run.returncode, json.loads(run.stdout)

    def raw(self, data):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(5)
            sock.connect(str(self.path))
            sock.sendall(data)
            return json.loads(sock.makefile("rb").readline())

    def test_status_and_private_socket(self):
        code, data = self.cli("status")
        self.assertEqual(code, 0)
        self.assertTrue(data["preview_live"])
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.directory.stat().st_mode), 0o700)

    def test_open_waits_for_window_without_activating(self):
        code, data = self.cli("open", "test.delayed")
        self.assertEqual(code, 0)
        self.assertEqual(data["moved_windows"], 1)
        self.assertFalse(data["activate"])
        self.assertEqual(client.request(self.path, "status")["moves"]["test.delayed"], 2)

    def test_partial_move_is_not_retried(self):
        code, data = self.cli("open", "test.partial")
        self.assertEqual(code, 1)
        self.assertEqual(data["moved_windows"], 1)
        self.assertEqual(client.request(self.path, "status")["moves"]["test.partial"], 1)

    def test_permission_denial_and_return_to_main(self):
        code, data = self.cli("move", "test.denied")
        self.assertEqual((code, data["error"]["code"]), (1, "permission_required"))
        code, data = self.cli("move", "test.normal", "--to", "main", "--activate")
        self.assertEqual((code, data["destination"], data["activate"]), (0, "main", True))

    def test_apps_filter(self):
        code, data = self.cli("apps", "--on-agent")
        self.assertEqual(code, 0)
        self.assertEqual([app["bundle_id"] for app in data["apps"]], ["test.agent"])

    def test_invalid_requests_do_not_reach_handler(self):
        for payload in [b"[]\n", b"broken\n", b"x" * 4100 + b"\n", b'{"version":1,"command":"quit"}\n',
                        b'{"version":1,"command":"open","app":"$(touch x)"}\n',
                        b'{"version":1,"command":"move","app":"test.normal","activate":"yes"}\n',
                        b'{"version":1,"command":"status","output_path":"/tmp/x"}\n']:
            with self.subTest(payload=payload[:90]):
                self.assertEqual(self.raw(payload)["error"]["code"], "invalid_request")

    def test_second_server_preserves_first(self):
        run = subprocess.run([str(FIXTURE), str(self.directory)], capture_output=True, timeout=5)
        self.assertEqual(run.returncode, 1)
        self.assertTrue(client.request(self.path, "status")["ok"])

    def test_launch_rejects_old_bundle_without_opening_it(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            app = Path(temp) / "Old App.app"
            (app / "Contents").mkdir(parents=True)
            with (app / "Contents/Info.plist").open("wb") as file:
                plistlib.dump({"CFBundleIdentifier": client.BUNDLE_ID, "CFBundleVersion": "4"}, file)
            with mock.patch.object(client.subprocess, "run") as launch:
                result = client.launch(Path(temp) / "missing.sock", str(app), 1)
                self.assertEqual(result["error"]["code"], "update_required")
                launch.assert_not_called()


class AgentClientTests(unittest.TestCase):
    def test_open_waits_for_window_and_preserves_focus(self):
        responses = [{"ok": True, "app": "com.apple.Safari"},
                     client.error("no_windows", "wait"), {"ok": True, "moved_windows": 1}]
        with mock.patch.object(client, "request", side_effect=responses) as send, mock.patch.object(client.time, "sleep"):
            result = client.open_and_move(Path("unused"), "com.apple.Safari", "agent", False, 20)
        self.assertTrue(result["ok"])
        self.assertTrue(result["opened"])
        self.assertEqual(send.call_count, 3)
        self.assertEqual(send.call_args.kwargs, {"app": "com.apple.Safari", "destination": "agent", "activate": False})

    def test_partial_move_or_timeout_is_never_retried(self):
        for code in ["move_failed", "command_timeout", "permission_required"]:
            with self.subTest(code=code), mock.patch.object(client, "request", side_effect=[{"ok": True}, client.error(code, "test", moved_windows=1)]) as send:
                result = client.open_and_move(Path("unused"), "test.app", "main", False, 20)
            self.assertFalse(result["ok"])
            self.assertEqual(result["moved_windows"], 1)
            self.assertEqual(send.call_count, 2)

    def test_permission_denied_before_launch_does_not_move(self):
        with mock.patch.object(client, "request", return_value=client.error("permission_required", "test")) as send:
            self.assertFalse(client.open_and_move(Path("unused"), "test.app", "agent", False, 20)["ok"])
        self.assertEqual(send.call_count, 1)

    def test_start_requires_actual_live_preview(self):
        pending = {"ok": True, "display_running": True, "preview_live": False, "permissions": {"screen_recording": True}}
        live = {**pending, "preview_live": True}
        with mock.patch.object(client, "request", side_effect=[pending, live]), mock.patch.object(client.time, "sleep"):
            self.assertTrue(client.wait_live(Path("unused"), 20)["preview_live"])
        with mock.patch.object(client, "request", return_value=pending), mock.patch.object(client.time, "monotonic", side_effect=[0, 21]):
            self.assertEqual(client.wait_live(Path("unused"), 20)["error"]["code"], "preview_not_live")

    def test_open_without_window_reports_failure(self):
        with mock.patch.object(client, "request", side_effect=[{"ok": True}, client.error("no_windows", "test")]), mock.patch.object(client.time, "monotonic", side_effect=[0, 21]):
            result = client.open_and_move(Path("unused"), "test.app", "agent", False, 20)
        self.assertFalse(result["ok"])
        self.assertTrue(result["opened"])

    def test_old_app_is_not_launched_or_resigned(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            app = Path(temp) / "Old App.app"
            (app / "Contents").mkdir(parents=True)
            with (app / "Contents/Info.plist").open("wb") as file:
                plistlib.dump({"CFBundleIdentifier": client.BUNDLE_ID, "CFBundleVersion": "4"}, file)
            with mock.patch.object(client.subprocess, "run") as launch:
                self.assertEqual(client.launch(Path(temp) / "missing.sock", str(app), 1)["error"]["code"], "update_required")
                launch.assert_not_called()


class AgentSafetyTests(unittest.TestCase):
    def test_refuse_symlink_and_public_directory(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            directory = Path(temp)
            target = directory / "untouched"
            target.write_text("keep")
            (directory / "control.sock").symlink_to(target)
            run = subprocess.run([str(FIXTURE), temp], capture_output=True, timeout=5)
            self.assertEqual(run.returncode, 1)
            self.assertEqual(target.read_text(), "keep")
            self.assertTrue((directory / "control.sock").is_symlink())
            (directory / "control.sock").unlink()
            directory.chmod(0o755)
            run = subprocess.run([str(FIXTURE), temp], capture_output=True, timeout=5)
            self.assertEqual(run.returncode, 1)
            self.assertFalse((directory / "control.sock").exists())

    def test_closed_socket_reports_unavailable(self):
        with tempfile.TemporaryDirectory(dir="/tmp") as temp:
            self.assertEqual(client.request(Path(temp) / "missing.sock", "status")["error"]["code"], "app_unavailable")

    def test_install_both_agents_from_other_directory(self):
        with tempfile.TemporaryDirectory(prefix="agent project ", dir="/tmp") as temp:
            args = [sys.executable, str(INSTALLER), "--scope", "project", "--project", temp]
            first = subprocess.run(args, cwd="/tmp", capture_output=True, text=True)
            self.assertEqual(first.returncode, 0, first.stderr)
            for folder in [".agents", ".claude"]:
                skill = Path(temp) / folder / "skills/agent-display"
                self.assertTrue((skill / "SKILL.md").is_file())
                self.assertEqual((skill / "scripts/agent_display.py").read_bytes(), SCRIPT.read_bytes())
                self.assertTrue((skill / "references/commands.md").is_file())
            again = subprocess.run(args, capture_output=True, text=True)
            self.assertEqual(again.returncode, 0, again.stderr)
            skill_file = Path(temp) / ".agents/skills/agent-display/SKILL.md"
            skill_file.write_text("user customization")
            blocked = subprocess.run(args, capture_output=True, text=True)
            self.assertEqual(blocked.returncode, 1)
            self.assertEqual(skill_file.read_text(), "user customization")


if __name__ == "__main__":
    unittest.main()
