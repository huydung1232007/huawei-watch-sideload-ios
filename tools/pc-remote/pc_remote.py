"""HuaSideload PC Remote: authenticated LAN media keys, Windows + Python 3.9+.

Wire: 4-byte big-endian length, then UTF-8 JSON (at most 2048 bytes).
Requests and replies are HMAC-SHA256 signed. The key is only in the pairing QR.
Only fixed media commands are supported; no shell, file or desktop access.
"""
from __future__ import annotations

import ctypes
from ctypes import wintypes
import hashlib
import hmac
import ipaddress
import json
from pathlib import Path
import queue
import re
import secrets
import socket
import socketserver
import struct
import sys
import threading
import time
import uuid

VERSION = "1.0.0"
PORT = 39767
MAX_FRAME = 2048
MEDIA_KEYS = {"play_pause": 0xB3, "previous": 0xB1, "next": 0xB0,
              "volume_up": 0xAF, "volume_down": 0xAE, "mute": 0xAD}
TITLES = {"ping": "iPhone đã kết nối", "play_pause": "Phát / tạm dừng", "previous": "Bài trước",
          "next": "Bài tiếp", "volume_up": "Tăng âm lượng", "volume_down": "Giảm âm lượng", "mute": "Bật / tắt tiếng"}
LAN_RANGES = tuple(ipaddress.ip_network(s) for s in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))


def is_lan(host):
    try:
        value = ipaddress.IPv4Address(host)
        return any(value in network for network in LAN_RANGES)
    except ipaddress.AddressValueError:
        return False


def mac(text, key):
    return hmac.new(key, text.encode("utf-8"), hashlib.sha256).hexdigest()


def signed_request(command, key, request_id=None, timestamp=None):
    request_id = request_id or str(uuid.uuid4())
    timestamp = int(time.time()) if timestamp is None else timestamp
    return {"v": 1, "id": request_id, "ts": timestamp, "command": command,
            "signature": mac(f"HN-PC-1\n{request_id}\n{timestamp}\n{command}", key)}


def frame(data):
    raw = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if not 1 <= len(raw) <= MAX_FRAME:
        raise ValueError("Invalid frame size")
    return struct.pack(">I", len(raw)) + raw


def receive_exact(stream, count):
    data = bytearray()
    while len(data) < count:
        part = stream.recv(count - len(data))
        if not part:
            raise ConnectionError("Connection closed")
        data.extend(part)
    return bytes(data)


def receive_frame(stream):
    count, = struct.unpack(">I", receive_exact(stream, 4))
    if not 1 <= count <= MAX_FRAME:
        raise ValueError("Invalid frame size")
    return json.loads(receive_exact(stream, count))


class MediaExecutor:
    """SendInput structures include the complete union, including mouse input.
    sizeof(INPUT) must be 40 on 64-bit Windows and 28 on 32-bit Windows.
    """
    class MouseInput(ctypes.Structure):
        _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG), ("mouseData", wintypes.DWORD),
                    ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t)]

    class KeyboardInput(ctypes.Structure):
        _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD),
                    ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t)]

    def __init__(self):
        if sys.platform != "win32":
            raise RuntimeError("Chương trình này điều khiển Windows.")

        class InputUnion(ctypes.Union):
            _fields_ = [("mi", MediaExecutor.MouseInput), ("ki", MediaExecutor.KeyboardInput)]

        class Input(ctypes.Structure):
            _fields_ = [("type", wintypes.DWORD), ("value", InputUnion)]

        self.Input = Input
        expected = 40 if ctypes.sizeof(ctypes.c_void_p) == 8 else 28
        if ctypes.sizeof(Input) != expected:
            raise RuntimeError("Cấu trúc SendInput không tương thích Windows.")
        self.send_input = ctypes.WinDLL("user32", use_last_error=True).SendInput
        self.send_input.argtypes = (wintypes.UINT, ctypes.POINTER(Input), ctypes.c_int)
        self.send_input.restype = wintypes.UINT

    def __call__(self, command):
        key = MEDIA_KEYS[command]
        inputs = (self.Input * 2)()
        for index, flag in enumerate((0, 2)):  # key down, key up
            inputs[index].type = 1
            inputs[index].value.ki = self.KeyboardInput(key, 0, flag, 0, 0)
        if self.send_input(2, inputs, ctypes.sizeof(self.Input)) != 2:
            raise OSError("Windows did not accept both key events")


class Controller:
    def __init__(self, key, execute, report=lambda text: None, clock=time.time):
        if len(key) != 32:
            raise ValueError("Expected a 256-bit pairing key")
        self.key = key
        self.execute = execute
        self.report = report
        self.clock = clock
        self.enabled = True
        self.lock = threading.Lock()
        self.recent = {}

    def reply(self, request_id, ok, code):
        return {"v": 1, "id": request_id, "ok": ok, "code": code,
                "signature": mac(f"HN-PC-1-REPLY\n{request_id}\n{int(ok)}\n{code}", self.key)}

    def handle(self, request):
        if not isinstance(request, dict):
            return self.reply("", False, "bad_request")
        rid, ts, command = request.get("id"), request.get("ts"), request.get("command")
        signature = request.get("signature")
        if (type(request.get("v")) is not int or request["v"] != 1 or not isinstance(rid, str)
                or not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", rid)
                or type(ts) is not int or not isinstance(command, str) or command not in {"ping", *MEDIA_KEYS}
                or not isinstance(signature, str) or not re.fullmatch(r"[0-9a-f]{64}", signature)):
            return self.reply("", False, "bad_request")
        expected = mac(f"HN-PC-1\n{rid}\n{ts}\n{command}", self.key)
        if not hmac.compare_digest(signature, expected):
            return self.reply(rid, False, "auth")
        now = self.clock()
        if abs(now - ts) > 120:
            return self.reply(rid, False, "stale")
        # A duplicate request must return its original result, never press again.
        with self.lock:
            self.recent = {i: value for i, value in self.recent.items() if now - value[0] < 300}
            if rid in self.recent:
                _, old_signature, response = self.recent[rid]
                return response if old_signature == signature else self.reply(rid, False, "duplicate_conflict")
            if len(self.recent) >= 1024:
                return self.reply(rid, False, "busy")
            if command != "ping" and not self.enabled:
                result = self.reply(rid, False, "paused")
            else:
                try:
                    if command != "ping":
                        self.execute(command)
                    result = self.reply(rid, True, "ok")
                    self.report(TITLES[command])
                except Exception:
                    result = self.reply(rid, False, "input_failed")
                    self.report("Windows chưa nhận được phím điều khiển")
            self.recent[rid] = (now, signature, result)
            return result


class RemoteServer(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 8

    def __init__(self, address, controller, allow_loopback=False):
        if not is_lan(address[0]) and not (allow_loopback and address[0] == "127.0.0.1"):
            raise ValueError("Chỉ nhận kết nối trên địa chỉ IPv4 trong mạng LAN.")
        self.controller = controller
        self.slots = threading.BoundedSemaphore(8)
        super().__init__(address, RemoteHandler)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()

    def handle_error(self, request, client_address):
        pass  # Never log arbitrary received data or credentials.


class RemoteHandler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(5)
        try:
            data = receive_frame(self.request)
            result = self.server.controller.handle(data)
            self.request.sendall(frame(result))
        except (ValueError, UnicodeError, OSError, ConnectionError):
            return


def local_addresses():
    try:
        return sorted({i[4][0] for i in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET, socket.SOCK_STREAM)
                       if is_lan(i[4][0])})
    except OSError:
        return []


def load_key(folder):
    folder.mkdir(parents=True, exist_ok=True)
    file = folder / "pairing-key.txt"
    if file.exists():
        value = file.read_text(encoding="ascii").strip()
        if not re.fullmatch(r"[0-9a-f]{64}", value):
            raise ValueError("Tệp mã kết nối không hợp lệ. Không tự thay mã đã lưu.")
        return bytes.fromhex(value)
    value = secrets.token_hex(32)
    with file.open("x", encoding="ascii") as output:
        output.write(value)
    return bytes.fromhex(value)


def run_gui():
    import tkinter as tk
    from tkinter import ttk, messagebox
    sys.path.insert(0, str(Path(__file__).resolve().parent / "vendor"))
    try:
        import qrcode
    except ImportError:
        messagebox.showerror("PC Remote", "Thiếu thư viện QR. Hãy giải nén đầy đủ bộ PC Remote có thư mục vendor.")
        return

    root = tk.Tk(); root.title("HuaSideload · PC Remote")
    root.geometry("760x600"); root.minsize(720, 560); root.configure(bg="#101827")
    style = ttk.Style(root); style.theme_use("clam")
    style.configure("TButton", font=("Segoe UI", 11), padding=10)
    style.configure("TCheckbutton", background="#101827", foreground="#e2e8f0", font=("Segoe UI", 11))
    style.map("TCheckbutton", background=[("active", "#101827")], foreground=[("active", "#ffffff")])
    tk.Label(root, text="PC Remote", font=("Segoe UI", 26, "bold"), fg="white", bg="#101827").pack(anchor="w", padx=28, pady=(22, 2))
    tk.Label(root, text="Nhạc và video · iPhone → Windows", font=("Segoe UI", 12), fg="#9baec6", bg="#101827").pack(anchor="w", padx=30)
    status = tk.StringVar(value="Chọn địa chỉ mạng rồi bấm Bắt đầu")
    tk.Label(root, textvariable=status, font=("Segoe UI", 11), fg="#5eead4", bg="#101827", wraplength=690, justify="left").pack(anchor="w", padx=30, pady=14)
    body = tk.Frame(root, bg="#101827"); body.pack(fill="both", expand=True, padx=28)
    qr = tk.Canvas(body, width=286, height=286, bg="white", highlightthickness=0); qr.pack(side="left", anchor="n")
    right = tk.Frame(body, bg="#101827"); right.pack(side="left", fill="both", expand=True, padx=(24, 0))
    tk.Label(right, text="1. Cùng mạng Wi-Fi/LAN\n2. iPhone → Tiện ích → Điều khiển PC\n3. Quét mã QR bên trái\n4. Kiểm tra và bật điều khiển", font=("Segoe UI", 11), fg="#e2e8f0", bg="#101827", justify="left", anchor="w").pack(anchor="w", pady=(4, 14))
    addresses = local_addresses(); host = tk.StringVar(value=addresses[0] if addresses else "")
    ttk.Combobox(right, textvariable=host, values=addresses, width=25, font=("Segoe UI", 11)).pack(fill="x", pady=4)
    incoming = queue.Queue(); controller = None; server = None; config = ""
    allowed = tk.BooleanVar(value=True)
    log = tk.Text(root, height=7, bg="#1b2739", fg="#c9d7e9", font=("Segoe UI", 10), relief="flat", state="disabled", padx=12, pady=10)
    log.pack(fill="x", padx=28, pady=(16, 22))

    def allow():
        if controller:
            with controller.lock:
                controller.enabled = allowed.get()
        incoming.put("Đã bật điều khiển" if allowed.get() else "Đã tạm dừng điều khiển")

    def stop():
        nonlocal server, config
        if controller:
            with controller.lock:
                controller.enabled = False
        if server:
            old = server; server = None
            threading.Thread(target=lambda: (old.shutdown(), old.server_close()), daemon=True).start()
        config = ""; qr.delete("all"); status.set("Đã dừng nhận điều khiển từ iPhone")

    def start():
        nonlocal server, controller, config
        if server:
            status.set("Đang chạy. Bấm Dừng trước nếu muốn đổi địa chỉ mạng."); return
        try:
            address = host.get().strip()
            if not is_lan(address):
                raise ValueError("Chọn IPv4 của PC trong mạng LAN, ví dụ 192.168.1.10.")
            key = load_key(Path(__file__).resolve().parent / ".private")
            controller = Controller(key, MediaExecutor(), report=incoming.put)
            controller.enabled = allowed.get()
            server = RemoteServer((address, PORT), controller)
            config = json.dumps({"v": 1, "host": address, "port": PORT, "key": key.hex()}, separators=(",", ":"))
            matrix = qrcode.QRCode(border=4); matrix.add_data(config); matrix.make(fit=True)
            cells = matrix.get_matrix(); scale = max(1, 286 // len(cells)); extent = len(cells) * scale; offset = (286 - extent) // 2
            qr.delete("all")
            for y, row in enumerate(cells):
                for x, black in enumerate(row):
                    if black:
                        qr.create_rectangle(offset+x*scale, offset+y*scale, offset+(x+1)*scale, offset+(y+1)*scale, fill="black", outline="")
            threading.Thread(target=server.serve_forever, daemon=True).start()
            status.set(f"Sẵn sàng tại {address}:{PORT} · Quét QR bằng iPhone")
            incoming.put("Đã mở bộ nhận lệnh media. Đóng cửa sổ để dừng.")
        except Exception as error:
            if server:
                server.server_close(); server = None
            config = ""; status.set(str(error))

    def copy():
        if config:
            root.clipboard_clear(); root.clipboard_append(config)
            status.set("Đã sao chép mã kết nối. Có thể chuyển mã riêng sang iPhone; quét QR là cách nhanh nhất.")

    ttk.Button(right, text="Bắt đầu", command=start).pack(fill="x", pady=4)
    ttk.Button(right, text="Sao chép mã kết nối", command=copy).pack(fill="x", pady=4)
    ttk.Checkbutton(right, text="Cho phép điều khiển", variable=allowed, command=allow).pack(anchor="w", pady=8)
    ttk.Button(right, text="Dừng", command=stop).pack(fill="x", pady=4)

    def drain():
        while not incoming.empty():
            text = incoming.get_nowait(); log.configure(state="normal")
            log.insert("end", time.strftime("%H:%M:%S") + "  " + text + "\n")
            if int(log.index("end-1c").split(".")[0]) > 80:
                log.delete("1.0", "2.0")
            log.see("end"); log.configure(state="disabled")
        root.after(150, drain)

    def close():
        stop(); root.destroy()

    root.protocol("WM_DELETE_WINDOW", close); root.after(150, drain)
    if addresses:
        root.after(250, start)
    root.mainloop()


if __name__ == "__main__":
    run_gui()
