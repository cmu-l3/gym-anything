#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes
import fcntl
import json
import os
import socketserver
import struct
import threading
import time
import traceback
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple


VERSION = 1

EV_SYN = 0x00
EV_KEY = 0x01
EV_REL = 0x02
REL_WHEEL = 0x08
REL_HWHEEL = 0x06
SYN_REPORT = 0
BUS_USB = 0x03

UI_DEV_CREATE = 0x5501
UI_DEV_DESTROY = 0x5502
UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_SET_RELBIT = 0x40045566

KEY_ESC = 1
KEY_1 = 2
KEY_2 = 3
KEY_3 = 4
KEY_4 = 5
KEY_5 = 6
KEY_6 = 7
KEY_7 = 8
KEY_8 = 9
KEY_9 = 10
KEY_0 = 11
KEY_MINUS = 12
KEY_EQUAL = 13
KEY_BACKSPACE = 14
KEY_TAB = 15
KEY_Q = 16
KEY_W = 17
KEY_E = 18
KEY_R = 19
KEY_T = 20
KEY_Y = 21
KEY_U = 22
KEY_I = 23
KEY_O = 24
KEY_P = 25
KEY_LEFTBRACE = 26
KEY_RIGHTBRACE = 27
KEY_ENTER = 28
KEY_LEFTCTRL = 29
KEY_A = 30
KEY_S = 31
KEY_D = 32
KEY_F = 33
KEY_G = 34
KEY_H = 35
KEY_J = 36
KEY_K = 37
KEY_L = 38
KEY_SEMICOLON = 39
KEY_APOSTROPHE = 40
KEY_GRAVE = 41
KEY_LEFTSHIFT = 42
KEY_BACKSLASH = 43
KEY_Z = 44
KEY_X = 45
KEY_C = 46
KEY_V = 47
KEY_B = 48
KEY_N = 49
KEY_M = 50
KEY_COMMA = 51
KEY_DOT = 52
KEY_SLASH = 53
KEY_RIGHTSHIFT = 54
KEY_KPASTERISK = 55
KEY_LEFTALT = 56
KEY_SPACE = 57
KEY_CAPSLOCK = 58
KEY_F1 = 59
KEY_F2 = 60
KEY_F3 = 61
KEY_F4 = 62
KEY_F5 = 63
KEY_F6 = 64
KEY_F7 = 65
KEY_F8 = 66
KEY_F9 = 67
KEY_F10 = 68
KEY_NUMLOCK = 69
KEY_SCROLLLOCK = 70
KEY_F11 = 87
KEY_F12 = 88
KEY_HOME = 102
KEY_UP = 103
KEY_PAGEUP = 104
KEY_LEFT = 105
KEY_RIGHT = 106
KEY_END = 107
KEY_DOWN = 108
KEY_PAGEDOWN = 109
KEY_INSERT = 110
KEY_DELETE = 111
KEY_LEFTMETA = 125
KEY_RIGHTMETA = 126
KEY_F13 = 183
KEY_F14 = 184
KEY_F15 = 185
KEY_F16 = 186
KEY_F17 = 187
KEY_F18 = 188
KEY_F19 = 189
KEY_F20 = 190
KEY_F21 = 191
KEY_F22 = 192
KEY_F23 = 193
KEY_F24 = 194

KEY_BY_NAME: Dict[str, int] = {
    "esc": KEY_ESC,
    "escape": KEY_ESC,
    "1": KEY_1,
    "2": KEY_2,
    "3": KEY_3,
    "4": KEY_4,
    "5": KEY_5,
    "6": KEY_6,
    "7": KEY_7,
    "8": KEY_8,
    "9": KEY_9,
    "0": KEY_0,
    "minus": KEY_MINUS,
    "equal": KEY_EQUAL,
    "backspace": KEY_BACKSPACE,
    "tab": KEY_TAB,
    "q": KEY_Q,
    "w": KEY_W,
    "e": KEY_E,
    "r": KEY_R,
    "t": KEY_T,
    "y": KEY_Y,
    "u": KEY_U,
    "i": KEY_I,
    "o": KEY_O,
    "p": KEY_P,
    "bracket_left": KEY_LEFTBRACE,
    "leftbrace": KEY_LEFTBRACE,
    "bracket_right": KEY_RIGHTBRACE,
    "rightbrace": KEY_RIGHTBRACE,
    "enter": KEY_ENTER,
    "return": KEY_ENTER,
    "ret": KEY_ENTER,
    "ctrl": KEY_LEFTCTRL,
    "control": KEY_LEFTCTRL,
    "leftctrl": KEY_LEFTCTRL,
    "a": KEY_A,
    "s": KEY_S,
    "d": KEY_D,
    "f": KEY_F,
    "g": KEY_G,
    "h": KEY_H,
    "j": KEY_J,
    "k": KEY_K,
    "l": KEY_L,
    "semicolon": KEY_SEMICOLON,
    "apostrophe": KEY_APOSTROPHE,
    "quote": KEY_APOSTROPHE,
    "grave": KEY_GRAVE,
    "grave_accent": KEY_GRAVE,
    "backtick": KEY_GRAVE,
    "shift": KEY_LEFTSHIFT,
    "leftshift": KEY_LEFTSHIFT,
    "backslash": KEY_BACKSLASH,
    "z": KEY_Z,
    "x": KEY_X,
    "c": KEY_C,
    "v": KEY_V,
    "b": KEY_B,
    "n": KEY_N,
    "m": KEY_M,
    "comma": KEY_COMMA,
    "dot": KEY_DOT,
    "period": KEY_DOT,
    "slash": KEY_SLASH,
    "rightshift": KEY_RIGHTSHIFT,
    "alt": KEY_LEFTALT,
    "leftalt": KEY_LEFTALT,
    "space": KEY_SPACE,
    "spc": KEY_SPACE,
    "capslock": KEY_CAPSLOCK,
    "numlock": KEY_NUMLOCK,
    "scrolllock": KEY_SCROLLLOCK,
    "home": KEY_HOME,
    "up": KEY_UP,
    "pageup": KEY_PAGEUP,
    "pgup": KEY_PAGEUP,
    "left": KEY_LEFT,
    "right": KEY_RIGHT,
    "end": KEY_END,
    "down": KEY_DOWN,
    "pagedown": KEY_PAGEDOWN,
    "pgdn": KEY_PAGEDOWN,
    "delete": KEY_DELETE,
    "del": KEY_DELETE,
    "insert": KEY_INSERT,
    "ins": KEY_INSERT,
    "meta": KEY_LEFTMETA,
    "super": KEY_LEFTMETA,
    "win": KEY_LEFTMETA,
    "cmd": KEY_LEFTMETA,
    "command": KEY_LEFTMETA,
    "meta_l": KEY_LEFTMETA,
    "meta_r": KEY_RIGHTMETA,
}

for index, code in enumerate(
    [
        KEY_F1,
        KEY_F2,
        KEY_F3,
        KEY_F4,
        KEY_F5,
        KEY_F6,
        KEY_F7,
        KEY_F8,
        KEY_F9,
        KEY_F10,
        KEY_F11,
        KEY_F12,
        KEY_F13,
        KEY_F14,
        KEY_F15,
        KEY_F16,
        KEY_F17,
        KEY_F18,
        KEY_F19,
        KEY_F20,
        KEY_F21,
        KEY_F22,
        KEY_F23,
        KEY_F24,
    ],
    start=1,
):
    KEY_BY_NAME[f"f{index}"] = code

CHAR_MAP: Dict[str, Tuple[str, bool]] = {
    " ": ("space", False),
    "\n": ("enter", False),
    "\r": ("enter", False),
    "\t": ("tab", False),
    "`": ("grave", False),
    "~": ("grave", True),
    "1": ("1", False),
    "!": ("1", True),
    "2": ("2", False),
    "@": ("2", True),
    "3": ("3", False),
    "#": ("3", True),
    "4": ("4", False),
    "$": ("4", True),
    "5": ("5", False),
    "%": ("5", True),
    "6": ("6", False),
    "^": ("6", True),
    "7": ("7", False),
    "&": ("7", True),
    "8": ("8", False),
    "*": ("8", True),
    "9": ("9", False),
    "(": ("9", True),
    "0": ("0", False),
    ")": ("0", True),
    "-": ("minus", False),
    "_": ("minus", True),
    "=": ("equal", False),
    "+": ("equal", True),
    "[": ("bracket_left", False),
    "{": ("bracket_left", True),
    "]": ("bracket_right", False),
    "}": ("bracket_right", True),
    "\\": ("backslash", False),
    "|": ("backslash", True),
    ";": ("semicolon", False),
    ":": ("semicolon", True),
    "'": ("apostrophe", False),
    '"': ("apostrophe", True),
    ",": ("comma", False),
    "<": ("comma", True),
    ".": ("dot", False),
    ">": ("dot", True),
    "/": ("slash", False),
    "?": ("slash", True),
}

for letter in "abcdefghijklmnopqrstuvwxyz":
    CHAR_MAP[letter] = (letter, False)
    CHAR_MAP[letter.upper()] = (letter, True)

SUPPORTED_KEYS = sorted(set(KEY_BY_NAME.values()))


class UInputKeyboard:
    def __init__(self, path: str, name: str):
        self.path = path
        self.name = name
        self.fd: Optional[int] = None
        self.pressed: Set[int] = set()

    def open(self) -> None:
        self.fd = os.open(self.path, os.O_WRONLY | os.O_NONBLOCK)
        try:
            fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_SYN)
            fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
            for code in SUPPORTED_KEYS:
                fcntl.ioctl(self.fd, UI_SET_KEYBIT, code)
            # The wheel rides this device too, so a modifier-held scroll is
            # one ordered stream instead of a race between two transports.
            fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_REL)
            fcntl.ioctl(self.fd, UI_SET_RELBIT, REL_WHEEL)
            fcntl.ioctl(self.fd, UI_SET_RELBIT, REL_HWHEEL)
            name = self.name.encode("utf-8")[:79] + b"\0"
            payload = struct.pack(
                "80sHHHHI" + "i" * 256,
                name,
                BUS_USB,
                0x1209,
                0xA111,
                1,
                0,
                *([0] * 256),
            )
            os.write(self.fd, payload)
            fcntl.ioctl(self.fd, UI_DEV_CREATE)
        except Exception:
            os.close(self.fd)
            self.fd = None
            raise

    def close(self) -> None:
        if self.fd is None:
            return
        try:
            self.release_all()
            fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        finally:
            os.close(self.fd)
            self.fd = None

    def emit(self, ev_type: int, code: int, value: int) -> None:
        if self.fd is None:
            raise RuntimeError("uinput device is not open")
        os.write(self.fd, struct.pack("llHHi", 0, 0, ev_type, code, value))

    def syn(self) -> None:
        self.emit(EV_SYN, SYN_REPORT, 0)

    def key_down(self, code: int) -> None:
        self.emit(EV_KEY, code, 1)
        self.syn()
        self.pressed.add(code)

    def key_up(self, code: int) -> None:
        self.emit(EV_KEY, code, 0)
        self.syn()
        self.pressed.discard(code)

    def key_tap(self, code: int) -> None:
        self.key_down(code)
        self.key_up(code)

    def wheel(self, dy: int = 0, dx: int = 0) -> None:
        """One wheel notch per SYN, which is what keeps the count exact.

        A guest coalesces notches that arrive inside one input report, so
        emitting N in a single report loses some of them (25 requested,
        24 delivered, through QEMU).
        """
        for _ in range(abs(dy)):
            self.emit(EV_REL, REL_WHEEL, -1 if dy > 0 else 1)
            self.syn()
        for _ in range(abs(dx)):
            self.emit(EV_REL, REL_HWHEEL, 1 if dx > 0 else -1)
            self.syn()

    def combo(self, codes: Iterable[int]) -> None:
        ordered = list(codes)
        for code in ordered:
            self.key_down(code)
        for code in reversed(ordered):
            self.key_up(code)

    def release_all(self) -> None:
        for code in sorted(self.pressed, reverse=True):
            self.emit(EV_KEY, code, 0)
        if self.pressed:
            self.syn()
        self.pressed.clear()


class _XGenericEventCookie(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", ctypes.c_int),
        ("display", ctypes.c_void_p),
        ("extension", ctypes.c_int),
        ("evtype", ctypes.c_int),
        ("cookie", ctypes.c_uint),
        ("data", ctypes.c_void_p),
    ]


class _XIRawEvent(ctypes.Structure):
    # Only the head is read; valuator fields past `flags` are not needed to
    # count deliveries.
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", ctypes.c_int),
        ("display", ctypes.c_void_p),
        ("extension", ctypes.c_int),
        ("evtype", ctypes.c_int),
        ("time", ctypes.c_ulong),
        ("deviceid", ctypes.c_int),
        ("sourceid", ctypes.c_int),
        ("detail", ctypes.c_int),
        ("flags", ctypes.c_int),
    ]


class _XIEventMask(ctypes.Structure):
    _fields_ = [
        ("deviceid", ctypes.c_int),
        ("mask_len", ctypes.c_int),
        ("mask", ctypes.POINTER(ctypes.c_ubyte)),
    ]


class XInputListener:
    """What the X server actually dispatched, read from the X server.

    The kernel accepts every event we inject and reports nothing back: an
    evdev client whose ring buffer (64 events minimum) fills has its whole
    queue discarded and gets a synthetic SYN_DROPPED, while the writer is
    told nothing (drivers/input/evdev.c, __pass_event). So "the kernel took
    it" is not evidence the X server got it, and a 200-character burst can
    vanish entirely.

    XI2 raw events are the record of what the server processed. They are
    delivered regardless of focus or grabs, so this counts deliveries rather
    than inferring them from end state: a burst that arrives as three events
    instead of two hundred is visible here and nowhere else.
    """

    GENERIC_EVENT = 35
    XI_RAW_KEY_PRESS = 13
    XI_RAW_KEY_RELEASE = 14
    XI_RAW_BUTTON_PRESS = 15
    XI_RAW_BUTTON_RELEASE = 16
    XI_RAW_MOTION = 17
    XI_ALL_DEVICES = 0
    XI_ALL_MASTER_DEVICES = 1

    def __init__(self, display_name: str, deviceid: int = XI_ALL_MASTER_DEVICES):
        # Measured on the guest: selecting XIAllDevices delivers each raw
        # event twice, once for the slave and once for the master, so a
        # counter built on it confirms a burst when half of it has arrived.
        # XIAllMasterDevices reports each event once.
        self._x11 = ctypes.CDLL("libX11.so.6")
        self._xi = ctypes.CDLL("libXi.so.6")
        self._x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self._x11.XOpenDisplay.restype = ctypes.c_void_p
        self._x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        self._x11.XDefaultRootWindow.restype = ctypes.c_ulong
        self._x11.XQueryExtension.argtypes = [
            ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
        self._x11.XNextEvent.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        self._x11.XPending.argtypes = [ctypes.c_void_p]
        self._x11.XPending.restype = ctypes.c_int
        self._x11.XGetEventData.argtypes = [ctypes.c_void_p,
                                            ctypes.POINTER(_XGenericEventCookie)]
        self._x11.XGetEventData.restype = ctypes.c_int
        self._x11.XFreeEventData.argtypes = [ctypes.c_void_p,
                                             ctypes.POINTER(_XGenericEventCookie)]
        self._x11.XFlush.argtypes = [ctypes.c_void_p]
        self._xi.XISelectEvents.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
                                            ctypes.POINTER(_XIEventMask),
                                            ctypes.c_int]
        self._xi.XIQueryVersion.argtypes = [ctypes.c_void_p,
                                            ctypes.POINTER(ctypes.c_int),
                                            ctypes.POINTER(ctypes.c_int)]

        self._display = self._x11.XOpenDisplay(display_name.encode("utf-8"))
        if not self._display:
            raise RuntimeError(f"could not open X11 display {display_name!r}")
        opcode, first_event, first_error = (ctypes.c_int(), ctypes.c_int(),
                                            ctypes.c_int())
        if not self._x11.XQueryExtension(
                self._display, b"XInputExtension", ctypes.byref(opcode),
                ctypes.byref(first_event), ctypes.byref(first_error)):
            raise RuntimeError("X server has no XInputExtension")
        self._opcode = opcode.value
        major, minor = ctypes.c_int(2), ctypes.c_int(2)
        self._xi.XIQueryVersion(self._display, ctypes.byref(major),
                                ctypes.byref(minor))

        mask_bits = (ctypes.c_ubyte * 4)()
        for evtype in (self.XI_RAW_KEY_PRESS, self.XI_RAW_KEY_RELEASE,
                       self.XI_RAW_BUTTON_PRESS, self.XI_RAW_BUTTON_RELEASE,
                       self.XI_RAW_MOTION):
            mask_bits[evtype >> 3] |= 1 << (evtype & 7)
        event_mask = _XIEventMask(deviceid=deviceid, mask_len=4,
                                  mask=ctypes.cast(mask_bits,
                                                   ctypes.POINTER(ctypes.c_ubyte)))
        root = self._x11.XDefaultRootWindow(self._display)
        self._xi.XISelectEvents(self._display, root, ctypes.byref(event_mask), 1)
        self._x11.XFlush(self._display)

        self._changed = threading.Condition()
        self._counts: Dict[int, int] = {}
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._drain, daemon=True)
        self._thread.start()

    def _drain(self) -> None:
        buffer = (ctypes.c_char * 256)()
        while not self._stop.is_set():
            # XNextEvent blocks, which is what keeps this thread off the CPU;
            # the connection is this listener's own, so blocking on it cannot
            # hold up injection.
            self._x11.XNextEvent(self._display, ctypes.byref(buffer))
            cookie = ctypes.cast(ctypes.byref(buffer),
                                 ctypes.POINTER(_XGenericEventCookie)).contents
            if cookie.type != self.GENERIC_EVENT or cookie.extension != self._opcode:
                continue
            if not self._x11.XGetEventData(self._display, ctypes.byref(cookie)):
                continue
            try:
                evtype = cookie.evtype
                with self._changed:
                    self._counts[evtype] = self._counts.get(evtype, 0) + 1
                    self._changed.notify_all()
            finally:
                self._x11.XFreeEventData(self._display, ctypes.byref(cookie))

    def counts(self) -> Dict[int, int]:
        with self._changed:
            return dict(self._counts)

    def wait_for(self, evtype: int, target: int, timeout_ms: int) -> Tuple[bool, int]:
        """Block until the server has dispatched `target` events of a type.

        Counting is what makes this a delivery record: end state cannot tell
        two key presses from twenty when every one of them is released again.

        Woken by the reader thread, not by a poll interval, so nothing here
        picks a rate. The deadline only decides when to give up and say what
        was missing.
        """
        deadline = time.perf_counter() + timeout_ms / 1000.0
        with self._changed:
            while True:
                seen = self._counts.get(evtype, 0)
                if seen >= target:
                    return True, seen
                remaining = deadline - time.perf_counter()
                if remaining <= 0:
                    return False, seen
                self._changed.wait(remaining)

    def close(self) -> None:
        self._stop.set()


class X11State:
    def __init__(self, display_name: str):
        lib = ctypes.CDLL("libX11.so.6")
        lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
        lib.XOpenDisplay.restype = ctypes.c_void_p
        lib.XCloseDisplay.argtypes = [ctypes.c_void_p]
        lib.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.XQueryKeymap.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        lib.XDefaultRootWindow.restype = ctypes.c_ulong
        lib.XQueryPointer.argtypes = [
            ctypes.c_void_p, ctypes.c_ulong,
            ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_uint),
        ]
        lib.XQueryPointer.restype = ctypes.c_int
        display = lib.XOpenDisplay(display_name.encode("utf-8"))
        if not display:
            raise RuntimeError(f"could not open X11 display {display_name!r}")
        self._lib = lib
        self._display = display
        self._root = lib.XDefaultRootWindow(display)

    def close(self) -> None:
        if self._display:
            self._lib.XCloseDisplay(self._display)
            self._display = None

    def sync(self) -> None:
        self._lib.XSync(self._display, 0)

    def keymap(self) -> bytes:
        buf = ctypes.create_string_buffer(32)
        self._lib.XQueryKeymap(self._display, buf)
        return bytes(buf.raw)

    def pointer(self) -> Tuple[int, int, int]:
        """Root pointer position and button mask, straight from the X server.

        Every call is a server round trip, so it doubles as the sync: what it
        returns is what X has actually processed, not what was queued.
        """
        root = ctypes.c_ulong()
        child = ctypes.c_ulong()
        root_x, root_y = ctypes.c_int(), ctypes.c_int()
        win_x, win_y = ctypes.c_int(), ctypes.c_int()
        mask = ctypes.c_uint()
        self._lib.XQueryPointer(
            self._display, self._root, ctypes.byref(root), ctypes.byref(child),
            ctypes.byref(root_x), ctypes.byref(root_y),
            ctypes.byref(win_x), ctypes.byref(win_y), ctypes.byref(mask))
        return root_x.value, root_y.value, mask.value

    def wait_pointer(self, expect: Dict[str, Any], timeout_ms: int
                     ) -> Tuple[bool, Tuple[int, int, int]]:
        """Block until the X server's pointer state matches, or the deadline.

        This is the pointer half of the delivery barrier. QMP's
        input-send-event returns once QEMU has QUEUED events into the virtio
        device, which says nothing about the guest having consumed them, so
        the caller's next action can overtake them. Polling the server for the
        state we asked for is the only claim that holds: no sleep, and the
        deadline exists to fail rather than to pace.
        """
        deadline = time.perf_counter() + timeout_ms / 1000.0
        want_x, want_y = expect.get("x"), expect.get("y")
        tolerance = int(expect.get("tol", 2))
        mask_set = int(expect.get("mask_set", 0))
        mask_clear = int(expect.get("mask_clear", 0))
        while True:
            state = self.pointer()
            x, y, mask = state
            matched = True
            if want_x is not None and abs(x - int(want_x)) > tolerance:
                matched = False
            if want_y is not None and abs(y - int(want_y)) > tolerance:
                matched = False
            if mask_set and (mask & mask_set) != mask_set:
                matched = False
            if mask_clear and (mask & mask_clear):
                matched = False
            if matched or time.perf_counter() >= deadline:
                return matched, state

    def wait_keymap_restored(self, before: bytes, timeout_ms: int) -> bool:
        deadline = time.perf_counter() + timeout_ms / 1000.0
        while True:
            self.sync()
            if self.keymap() == before:
                return True
            if time.perf_counter() >= deadline:
                return False
            time.sleep(0.001)

    def key_is_down(self, keycode: int) -> bool:
        """Is this X keycode held, according to the server's own key state?

        X keycode is the evdev code plus 8. XQueryKeymap is a bit vector of
        the 256 keycodes, so this reads the server's view directly rather
        than inferring it from a modifier mask.
        """
        bits = self.keymap()
        return bool(bits[keycode // 8] & (1 << (keycode % 8)))

    def wait_key_down(self, keycode: int, timeout_ms: int) -> bool:
        """Block until the X server shows the key held.

        A chord presses its modifier and its main key microseconds apart. If
        the server has not folded the modifier into its state by the time the
        main key is processed, the chord arrives as a bare keypress: measured
        on super+d, where the tap saw key_down super, then key_down d with an
        empty modifier list, while ctrl+c registered correctly.
        """
        deadline = time.perf_counter() + timeout_ms / 1000.0
        while True:
            if self.key_is_down(keycode):
                return True
            if time.perf_counter() >= deadline:
                return False

    def wait_keymap_changed(self, before: bytes, timeout_ms: int) -> bool:
        """Ack for a request that deliberately changes the held-key set.

        A held modifier only counts once the X server has it: the pointer
        event that follows must observe it. Waiting here makes keys_down
        synchronous with X instead of racing the next action.
        """
        deadline = time.perf_counter() + timeout_ms / 1000.0
        while True:
            self.sync()
            if self.keymap() != before:
                return True
            if time.perf_counter() >= deadline:
                return False
            time.sleep(0.001)


class FastInputService:
    def __init__(self, keyboard: UInputKeyboard, x11: Optional[X11State],
                 x11_ack_timeout_ms: int,
                 listener: "Optional[XInputListener]" = None):
        self.keyboard = keyboard
        self.x11 = x11
        self.x11_ack_timeout_ms = x11_ack_timeout_ms
        self.listener = listener
        self.lock = threading.Lock()

    def handle(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        op = payload.get("op")
        if op == "ping":
            return {
                "ok": True,
                "version": VERSION,
                "backend": "uinput",
                "device_name": self.keyboard.name,
                "x11": self.x11 is not None,
            }
        if op == "keyboard":
            keyboard = payload.get("keyboard")
            if not isinstance(keyboard, dict):
                raise ValueError("keyboard request must contain a keyboard object")
            return self._keyboard(keyboard)
        if op == "release_all":
            with self.lock:
                self.keyboard.release_all()
            return {"ok": True, "released": True}
        if op == "await_pointer":
            return self._await_pointer(payload)
        if op == "scroll":
            return self._scroll(payload)
        raise ValueError(f"unknown op {op!r}")

    # Events per chunk, kept well under the 64-event floor of an evdev
    # client's ring buffer (drivers/input/evdev.c). A chunk that overruns a
    # consumer's ring has its WHOLE queue discarded, not trimmed, which is
    # how a 200-character string arrived as a single shift press.
    _CHUNK_EVENTS = 24

    def _type_text(self, text: str) -> int:
        chunk: List[Tuple[int, bool]] = []
        cost = 0
        events = 0
        for code, shifted in text_to_codes(text):
            # key down + up + a SYN each, doubled when the shift wrap is on.
            char_cost = 8 if shifted else 4
            if chunk and cost + char_cost > self._CHUNK_EVENTS:
                events += self._emit_chunk(chunk)
                chunk, cost = [], 0
            chunk.append((code, shifted))
            cost += char_cost
        if chunk:
            events += self._emit_chunk(chunk)
        return events

    def _emit_chunk(self, chunk: List[Tuple[int, bool]]) -> int:
        """Type one chunk, then confirm the X server dispatched all of it.

        Without the confirmation the chunk size would be a guess about
        someone else's buffer. With it, the size only decides throughput: a
        chunk that gets dropped is reported with its exact shortfall instead
        of surfacing later as text that silently differs.
        """
        presses = sum(2 if shifted else 1 for _, shifted in chunk)
        before = (self.listener.counts().get(XInputListener.XI_RAW_KEY_PRESS, 0)
                  if self.listener else 0)
        events = 0
        for code, shifted in chunk:
            if shifted:
                self.keyboard.key_down(KEY_LEFTSHIFT)
                events += 1
            self.keyboard.key_tap(code)
            events += 2
            if shifted:
                self.keyboard.key_up(KEY_LEFTSHIFT)
                events += 1
        if self.listener:
            arrived, seen = self.listener.wait_for(
                XInputListener.XI_RAW_KEY_PRESS, before + presses,
                self.x11_ack_timeout_ms)
            if not arrived:
                self.keyboard.release_all()
                raise RuntimeError(
                    f"X server dispatched {seen - before} of {presses} key "
                    f"presses; the rest never reached it (evdev client "
                    f"buffer overrun drops the whole queue silently)")
        return events

    def _chord(self, codes: List[int]) -> int:
        """Press the keys in order, each confirmed held by the X server before
        the next goes down, then release in reverse.

        Without the confirmation a chord can arrive as its main key alone,
        because the modifier is not yet in the server's state when the main
        key is processed.
        """
        for code in codes:
            self.keyboard.key_down(code)
            if self.x11 is not None:
                # X keycode is the evdev code plus 8.
                if not self.x11.wait_key_down(code + 8, self.x11_ack_timeout_ms):
                    self.keyboard.release_all()
                    raise RuntimeError(
                        f"X server never registered key {code} as held; the "
                        f"chord would have arrived without it")
        for code in reversed(codes):
            self.keyboard.key_up(code)
        return 2 * len(codes)

    def _scroll(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Wheel notches on the same device as the keys, under the same lock.

        A modifier-held scroll is keys_down, scroll, keys_up. Injected through
        QEMU the wheel is a different transport from the keys, so the release
        overtook the notches and the app saw an unmodified scroll. Same device
        means one ordered stream and no barrier needed between them.
        """
        started = time.perf_counter_ns()
        dy = int(payload.get("dy") or 0)
        dx = int(payload.get("dx") or 0)
        with self.lock:
            self.keyboard.wheel(dy=dy, dx=dx)
        return {
            "ok": True,
            "dy": dy,
            "dx": dx,
            "elapsed_ms": (time.perf_counter_ns() - started) / 1_000_000.0,
        }

    def _await_pointer(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Delivery barrier for pointer events injected out of band (QMP).

        The runner injects the pointer through QEMU, which is a different
        path from this agent, so nothing about that call proves the guest
        consumed it. This asks the X server directly and returns once its
        state matches what the runner sent.
        """
        if self.x11 is None:
            raise ValueError("await_pointer needs the X11 connection")
        expect = payload.get("expect")
        if not isinstance(expect, dict):
            raise ValueError("await_pointer needs an expect object")
        timeout_ms = int(payload.get("timeout_ms") or self.x11_ack_timeout_ms)
        started = time.perf_counter_ns()
        matched, (x, y, mask) = self.x11.wait_pointer(expect, timeout_ms)
        return {
            "ok": True,
            "matched": matched,
            "x": x,
            "y": y,
            "mask": mask,
            "elapsed_ms": (time.perf_counter_ns() - started) / 1_000_000.0,
        }

    def _keyboard(self, keyboard: Dict[str, Any]) -> Dict[str, Any]:
        started = time.perf_counter_ns()
        # Refuse before touching the device, never halfway through: the caller
        # retries the whole request on the guest's Xlib typer, and a partially
        # typed string would then be typed twice.
        unsupported = unsupported_text_chars(keyboard.get("text"))
        if unsupported:
            return {"ok": False, "error": "unsupported_text", "chars": unsupported}
        unknown_keys = unsupported_key_names(keyboard)
        if unknown_keys:
            return {"ok": False, "error": "unsupported_keys", "keys": unknown_keys}
        before = self.x11.keymap() if self.x11 else None
        pressed_before = set(self.keyboard.pressed)
        presses_before = (self.listener.counts().get(
            XInputListener.XI_RAW_KEY_PRESS, 0) if self.listener else 0)
        expected_presses = _expected_presses(keyboard)
        events = 0
        with self.lock:
            try:
                if "text" in keyboard:
                    events += self._type_text(str(keyboard["text"]))
                if "keys" in keyboard:
                    codes = _key_codes(keyboard["keys"], "keyboard.keys")
                    events += self._chord(codes)
                # keys_down / keys_up compose a modifier-held gesture: the hold
                # spans the pointer action that follows, so these keys stay
                # down across requests until keys_up releases them.
                if "keys_down" in keyboard:
                    for code in _key_codes(keyboard["keys_down"], "keyboard.keys_down"):
                        self.keyboard.key_down(code)
                        events += 1
                if "keys_up" in keyboard:
                    for code in _key_codes(keyboard["keys_up"], "keyboard.keys_up"):
                        self.keyboard.key_up(code)
                        events += 1
            except Exception:
                self.keyboard.release_all()
                raise

            # Where did they land? Compares what this device emitted against
            # what the X server dispatched, so a request that vanishes says so
            # here instead of surfacing later as text that silently differs.
            dispatched = None
            if self.listener is not None and expected_presses:
                arrived, seen = self.listener.wait_for(
                    XInputListener.XI_RAW_KEY_PRESS,
                    presses_before + expected_presses, self.x11_ack_timeout_ms)
                dispatched = seen - presses_before
                if not arrived:
                    print(json.dumps({
                        "event": "key_presses_lost",
                        "expected": expected_presses,
                        "x_dispatched": dispatched,
                        "text": str(keyboard.get("text", ""))[:40],
                        "keys": keyboard.get("keys"),
                    }), flush=True)

            restored = True
            if self.x11 and before is not None:
                if set(self.keyboard.pressed) != pressed_before:
                    # The request changed what is held. X must have seen it
                    # before the next action is injected, or a modifier-held
                    # click races its own modifier.
                    restored = self.x11.wait_keymap_changed(
                        before, self.x11_ack_timeout_ms)
                    if not restored:
                        self.keyboard.release_all()
                        raise RuntimeError(
                            "X11 never observed the held-key change")
                else:
                    restored = self.x11.wait_keymap_restored(
                        before, self.x11_ack_timeout_ms)
                    if not restored:
                        self.keyboard.release_all()
                        raise RuntimeError(
                            "X11 keymap did not return to its pre-action state")

        return {
            "ok": True,
            "events": events,
            "expected_presses": expected_presses,
            "x_dispatched_presses": dispatched,
            "pressed_after": len(self.keyboard.pressed),
            "x11_keymap_restored": restored,
            "elapsed_ms": (time.perf_counter_ns() - started) / 1_000_000.0,
        }


def key_name_to_code(name: str) -> int:
    normalized = name.strip().lower().replace("-", "_")
    if normalized in KEY_BY_NAME:
        return KEY_BY_NAME[normalized]
    if len(normalized) == 1 and normalized in CHAR_MAP:
        mapped, shifted = CHAR_MAP[normalized]
        if shifted:
            raise ValueError(f"key name {name!r} requires text input or an explicit shift combo")
        return KEY_BY_NAME[mapped]
    raise ValueError(f"unsupported key name {name!r}")


def text_to_codes(text: str) -> List[Tuple[int, bool]]:
    codes: List[Tuple[int, bool]] = []
    for char in text:
        mapped = CHAR_MAP.get(char)
        if mapped is None:
            raise ValueError(f"unsupported text character {char!r}")
        key_name, shifted = mapped
        codes.append((KEY_BY_NAME[key_name], shifted))
    return codes


def unsupported_text_chars(text: Any) -> List[str]:
    """Characters this device cannot type, in first-seen order.

    uinput carries keycodes, so the guest's keyboard layout decides which
    character a keycode produces; CHAR_MAP is exactly what the layout can
    reach. Anything else needs a keysym remap, which belongs to the X server,
    not here. Reporting them lets the caller reroute the request instead of
    dropping characters or killing the episode.
    """
    if not isinstance(text, str):
        return []
    missing: List[str] = []
    for char in text:
        if char not in CHAR_MAP and char not in missing:
            missing.append(char)
    return missing


def _key_codes(keys: Any, field: str) -> List[int]:
    if isinstance(keys, str):
        keys = [keys]
    if not isinstance(keys, list):
        raise ValueError(f"{field} must be a string or list of strings")
    return [key_name_to_code(str(key)) for key in keys]


def _expected_presses(keyboard: Dict[str, Any]) -> int:
    """Key presses a request should produce at the X server: one per typed
    character plus its shift, one per named key pressed."""
    total = 0
    text = keyboard.get("text")
    if isinstance(text, str):
        try:
            total += sum(2 if shifted else 1
                         for _, shifted in text_to_codes(text))
        except ValueError:
            return 0
    for field in ("keys", "keys_down"):
        keys = keyboard.get(field)
        if isinstance(keys, str):
            keys = [keys]
        if isinstance(keys, list):
            total += len(keys)
    return total


def unsupported_key_names(keyboard: Dict[str, Any]) -> List[str]:
    """Key names this device cannot press, in first-seen order.

    Same boundary as unsupported_text_chars: the uinput map reaches what the
    guest layout reaches, and names outside it (numpad, menu, lock keys) need
    a keysym the X server has to resolve. Reporting them lets the caller
    reroute rather than lose the keypress or kill the episode.
    """
    missing: List[str] = []
    for field in ("keys", "keys_down", "keys_up"):
        keys = keyboard.get(field)
        if keys is None:
            continue
        if isinstance(keys, str):
            keys = [keys]
        if not isinstance(keys, list):
            continue
        for key in keys:
            name = str(key)
            try:
                key_name_to_code(name)
            except ValueError:
                if name not in missing:
                    missing.append(name)
    return missing


class RequestHandler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        service: FastInputService = self.server.service  # type: ignore[attr-defined]
        for line in self.rfile:
            try:
                payload = json.loads(line.decode("utf-8"))
                response = service.handle(payload)
            except Exception as exc:
                response = {
                    "ok": False,
                    "error": str(exc),
                    "traceback": traceback.format_exc(limit=6),
                }
            self.wfile.write(json.dumps(response, separators=(",", ":")).encode("utf-8") + b"\n")
            self.wfile.flush()


class FastInputServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, server_address: Tuple[str, int], service: FastInputService):
        self.service = service
        super().__init__(server_address, RequestHandler)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--device", default="/dev/uinput")
    parser.add_argument("--device-name", default="GymAnything Fast Keyboard")
    parser.add_argument("--x11-display", default=os.environ.get("DISPLAY", ""))
    parser.add_argument("--require-x11", action="store_true")
    parser.add_argument("--x11-ack-timeout-ms", type=int, default=100)
    args = parser.parse_args()

    keyboard = UInputKeyboard(args.device, args.device_name)
    keyboard.open()
    x11 = None
    listener = None
    try:
        if args.x11_display:
            x11 = X11State(args.x11_display)
            try:
                listener = XInputListener(args.x11_display)
            except Exception as exc:
                # Without it, typing cannot be confirmed and a dropped burst
                # is silent, so say so rather than degrade quietly.
                print(json.dumps({"warning": "no XI2 listener", "error": repr(exc)}),
                      flush=True)
                if args.require_x11:
                    raise
        elif args.require_x11:
            raise RuntimeError("X11 display is required but DISPLAY is empty")
        service = FastInputService(keyboard, x11, args.x11_ack_timeout_ms,
                                   listener=listener)
        with FastInputServer((args.host, args.port), service) as server:
            print(
                json.dumps(
                    {
                        "event": "ready",
                        "version": VERSION,
                        "backend": "uinput",
                        "host": args.host,
                        "port": args.port,
                        "device_name": args.device_name,
                        "x11": x11 is not None,
                    },
                    separators=(",", ":"),
                ),
                flush=True,
            )
            server.serve_forever()
    finally:
        if x11:
            x11.close()
        keyboard.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
