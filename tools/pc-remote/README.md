# PC Remote — Windows media controls

Companion for HuaSideload 1.4.0+. Uses the existing Huawei watch Music screen,
without installing a new watch app. The watch must offer the phone-music control
screen and send service `0x25` button/volume events. A running Windows player
decides how standard media keys behave; no player-specific automation is used.

## Use

Use Python 3.9+ on Windows. The delivered PC-Remote folder includes the pure-Python
qrcode 8.2 package and its BSD license under vendor/. For a source checkout,
install requirements.txt into your environment first. Run Start-PC-Remote.vbs,
or run pc_remote.py with Python. The graphical window displays the local endpoint
and a pairing QR. Close the window to stop; it does not install a startup task.

Keep iPhone and PC on the same LAN. In HuaSideload, open Utilities / Tiện ích →
Điều khiển PC → Quét mã QR trên PC. Allow Camera and Local Network if iOS asks.
The app validates the endpoint and checks a signed ping before controls can be
enabled. Test with the iPhone buttons, then open Music on the watch and choose
phone music control. Play/pause, previous, next and volume are mapped to Windows
media keys. Mute is also available on the iPhone control page.

If Windows requests network access for Python, the user must handle that prompt.
No firewall or Windows security settings are changed by this program. If several
local addresses exist, choose the PC address reachable from the iPhone before
starting the receiver. A public IPv4, loopback or wildcard bind is rejected.

The watch playback icon and volume slider are estimates. This first version
acknowledges Windows accepting the key events; it does not read the current song,
actual playback state or system volume. Lock-screen/background watch-to-PC behavior
needs a physical iPhone/watch trial. Do not force-quit the iPhone companion.

## Pairing and protocol

The persistent random 256-bit key stays in .private/pairing-key.txt on the PC and
in the iPhone Keychain. Do not publish the key or its pairing QR. No real key is
included in source, tests, or the distributable ZIP. Keep .private/ out of backups
you intend to publish. Existing keys are not regenerated on restart.

Each TCP connection carries a 4-byte big-endian length and one JSON request, with
a maximum of 2048 bytes. Requests contain v, id (lowercase UUID), ts (Unix seconds),
command and signature. HMAC-SHA256 request input:

```
HN-PC-1\n{id}\n{ts}\n{command}
```

Replies contain v, id, ok, code and signature, authenticated over:

```
HN-PC-1-REPLY\n{id}\n{ok as 0 or 1}\n{code}
```

Only ping, play_pause, previous, next, volume_up, volume_down and mute exist.
Requests outside a ±120-second clock window are rejected. Request IDs and results
are cached for 300 seconds under a lock; a repeated ID never executes a key twice.
At most 8 connections are handled concurrently, with bounded frame size and time.
The iPhone serializes requests, expires old queued media events, cancels on mode
disable/disconnect, and does not automatically retry a potentially executed toggle.

This is a local, signed control protocol, not encrypted desktop access: media
commands and replies are visible to a network observer. The pairing key is not
transmitted with commands. There is no shell execution, screen capture, filesystem
access, port forwarding or internet listener.

## Validation

Run `python -m unittest discover -s tools/pc-remote -p test_pc_remote.py -v` from
the repository root. The Windows ABI test replaces SendInput before invoking any
key; socket tests bind loopback with a fake executor. The public JSON vector in
Tests/HuaSideloadParsingTests/Fixtures/pc-remote-v1.json is shared with Swift tests.

References: [Windows media key codes](https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes),
[SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput),
[Apple local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy),
[qrcode 8.2](https://pypi.org/project/qrcode/8.2/).
