"""Low-latency client for the Modal Native X11 input and display service."""

from __future__ import annotations

import mmap
import os
import socket
import ssl
import struct
import threading
import time
from typing import Any, Dict, Iterable, List, Optional, Tuple

from .vnc_utils import char_needs_shift, char_to_keysym, key_to_keysym


FAST_IO_PORT = 5902

_MAGIC = 0x47414649
_VERSION = 1

_OP_HELLO = 1
_OP_PING = 2
_OP_SCREENSHOT = 3
_OP_ACTION = 4

_REQUEST_HEADER = struct.Struct("!IHHI")
_RESPONSE_HEADER = struct.Struct("!IHHII")
_HELLO_RESPONSE = struct.Struct("!IIII")
_SCREENSHOT_REQUEST = struct.Struct("!Q")
_SCREENSHOT_META = struct.Struct("!IIIIQQQ")
_ACTION_RESPONSE = struct.Struct("!Q")
_EVENT = struct.Struct("!BBHIii")

_EVENT_MOTION = 1
_EVENT_BUTTON = 2
_EVENT_KEY = 3
_FRAME_DATA_FOLLOWS = 1

_MAX_EVENTS = 4096
_MAX_RESPONSE_BYTES = 256 * 1024 * 1024
_DRAG_STEPS = 8

_LOCAL_FRAME_PATH = "/dev/shm/gym-anything-modal-native-fast-io"
_LOCAL_HEADER_SIZE = 4096
_LOCAL_PREFIX = struct.Struct("=4sIIIII")
_LOCAL_U64 = struct.Struct("=Q")
_LOCAL_SLOT_META = struct.Struct("=QQQQ")
_LOCAL_FRAME_MAGIC = b"GAFS"
_LOCAL_FRAME_SLOTS = 3


class ModalNativeFastIOError(RuntimeError):
    """The native fast-I/O service rejected or could not complete a request."""


WireEvent = Tuple[int, int, int, int, int]


def _key_keysym(key: str) -> int:
    normalized = key.strip()
    lower = normalized.lower()
    if lower.startswith("f") and lower[1:].isdigit():
        number = int(lower[1:])
        if 1 <= number <= 35:
            return 0xFFBD + number
    return key_to_keysym(normalized)


def _motion(x: int, y: int) -> WireEvent:
    return (_EVENT_MOTION, 0, 0, int(x), int(y))


def _button(button: int, down: bool) -> WireEvent:
    return (_EVENT_BUTTON, int(down), int(button), 0, 0)


def _key(keysym: int, down: bool) -> WireEvent:
    return (_EVENT_KEY, int(down), int(keysym), 0, 0)


def _tap_key(keysym: int) -> List[WireEvent]:
    return [_key(keysym, True), _key(keysym, False)]


def _text_events(text: str) -> List[WireEvent]:
    events: List[WireEvent] = []
    for char in text:
        if char in {"\n", "\r"}:
            events.extend(_tap_key(_key_keysym("Return")))
            continue
        if char == "\t":
            events.extend(_tap_key(_key_keysym("Tab")))
            continue
        if char == "\b":
            events.extend(_tap_key(_key_keysym("BackSpace")))
            continue

        shifted, base_key = char_needs_shift(char)
        if shifted:
            events.append(_key(_key_keysym("Shift_L"), True))
        events.extend(_tap_key(char_to_keysym(base_key)))
        if shifted:
            events.append(_key(_key_keysym("Shift_L"), False))
    return events


def events_for_action(action: Dict[str, Any]) -> List[WireEvent]:
    """Translate the public action shape into one atomic XTest event batch."""
    events: List[WireEvent] = []

    def click(x: int, y: int, button: int, count: int = 1) -> None:
        events.append(_motion(x, y))
        for _ in range(count):
            events.extend((_button(button, True), _button(button, False)))

    def drag(points: Iterable[Iterable[int]], button: int) -> None:
        start, end = points
        x1, y1 = (int(value) for value in start)
        x2, y2 = (int(value) for value in end)
        events.extend((_motion(x1, y1), _button(button, True)))
        for step in range(1, _DRAG_STEPS + 1):
            x = int(x1 + (x2 - x1) * step / _DRAG_STEPS)
            y = int(y1 + (y2 - y1) * step / _DRAG_STEPS)
            events.append(_motion(x, y))
        events.append(_button(button, False))

    mouse = action.get("mouse") or {}
    if "left_click" in mouse:
        click(*map(int, mouse["left_click"]), button=1)
    if "right_click" in mouse:
        click(*map(int, mouse["right_click"]), button=3)
    if "middle_click" in mouse:
        click(*map(int, mouse["middle_click"]), button=2)
    if "double_click" in mouse:
        click(*map(int, mouse["double_click"]), button=1, count=2)
    if "triple_click" in mouse:
        click(*map(int, mouse["triple_click"]), button=1, count=3)
    if "left_click_drag" in mouse:
        drag(mouse["left_click_drag"], button=1)
    if "right_click_drag" in mouse:
        drag(mouse["right_click_drag"], button=3)
    if "move" in mouse:
        events.append(_motion(*map(int, mouse["move"])))

    buttons = mouse.get("buttons") or {}
    for name, button, down in (
        ("left_down", 1, True),
        ("left_up", 1, False),
        ("middle_down", 2, True),
        ("middle_up", 2, False),
        ("right_down", 3, True),
        ("right_up", 3, False),
    ):
        if buttons.get(name):
            events.append(_button(button, down))

    if "scroll" in mouse:
        amount = int(mouse["scroll"])
        wheel_button = 5 if amount > 0 else 4
        for _ in range(abs(amount)):
            events.extend((_button(wheel_button, True), _button(wheel_button, False)))

    keyboard = action.get("keyboard") or {}
    if "text" in keyboard:
        events.extend(_text_events(str(keyboard["text"])))
    if "keys" in keyboard:
        keys = keyboard["keys"]
        key_list = [keys] if isinstance(keys, str) else list(keys)
        keysyms = [_key_keysym(str(value)) for value in key_list]
        events.extend(_key(keysym, True) for keysym in keysyms)
        events.extend(_key(keysym, False) for keysym in reversed(keysyms))
    if "keys_down" in keyboard:
        keys = keyboard["keys_down"]
        for value in ([keys] if isinstance(keys, str) else keys):
            events.append(_key(_key_keysym(str(value)), True))
    if "keys_up" in keyboard:
        keys = keyboard["keys_up"]
        for value in ([keys] if isinstance(keys, str) else keys):
            events.append(_key(_key_keysym(str(value)), False))

    if len(events) > _MAX_EVENTS:
        raise ValueError(
            f"Modal Native fast input action expands to {len(events)} events; "
            f"the maximum is {_MAX_EVENTS}"
        )
    return events


def _encode_events(events: List[WireEvent]) -> bytes:
    payload = bytearray(struct.pack("!I", len(events)))
    for kind, down, code, x, y in events:
        payload.extend(_EVENT.pack(kind, down, 0, code, x, y))
    return bytes(payload)


class ModalNativeFastIOClient:
    """Persistent authenticated client for the in-VM native X11 service."""

    def __init__(
        self,
        host: str,
        port: int,
        token: str,
        resolution: Tuple[int, int],
        *,
        timeout: float = 30.0,
        use_tls: bool = True,
    ):
        self.host = host
        self.port = int(port)
        self.token = token
        self.resolution = tuple(int(value) for value in resolution)
        self.timeout = float(timeout)
        self.use_tls = bool(use_tls)
        self._socket: Optional[socket.socket] = None
        self._lock = threading.RLock()
        self._frame_id = 0
        self._cached_image = None
        self._local_frame_map: Optional[mmap.mmap] = None
        self._last_local_ping_ns = 0
        self.last_frame_captured_ns = 0
        self.last_server_capture_ns = 0
        self.last_server_action_ns = 0

    def connect(self, retry_count: int = 10, retry_delay: float = 1.0) -> None:
        last_error: Optional[BaseException] = None
        for attempt in range(retry_count):
            try:
                with self._lock:
                    self._connect_locked()
                return
            except BaseException as exc:
                last_error = exc
                self.close()
                if attempt < retry_count - 1:
                    time.sleep(retry_delay)
        raise ModalNativeFastIOError(
            f"Could not connect to Modal Native fast I/O at {self.host}:{self.port}: "
            f"{last_error}"
        ) from last_error

    def _connect_locked(self) -> None:
        self._close_locked()
        raw_socket = socket.create_connection((self.host, self.port), self.timeout)
        raw_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        raw_socket.settimeout(self.timeout)
        try:
            if self.use_tls:
                context = ssl.create_default_context()
                connection = context.wrap_socket(raw_socket, server_hostname=self.host)
            else:
                connection = raw_socket
        except BaseException:
            raw_socket.close()
            raise
        self._socket = connection
        try:
            payload = self._request_locked(_OP_HELLO, self.token.encode("utf-8"))
            if len(payload) != _HELLO_RESPONSE.size:
                raise ModalNativeFastIOError("Malformed fast-I/O hello response")
            width, height, channels, capabilities = _HELLO_RESPONSE.unpack(payload)
            if (width, height) != self.resolution:
                raise ModalNativeFastIOError(
                    "Modal Native fast-I/O resolution mismatch: "
                    f"expected {self.resolution}, got {(width, height)}"
                )
            if channels != 3 or not capabilities & 1:
                raise ModalNativeFastIOError(
                    "Modal Native fast-I/O service lacks RGB/XShm/XTest support"
                )
            self._frame_id = 0
            self._cached_image = None
            self._open_local_frames_locked()
        except BaseException:
            self._close_locked()
            raise

    def close(self) -> None:
        with self._lock:
            self._close_locked()

    def _close_locked(self) -> None:
        self._cached_image = None
        local_frame_map, self._local_frame_map = self._local_frame_map, None
        if local_frame_map is not None:
            try:
                local_frame_map.close()
            except OSError:
                pass
        connection, self._socket = self._socket, None
        if connection is not None:
            try:
                connection.close()
            except OSError:
                pass

    def _open_local_frames_locked(self) -> None:
        if self.host not in {"127.0.0.1", "localhost", "::1"}:
            return
        path = os.environ.get(
            "GYM_ANYTHING_MODAL_NATIVE_FAST_IO_SHM", _LOCAL_FRAME_PATH
        )
        try:
            fd = os.open(path, os.O_RDONLY)
        except OSError:
            return
        try:
            local_frame_map = mmap.mmap(fd, 0, access=mmap.ACCESS_READ)
        finally:
            os.close(fd)
        try:
            magic, version, width, height, stride, slots = _LOCAL_PREFIX.unpack_from(
                local_frame_map, 0
            )
            required_size = _LOCAL_HEADER_SIZE + stride * height * slots
            if (
                magic != _LOCAL_FRAME_MAGIC
                or version != _VERSION
                or (width, height) != self.resolution
                or stride != width * 3
                or slots != _LOCAL_FRAME_SLOTS
                or len(local_frame_map) < required_size
            ):
                raise ModalNativeFastIOError(
                    "Modal Native local fast-frame metadata is incompatible"
                )
        except BaseException:
            local_frame_map.close()
            raise
        self._local_frame_map = local_frame_map
        self._last_local_ping_ns = time.monotonic_ns()

    @property
    def is_connected(self) -> bool:
        return self._socket is not None

    def _recv_exact_locked(self, size: int) -> bytearray:
        if self._socket is None:
            raise ConnectionError("Modal Native fast-I/O socket is not connected")
        data = bytearray(size)
        view = memoryview(data)
        offset = 0
        while offset < size:
            received = self._socket.recv_into(view[offset:])
            if received == 0:
                raise ConnectionError("Modal Native fast-I/O service closed the connection")
            offset += received
        return data

    def _request_locked(self, opcode: int, payload: bytes = b"") -> bytearray:
        if self._socket is None:
            raise ConnectionError("Modal Native fast-I/O socket is not connected")
        self._socket.sendall(
            _REQUEST_HEADER.pack(_MAGIC, _VERSION, opcode, len(payload)) + payload
        )
        header = self._recv_exact_locked(_RESPONSE_HEADER.size)
        magic, version, response_opcode, status, length = _RESPONSE_HEADER.unpack(header)
        if magic != _MAGIC or version != _VERSION or response_opcode != opcode:
            raise ModalNativeFastIOError("Malformed fast-I/O response header")
        if length > _MAX_RESPONSE_BYTES:
            raise ModalNativeFastIOError(
                f"Fast-I/O response is unreasonably large: {length} bytes"
            )
        response = self._recv_exact_locked(length)
        if status:
            message = bytes(response).decode("utf-8", errors="replace")
            raise ModalNativeFastIOError(message or f"Fast-I/O service error {status}")
        return response

    def _request(self, opcode: int, payload: bytes = b"", *, retry_safe: bool) -> bytearray:
        with self._lock:
            if self._socket is None:
                self._connect_locked()
            try:
                return self._request_locked(opcode, payload)
            except (OSError, ConnectionError, ssl.SSLError) as exc:
                self._close_locked()
                if retry_safe:
                    self._connect_locked()
                    return self._request_locked(opcode, payload)
                raise ModalNativeFastIOError(
                    "Modal Native fast input connection failed after dispatch; "
                    "the action was not retried because its execution state is unknown"
                ) from exc

    def ping(self) -> None:
        self._request(_OP_PING, retry_safe=True)

    def inject_action(self, action: Dict[str, Any]) -> None:
        events = events_for_action(action)
        if not events:
            return
        response = self._request(
            _OP_ACTION, _encode_events(events), retry_safe=False
        )
        if len(response) != _ACTION_RESPONSE.size:
            raise ModalNativeFastIOError("Malformed fast-input acknowledgement")
        (self.last_server_action_ns,) = _ACTION_RESPONSE.unpack(response)

    def capture_image(self):
        from PIL import Image

        with self._lock:
            if self._local_frame_map is not None:
                now_ns = time.monotonic_ns()
                if now_ns - self._last_local_ping_ns >= 1_000_000_000:
                    self._request(_OP_PING, retry_safe=True)
                    self._last_local_ping_ns = now_ns
                if self._local_frame_map is not None:
                    return self._capture_local_image_locked(Image)
            return self._capture_remote_image_locked(Image)

    def _capture_remote_image_locked(self, image_class):
        response = self._request(
            _OP_SCREENSHOT,
            _SCREENSHOT_REQUEST.pack(self._frame_id),
            retry_safe=True,
        )
        if len(response) < _SCREENSHOT_META.size:
            raise ModalNativeFastIOError("Malformed fast-I/O screenshot response")
        (
            width,
            height,
            stride,
            flags,
            frame_id,
            captured_ns,
            capture_elapsed_ns,
        ) = _SCREENSHOT_META.unpack(response[: _SCREENSHOT_META.size])
        if (width, height) != self.resolution or stride != width * 3:
            raise ModalNativeFastIOError(
                "Modal Native fast-I/O frame geometry changed unexpectedly: "
                f"{width}x{height}, stride={stride}"
            )

        if flags & _FRAME_DATA_FOLLOWS:
            expected = _SCREENSHOT_META.size + stride * height
            if len(response) != expected:
                raise ModalNativeFastIOError(
                    f"Malformed fast-I/O frame: expected {expected} bytes, "
                    f"received {len(response)}"
                )
            frame_view = memoryview(response)[_SCREENSHOT_META.size :]
            try:
                self._cached_image = image_class.frombytes(
                    "RGB",
                    (width, height),
                    frame_view,
                    "raw",
                    "RGB",
                    stride,
                    1,
                )
            finally:
                frame_view.release()
        elif len(response) != _SCREENSHOT_META.size:
            raise ModalNativeFastIOError("Unexpected data in unchanged screenshot response")

        missing_changed_frame = frame_id != self._frame_id and not (
            flags & _FRAME_DATA_FOLLOWS
        )
        if self._cached_image is None or missing_changed_frame:
            raise ModalNativeFastIOError("Fast-I/O service omitted required frame data")

        self._frame_id = frame_id
        self.last_frame_captured_ns = captured_ns
        self.last_server_capture_ns = capture_elapsed_ns
        return self._cached_image.copy()

    def _capture_local_image_locked(self, image_class):
        local_frame_map = self._local_frame_map
        if local_frame_map is None:
            raise ModalNativeFastIOError("Local fast-frame mapping is unavailable")
        width, height = self.resolution
        stride = width * 3
        frame_size = stride * height
        for _ in range(50):
            (slot_index,) = _LOCAL_U64.unpack_from(local_frame_map, 24)
            if slot_index >= _LOCAL_FRAME_SLOTS:
                time.sleep(0)
                continue
            metadata_offset = 32 + slot_index * _LOCAL_SLOT_META.size
            sequence, frame_id, captured_ns, capture_elapsed_ns = (
                _LOCAL_SLOT_META.unpack_from(local_frame_map, metadata_offset)
            )
            if sequence & 1:
                time.sleep(0)
                continue
            if frame_id == self._frame_id and self._cached_image is not None:
                self.last_frame_captured_ns = captured_ns
                self.last_server_capture_ns = capture_elapsed_ns
                return self._cached_image.copy()
            frame_offset = _LOCAL_HEADER_SIZE + slot_index * frame_size
            frame_view = memoryview(local_frame_map)[
                frame_offset : frame_offset + frame_size
            ]
            try:
                image = image_class.frombytes(
                    "RGB",
                    (width, height),
                    frame_view,
                    "raw",
                    "RGB",
                    stride,
                    1,
                )
            finally:
                frame_view.release()
            (sequence_after,) = _LOCAL_U64.unpack_from(
                local_frame_map, metadata_offset
            )
            if sequence == sequence_after and not sequence_after & 1:
                self._frame_id = frame_id
                self.last_frame_captured_ns = captured_ns
                self.last_server_capture_ns = capture_elapsed_ns
                self._cached_image = image
                return image.copy()
        raise ModalNativeFastIOError(
            "Could not read a stable Modal Native shared-memory frame"
        )


__all__ = [
    "FAST_IO_PORT",
    "ModalNativeFastIOClient",
    "ModalNativeFastIOError",
    "events_for_action",
]
