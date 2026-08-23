#!/usr/bin/env python3
import json
import os
import signal
import struct
import subprocess
import sys

from PIL import Image, ImageDraw

config = os.path.expanduser("~/.config/waybar/cava/waybar-config.toml")
fifo = "/tmp/waybar-cava.fifo"
lastfile = "/tmp/waybar-cava.last"
img_path = "/tmp/waybar-cava.png"
tmp_path = "/tmp/waybar-cava.tmp.png"
bars = 10
RENDER_EVERY = 2  # ~15 fps at cava's 30 fps

IMG_W, IMG_H = 73, 22
BAR_W, BAR_GAP, PAD = 4, 3, 3
BAR_COLOR = (236, 223, 229, 255)  # @fg


def kill_cava_only():
    subprocess.run(["pkill", "-f", f"cava -p {config}"], capture_output=True)


def on_signal(_sig=None, _frame=None):
    kill_cava_only()
    sys.exit(0)


def resolve_source():
    try:
        sink = subprocess.check_output(
            ["pactl", "get-default-sink"], stderr=subprocess.DEVNULL
        ).decode().strip()
        if not sink:
            return "auto"
        srcs = subprocess.check_output(
            ["pactl", "list", "sources", "short"], stderr=subprocess.DEVNULL
        ).decode()
        for ln in srcs.splitlines():
            if sink in ln and ".monitor" in ln:
                return ln.split("\t")[1].strip()
        return "auto"
    except Exception:
        return "auto"


def patch_config(source):
    import re

    try:
        with open(config) as f:
            txt = f.read()
        txt = re.sub(r"^source = .*$", f"source = {source}", txt, flags=re.M)
        with open(config, "w") as f:
            f.write(txt)
    except Exception:
        pass


def render(vals):
    base = Image.new("RGBA", (IMG_W, IMG_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(base)
    x = PAD
    max_h = IMG_H - 4
    for v in vals:
        h = max(2, int(v * max_h // 65535))
        y0 = IMG_H - 2 - h
        d.rounded_rectangle(
            [x, y0, x + BAR_W, IMG_H - 2], radius=BAR_W / 2, fill=BAR_COLOR
        )
        x += BAR_W + BAR_GAP
    base.save(tmp_path)
    os.replace(tmp_path, img_path)


signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

kill_cava_only()
patch_config(resolve_source())
if os.path.exists(fifo):
    os.remove(fifo)
os.mkfifo(fifo)

proc = subprocess.Popen(
    ["cava", "-p", config],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
frame_bytes = bars * 2
buf = b""
fd = os.open(fifo, os.O_RDONLY)
seq = 0
try:
    while True:
        chunk = os.read(fd, 4096)
        if not chunk:
            break
        buf += chunk
        n = len(buf) // frame_bytes
        if n:
            frames = struct.unpack(f"<{n * bars}H", buf[: n * frame_bytes])
            for i in range(n):
                vals = frames[i * bars : (i + 1) * bars]
                seq += 1
                if seq % RENDER_EVERY == 0:
                    render(vals)
                    out = json.dumps({"text": ""})
                    with open(lastfile, "w") as f:
                        f.write(out + "\n")
                    try:
                        print(out, flush=True)
                    except BrokenPipeError:
                        sys.exit(0)
            buf = buf[n * frame_bytes :]
finally:
    os.close(fd)
    proc.kill()
    kill_cava_only()
