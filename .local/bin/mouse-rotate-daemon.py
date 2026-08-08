#!/usr/bin/env python3
"""
mouse-rotate-daemon.py - keep the pointer natural on a rotated monitor.

Hyprland applies relative pointer motion in its global logical space, so when
a monitor is rotated (transform != 0) the mouse direction rotates with the
screen. There is no Hyprland option for this. This daemon:

  * watches the monitor transform from a background thread (never in the
    hot event path),
  * only while a monitor is rotated it creates a virtual mouse, lets the
    compositor register it, then exclusively grabs the real mouse,
  * rotates the real mouse's relative deltas by the inverse of the display
    rotation and forwards them through the virtual mouse, so movement feels
    normal again,
  * when everything is back to normal (transform 0) it releases the grab and
    destroys the virtual mouse, so the real mouse works untouched.

If this process dies the kernel automatically releases the grab, so the real
mouse always keeps working.

The event path never spawns a subprocess: the only subprocess work is the
0.25 s transform poll in the background thread. REL events are drained until
the buffer is empty so the kernel never drops deltas.

Usage: mouse-rotate-daemon.py [--device /dev/input/eventN]
"""

import ctypes
import glob
import json
import os
import select
import struct
import subprocess
import sys
import threading
import time

LOG = "/tmp/mouse-rotate-daemon.log"

EV_SYN = 0x00
EV_KEY = 0x01
EV_REL = 0x02
EV_ABS = 0x03
EV_MSC = 0x04

REL_X = 0x00
REL_Y = 0x01
REL_HWHEEL = 0x06
REL_WHEEL = 0x08
REL_WHEEL_HI_RES = 0x0B
REL_HWHEEL_HI_RES = 0x0C

BTN_LEFT = 0x110
BTN_RIGHT = 0x111
BTN_MIDDLE = 0x112
BTN_SIDE = 0x113
BTN_EXTRA = 0x114

_IOC_WRITE = 1
_IOC_READ = 2


def _ioc(direction, t, nr, size):
    return (direction << 30) | (size << 16) | (t << 8) | nr


def _ior(t, nr, size):
    return _ioc(_IOC_READ, t, nr, size)


def _iow(t, nr, size):
    return _ioc(_IOC_WRITE, t, nr, size)


EVIOCGNAME = _ior(0x45, 0x06, 256)
EVIOCGBIT_REL = _ioc(_IOC_READ, 0x45, 0x20 + EV_REL, 8)
EVIOCGBIT_KEY = _ioc(_IOC_READ, 0x45, 0x20 + EV_KEY, 64)
EVIOCGRAB = _iow(0x45, 0x90, 4)

UI_SET_EVBIT = _iow(0x55, 100, 4)
UI_SET_KEYBIT = _iow(0x55, 101, 4)
UI_SET_RELBIT = _iow(0x55, 102, 4)
UI_DEV_CREATE = _ioc(0, 0x55, 1, 0)
UI_DEV_DESTROY = _ioc(0, 0x55, 2, 0)


class InputId(ctypes.Structure):
    _fields_ = [("bustype", ctypes.c_uint16), ("vendor", ctypes.c_uint16),
                ("product", ctypes.c_uint16), ("version", ctypes.c_uint16)]


class UinputSetup(ctypes.Structure):
    _fields_ = [("id", InputId), ("name", ctypes.c_char * 80),
                ("ff_effects_max", ctypes.c_uint32)]


UI_DEV_SETUP = _iow(0x55, 3, ctypes.sizeof(UinputSetup))

libc = ctypes.CDLL(None, use_errno=True)

VMOUSE_NAME = "vmouse-rotate"

POLL_INTERVAL = 0.25
REGISTER_WAIT = 0.6


def log(msg):
    try:
        with open(LOG, "a") as f:
            f.write("%s %s\n" % (time.strftime("%H:%M:%S"), msg))
    except OSError:
        pass


# ---------- rotation mapping ----------
# Emit logical deltas that cancel the display rotation so the physical hand
# maps 1:1 onto on-screen movement.
# Empirical (this box, transform 1): panel-right = logical +y, panel-up =
# logical +x, so physical -> logical is L = (-dy, dx); the other rotations
# follow by composition.
#   t=0: (dx,dy)
#   t=1 (90):  (-dy,dx)
#   t=2 (180): (-dx,-dy)
#   t=3 (270): (dy,-dx)
#   t=4..7: same rotation plus a horizontal flip of dy.
def unrotate(dx, dy, transform):
    r = transform & 3
    if r == 1:
        nx, ny = -dy, dx
    elif r == 2:
        nx, ny = -dx, -dy
    elif r == 3:
        nx, ny = dy, -dx
    else:
        nx, ny = dx, dy
    if transform >= 4:
        ny = -ny
    return nx, ny


# ---------- device discovery ----------

def _buf_has_bit(buf, code):
    return (buf[code >> 3] >> (code & 7)) & 1


def _device_name(fd):
    buf = ctypes.create_string_buffer(256)
    n = libc.ioctl(fd, EVIOCGNAME, buf)
    if n < 0:
        return ""
    return buf.raw[:n].split(b"\0")[0].decode(errors="replace")


def _device_is_pointer(fd):
    rel = ctypes.create_string_buffer(8)
    if libc.ioctl(fd, EVIOCGBIT_REL, rel) < 0:
        return False
    key = ctypes.create_string_buffer(64)
    if libc.ioctl(fd, EVIOCGBIT_KEY, key) < 0:
        return False
    return (_buf_has_bit(rel.raw, REL_X) and _buf_has_bit(rel.raw, REL_Y)
            and _buf_has_bit(key.raw, BTN_LEFT))


def find_real_mouse():
    best = None
    for ev in sorted(glob.glob("/dev/input/event*")):
        try:
            fd = os.open(ev, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            name = _device_name(fd).lower()
            if not name or VMOUSE_NAME in name:
                continue
            if not _device_is_pointer(fd):
                continue
            score = 2 if any(s in name for s in
                             ("mouse", "mice", "touchpad", "trackpad")) else 1
            if best is None or score > best[0]:
                best = (score, ev, name)
        finally:
            os.close(fd)
    if best is None:
        return None
    return best[1], best[2]


# ---------- virtual mouse ----------

def create_virtual_mouse():
    try:
        fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    except OSError:
        return None

    def fail():
        try:
            os.close(fd)
        except OSError:
            pass
        return None

    if libc.ioctl(fd, UI_SET_EVBIT, EV_REL) < 0:
        return fail()
    for c in (REL_X, REL_Y, REL_WHEEL, REL_HWHEEL,
              REL_WHEEL_HI_RES, REL_HWHEEL_HI_RES):
        if libc.ioctl(fd, UI_SET_RELBIT, c) < 0:
            return fail()
    if libc.ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0:
        return fail()
    for c in (BTN_LEFT, BTN_RIGHT, BTN_MIDDLE, BTN_SIDE, BTN_EXTRA):
        if libc.ioctl(fd, UI_SET_KEYBIT, c) < 0:
            return fail()

    setup = UinputSetup()
    setup.id.bustype = 3
    setup.id.vendor = 0x1234
    setup.id.product = 0x9ABC
    setup.id.version = 1
    setup.name = VMOUSE_NAME.encode()
    if libc.ioctl(fd, UI_DEV_SETUP, ctypes.byref(setup)) < 0:
        return fail()
    if libc.ioctl(fd, UI_DEV_CREATE) < 0:
        return fail()
    return fd


def destroy_virtual_mouse(fd):
    try:
        libc.ioctl(fd, UI_DEV_DESTROY)
    except OSError:
        pass
    try:
        os.close(fd)
    except OSError:
        pass


# ---------- event forwarding ----------

def write_event(fd, etype, code, value):
    os.write(fd, struct.pack("QQHHi", 0, 0, etype, code, value))


def read_event(fd):
    buf = b""
    while len(buf) < 24:
        try:
            chunk = os.read(fd, 24 - len(buf))
        except (BlockingIOError, InterruptedError):
            return None
        if not chunk:
            return None
        buf += chunk
    _s, _u, etype, code, value = struct.unpack("QQHHi", buf)
    return etype, code, value


class Forwarder:
    def __init__(self, vfd):
        self.vfd = vfd
        self.ax = 0
        self.ay = 0

    def feed(self, ev, transform):
        etype, code, value = ev
        if etype == EV_REL and code in (REL_X, REL_Y):
            dx = value if code == REL_X else 0
            dy = value if code == REL_Y else 0
            nx, ny = unrotate(dx, dy, transform)
            self.ax += nx
            self.ay += ny
            return
        if etype == EV_SYN:
            if self.ax or self.ay:
                write_event(self.vfd, EV_REL, REL_X, self.ax)
                write_event(self.vfd, EV_REL, REL_Y, self.ay)
                self.ax = 0
                self.ay = 0
            write_event(self.vfd, EV_SYN, 0, 0)
            return
        write_event(self.vfd, etype, code, value)


# ---------- background transform poller ----------

class MonitorState:
    def __init__(self):
        self.lock = threading.Lock()
        self.transform = 0


def poll_monitors(state, stop):
    while not stop.is_set():
        try:
            out = subprocess.run(["hyprctl", "-j", "monitors"],
                                 capture_output=True, text=True, timeout=3).stdout
            mons = json.loads(out) if out else []
            if not mons:
                t = 0
            else:
                focused = [m for m in mons if m.get("focused")]
                m = focused[0] if focused else mons[0]
                t = int(m.get("transform", 0)) & 7
            with state.lock:
                state.transform = t
        except Exception:
            pass
        stop.wait(POLL_INTERVAL)


# ---------- main ----------

def main():
    device_override = None
    if "--device" in sys.argv:
        device_override = sys.argv[sys.argv.index("--device") + 1]

    log("mouse-rotate-daemon starting")

    state = MonitorState()
    stop = threading.Event()
    threading.Thread(target=poll_monitors, args=(state, stop),
                     daemon=True).start()

    grabbed = None  # (fd, path, vfd, forwarder)
    transform = 0

    while True:
        with state.lock:
            transform = state.transform

        if transform == 0:
            if grabbed is not None:
                fd, path, vfd, _fwd = grabbed
                try:
                    libc.ioctl(fd, EVIOCGRAB, 0)
                except OSError:
                    pass
                try:
                    os.close(fd)
                except OSError:
                    pass
                destroy_virtual_mouse(vfd)
                grabbed = None
                log("released grab on %s" % path)
            time.sleep(0.05)
            continue

        if grabbed is None:
            path = device_override
            name = ""
            if path is None:
                found = find_real_mouse()
                if found is None:
                    time.sleep(0.3)
                    continue
                path, name = found
            vfd = create_virtual_mouse()
            if vfd is None:
                log("ERROR: cannot create virtual mouse (uinput?)")
                time.sleep(1.0)
                continue
            time.sleep(REGISTER_WAIT)  # let the compositor register it
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            except OSError:
                destroy_virtual_mouse(vfd)
                time.sleep(0.5)
                continue
            if libc.ioctl(fd, EVIOCGRAB, 1) != 0:
                log("grab failed on %s (%s)" % (path, name))
                os.close(fd)
                destroy_virtual_mouse(vfd)
                time.sleep(1.0)
                continue
            grabbed = (fd, path, vfd, Forwarder(vfd))
            log("grabbed %s (%s) transform=%d" % (path, name or "?", transform))

        fd, _path, _vfd, fwd = grabbed

        while True:
            ev = read_event(fd)
            if ev is None:
                break
            fwd.feed(ev, transform)

        try:
            r, _, _ = select.select([fd], [], [], 0.02)
        except (OSError, ValueError):
            fd2, path, vfd2, _fwd2 = grabbed
            grabbed = None
            try:
                os.close(fd2)
            except OSError:
                pass
            destroy_virtual_mouse(vfd2)
            log("real mouse gone, re-detecting")
            continue
        if not r:
            time.sleep(0.001)


if __name__ == "__main__":
    main()
