import ctypes
import hashlib
import hmac
import json
from pathlib import Path
import socket
import struct
import sys
import threading
import unittest
import pc_remote as remote

KEY = bytes(range(32))  # Public, synthetic fixture only.
NOW = 1800000000
RID = "12345678-1234-4234-8234-123456789abc"


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.actions = []
        self.controller = remote.Controller(KEY, self.actions.append, clock=lambda: NOW)

    def request(self, command="play_pause", **kwargs):
        return remote.signed_request(command, KEY, request_id=kwargs.get("id", RID), timestamp=kwargs.get("ts", NOW))

    def test_cross_language_fixture(self):
        fixture = json.loads((Path(__file__).parents[2] / "Tests/HuaSideloadParsingTests/Fixtures/pc-remote-v1.json").read_text())
        self.assertEqual(self.request(), fixture["request"])
        response = self.controller.handle(fixture["request"])
        self.assertEqual(response, fixture["reply"])
        self.assertEqual(self.actions, ["play_pause"])

    def test_each_media_action_and_ping(self):
        for command in ("ping", *remote.MEDIA_KEYS):
            response = self.controller.handle(remote.signed_request(command, KEY, timestamp=NOW))
            self.assertTrue(response["ok"])
            message = f"HN-PC-1-REPLY\n{response['id']}\n1\nok".encode()
            self.assertEqual(response["signature"], hmac.new(KEY, message, hashlib.sha256).hexdigest())
        self.assertEqual(self.actions, list(remote.MEDIA_KEYS))

    def test_wrong_key_and_modified_command_never_press(self):
        wrong = remote.signed_request("next", b"x" * 32, timestamp=NOW)
        changed = self.request(); changed["command"] = "mute"
        for request in (wrong, changed):
            self.assertEqual(self.controller.handle(request)["code"], "auth")
        self.assertEqual(self.actions, [])

    def test_duplicate_is_acknowledged_without_second_toggle(self):
        request = self.request()
        first = self.controller.handle(request)
        self.assertEqual(first, self.controller.handle(request))
        self.assertEqual(self.actions, ["play_pause"])

    def test_simultaneous_duplicate_only_executes_once(self):
        request = self.request()
        threads = [threading.Thread(target=lambda: self.controller.handle(request)) for _ in range(12)]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
        self.assertEqual(self.actions, ["play_pause"])

    def test_duplicate_id_with_changed_signed_content_is_rejected(self):
        self.controller.handle(self.request())
        self.assertEqual(self.controller.handle(self.request("mute"))["code"], "duplicate_conflict")
        self.assertEqual(self.actions, ["play_pause"])

    def test_old_and_future_requests_are_rejected(self):
        for timestamp in (NOW - 121, NOW + 121):
            self.assertEqual(self.controller.handle(self.request(ts=timestamp))["code"], "stale")
        self.assertEqual(self.actions, [])

    def test_paused_allows_connectivity_check_but_no_keys(self):
        self.controller.enabled = False
        self.assertTrue(self.controller.handle(self.request("ping"))["ok"])
        self.assertEqual(self.controller.handle(self.request("next", id="22345678-1234-4234-8234-123456789abc"))["code"], "paused")
        self.assertEqual(self.actions, [])

    def test_bad_types_and_unknown_commands_do_not_execute(self):
        for value in ([], None, {}, self.request("shutdown"), dict(self.request(), ts=True), dict(self.request(), v=True)):
            self.assertEqual(self.controller.handle(value)["code"], "bad_request")
        self.assertEqual(self.actions, [])

    def test_input_failure_is_not_retried(self):
        def fail(_): raise OSError("synthetic failure")
        self.controller.execute = fail
        self.assertEqual(self.controller.handle(self.request())["code"], "input_failed")
        self.controller.execute = self.actions.append
        self.assertEqual(self.controller.handle(self.request())["code"], "input_failed")
        self.assertEqual(self.actions, [])

    def test_restrict_bind_addresses(self):
        for value in ("0.0.0.0", "127.0.0.1", "8.8.8.8", "192.168.01.2", "localhost", "::1"):
            self.assertFalse(remote.is_lan(value))
        for value in ("10.0.0.2", "172.16.0.1", "172.31.255.1", "192.168.1.2"):
            self.assertTrue(remote.is_lan(value))

    @unittest.skipUnless(sys.platform == "win32", "Windows input ABI")
    def test_windows_input_layout_without_sending_keys(self):
        executor = remote.MediaExecutor()
        self.assertEqual(ctypes.sizeof(executor.Input), 40 if ctypes.sizeof(ctypes.c_void_p) == 8 else 28)
        captured = []
        def record(count, values, size):
            captured.append((count, [(v.type, v.value.ki.wVk, v.value.ki.dwFlags) for v in values], size)); return 2
        executor.send_input = record
        for command, code in remote.MEDIA_KEYS.items():
            executor(command)
            self.assertEqual(captured[-1][1], [(1, code, 0), (1, code, 2)])


class SocketTests(unittest.TestCase):
    def setUp(self):
        self.actions = []
        self.server = remote.RemoteServer(("127.0.0.1", 0), remote.Controller(KEY, self.actions.append), allow_loopback=True)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()

    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(2)

    def test_fragmented_frame_and_reply(self):
        request = remote.signed_request("next", KEY)
        with socket.create_connection(self.server.server_address, timeout=2) as stream:
            data = remote.frame(request)
            for index in range(0, len(data), 3): stream.sendall(data[index:index+3])
            response = remote.receive_frame(stream)
        self.assertEqual((response["id"], response["ok"]), (request["id"], True))
        self.assertEqual(self.actions, ["next"])

    def test_oversized_frame_closes_connection_without_action(self):
        with socket.create_connection(self.server.server_address, timeout=2) as stream:
            stream.sendall(struct.pack(">I", remote.MAX_FRAME + 1))
            self.assertEqual(stream.recv(1), b"")
        self.assertEqual(self.actions, [])


if __name__ == "__main__":
    unittest.main()
