#!/usr/bin/env python3
"""自测工具：模拟一个 VNC 客户端连到本机中继端口，移动指针 + 右键点击。

用来判断"是本机注入链路坏了，还是上游客户端的问题"（绕过手机 / UU 客户端）。
端点与坐标均可配置，默认值只是本机的示例；坐标是相对**被控桌面**的像素位置，
可与 `xrandr` 查到的分辨率搭配使用：

    python3 vnc-click-test.py --port 5922 --x 1500 --y 300
"""
import argparse
import socket
import struct
import time

ap = argparse.ArgumentParser(description="向 UU 中继端口发一次右键点击")
ap.add_argument("--host", default="127.0.0.1")
ap.add_argument("--port", type=int, default=5922,
                help="中继端口，默认 5922（= environment 里的 UURB_DESKTOP_VNC_PORT）")
ap.add_argument("--x", type=int, default=1500, help="点击位置 X（示例值，按你的分辨率调整）")
ap.add_argument("--y", type=int, default=300, help="点击位置 Y（示例值，按你的分辨率调整）")
args = ap.parse_args()

s = socket.create_connection((args.host, args.port), timeout=5)
s.settimeout(5)

def recv_exact(n):
    buf = b""
    while len(buf) < n:
        c = s.recv(n - len(buf))
        if not c:
            raise RuntimeError("closed")
        buf += c
    return buf

# Handshake
ver = recv_exact(12)
print("server version:", ver)
s.sendall(b"RFB 003.008\n")
nsec = recv_exact(1)[0]
print("security types:", nsec, list(recv_exact(nsec)) if nsec else [])
# choose None (1) if present else first
if nsec == 0:
    pass
s.sendall(b"\x01")
secres = recv_exact(4)
print("security result:", struct.unpack(">I", secres)[0])
# ClientInit
s.sendall(struct.pack("B", 1))
w, h = struct.unpack(">HH", recv_exact(4))
print("server dims:", w, h)
recv_exact(16)  # pixel format
bn = struct.unpack(">I", recv_exact(4))[0]
recv_exact(bn)  # name
print("name len:", bn)

# Skip SetPixelFormat/SetEncodings; only input events are needed.

x, y = args.x, args.y
# PointerEvent: move
def pointer(buttons, x, y):
    s.sendall(struct.pack(">BBHH", 5, buttons, x, y))

pointer(0, x, y); time.sleep(0.3)
pointer(4, x, y); time.sleep(0.15)   # right button down
pointer(0, x, y); time.sleep(0.15)   # up
print("sent right-click at", x, y)
time.sleep(1.5)
s.close()
print("done")
