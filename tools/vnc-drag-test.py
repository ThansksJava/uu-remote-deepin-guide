#!/usr/bin/env python3
"""自测工具：模拟一个 VNC 客户端连到本机中继端口，做一次完整初始化后
左键拖拽（在桌面上画一个选择框），验证 XTEST 注入链路。

端点与拖拽起止点均可配置，默认值只是本机的示例：

    python3 vnc-drag-test.py --port 5922 --x1 300 --y1 850 --x2 520 --y2 980
"""
import argparse
import socket
import struct
import time

ap = argparse.ArgumentParser(description="向 UU 中继端口发一次左键拖拽")
ap.add_argument("--host", default="127.0.0.1")
ap.add_argument("--port", type=int, default=5922,
                help="中继端口，默认 5922（= environment 里的 UURB_DESKTOP_VNC_PORT）")
ap.add_argument("--x1", type=int, default=300, help="起点 X（示例值）")
ap.add_argument("--y1", type=int, default=850, help="起点 Y（示例值）")
ap.add_argument("--x2", type=int, default=520, help="终点 X（示例值）")
ap.add_argument("--y2", type=int, default=980, help="终点 Y（示例值）")
args = ap.parse_args()

s = socket.create_connection((args.host, args.port), timeout=5)
s.settimeout(5)

def rx(n):
    b = b""
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c: raise RuntimeError("closed")
        b += c
    return b

print("ver:", rx(12))
s.sendall(b"RFB 003.008\n")
nsec = rx(1)[0]
print("sec types:", list(rx(nsec)))
s.sendall(b"\x01")
print("sec result:", struct.unpack(">I", rx(4))[0])
s.sendall(b"\x01")  # ClientInit shared
w, h = struct.unpack(">HH", rx(4))
rx(16)
nl = struct.unpack(">I", rx(4))[0]
print("server:", w, h, "name:", rx(nl))

# Minimal client: rely on server defaults, just request an update.
s.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, w, h))
time.sleep(0.5)
try:
    data = s.recv(65536)
    print("update bytes:", len(data), "first type:", data[0] if data else None)
except socket.timeout:
    print("no update within 0.5s (ok)")

def pointer(btn, x, y):
    s.sendall(struct.pack(">BBHH", 5, btn, x, y))

def key_down(k):
    s.sendall(struct.pack(">BBH", 4, 1, 0, k))

def key_up(k):
    s.sendall(struct.pack(">BBH", 4, 0, 0, k))

# 左键按下 → 分两步拖动 → 释放（在 DDE 桌面上会画出一个选择框）
x1, y1, x2, y2 = args.x1, args.y1, args.x2, args.y2
mx, my = (x1 + x2) // 2, (y1 + y2) // 2
pointer(0, x1, y1); time.sleep(0.2)
pointer(1, x1, y1); time.sleep(0.2)
pointer(1, mx, my); time.sleep(0.15)
pointer(1, x2, y2); time.sleep(0.15)
pointer(0, x2, y2); time.sleep(0.3)
print(f"drag sent ({x1},{y1}) -> ({x2},{y2})")
time.sleep(0.5)
s.close()
print("done")
