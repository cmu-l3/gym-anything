from __future__ import annotations

import asyncio
import os
import socket
import subprocess
import threading
import time
from pathlib import Path
from typing import Optional


class QemuDbusDisplayCapture:
    def __init__(self, work_dir: Path):
        self.work_dir = work_dir
        self.bus_path = work_dir / "display-bus.sock"
        self.bus_address = f"unix:path={self.bus_path}"
        self._dbus_process: Optional[subprocess.Popen] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._thread: Optional[threading.Thread] = None
        self._registered = threading.Event()
        self._ready = threading.Event()
        self._error: Optional[BaseException] = None
        self._stop_requested = threading.Event()
        self._lock = threading.RLock()
        self._frame: Optional[bytearray] = None
        self._width = 0
        self._height = 0
        self._stride = 0
        self._pixman_format = 0
        self._last_update_ns = 0

    def start_bus(self) -> None:
        try:
            self.bus_path.unlink()
        except FileNotFoundError:
            pass
        out_path = self.work_dir / "display-dbus.out"
        with out_path.open("wb") as out:
            proc = subprocess.Popen(
                [
                    "dbus-daemon",
                    "--session",
                    f"--address={self.bus_address}",
                    "--fork",
                    "--print-address=1",
                    "--print-pid=1",
                ],
                stdout=out,
                stderr=subprocess.STDOUT,
            )
            proc.wait(timeout=5)
        if proc.returncode != 0:
            raise RuntimeError(out_path.read_text(errors="replace"))
        self._dbus_process = proc

    def start_listener(self, timeout: float = 10.0) -> None:
        self._thread = threading.Thread(target=self._run_loop, name="qemu-dbus-display", daemon=True)
        self._thread.start()
        if not self._registered.wait(timeout):
            self.stop()
            if self._error:
                raise RuntimeError(f"QEMU D-Bus display listener failed: {self._error}") from self._error
            raise TimeoutError("QEMU D-Bus display listener did not register")
        if self._error:
            raise RuntimeError(f"QEMU D-Bus display listener failed: {self._error}") from self._error

    def stop(self) -> None:
        self._stop_requested.set()
        if self._loop and self._loop.is_running():
            self._loop.call_soon_threadsafe(self._loop.stop)
        if self._thread:
            self._thread.join(timeout=2)
            self._thread = None
        if self._dbus_process and self._dbus_process.poll() is None:
            self._dbus_process.terminate()
        self._dbus_process = None

    def capture_image(self):
        from PIL import Image

        if self._frame is None:
            self._ready.wait(1.0)
        with self._lock:
            if self._frame is None:
                raise RuntimeError("QEMU D-Bus display has not delivered a frame")
            data = bytes(self._frame)
            width = self._width
            height = self._height
            stride = self._stride

        return Image.frombytes("RGB", (width, height), data, "raw", "BGRX", stride, 1)

    @property
    def last_update_ns(self) -> int:
        return self._last_update_ns

    def _run_loop(self) -> None:
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)
        try:
            self._loop.run_until_complete(self._register())
            self._registered.set()
            self._loop.run_forever()
        except BaseException as exc:
            self._error = exc
            self._ready.set()
        finally:
            pending = asyncio.all_tasks(self._loop)
            for task in pending:
                task.cancel()
            self._loop.close()

    async def _register(self) -> None:
        from dbus_next import Message, MessageType, Variant
        from dbus_next.aio import MessageBus
        from dbus_next.constants import BusType

        class PeerBus(MessageBus):
            def __init__(self, sock: socket.socket):
                self._provided_sock = sock
                super().__init__(
                    bus_address="unix:path=/tmp/nonexistent",
                    bus_type=BusType.SESSION,
                    negotiate_unix_fd=True,
                )

            def _setup_socket(self) -> None:
                self._sock = self._provided_sock
                self._stream = self._sock.makefile("rwb")
                self._fd = self._sock.fileno()

            async def connect_peer(self) -> "PeerBus":
                self._sock.setblocking(False)
                await self._authenticate()
                self._loop.add_reader(self._fd, self._message_reader)
                return self

        def handle_message(msg):
            if msg.message_type != MessageType.METHOD_CALL:
                return None
            if msg.path != "/org/qemu/Display1/Listener":
                return None

            if msg.interface == "org.freedesktop.DBus.Properties":
                if msg.member == "GetAll":
                    return Message.new_method_return(msg, "a{sv}", [{"Interfaces": Variant("as", [])}])
                if msg.member == "Get":
                    return Message.new_method_return(msg, "v", [Variant("as", [])])

            if msg.interface == "org.freedesktop.DBus.Introspectable":
                return Message.new_method_return(msg, "s", [_LISTENER_INTROSPECTION])

            if msg.interface != "org.qemu.Display1.Listener":
                return Message.new_method_return(msg)

            if msg.member == "Scanout":
                width, height, stride, pixman_format, data = msg.body
                payload = bytes(data)
                with self._lock:
                    self._width = int(width)
                    self._height = int(height)
                    self._stride = int(stride)
                    self._pixman_format = int(pixman_format)
                    self._frame = bytearray(payload)
                    self._last_update_ns = time.perf_counter_ns()
                self._ready.set()
            elif msg.member == "Update":
                x, y, width, height, stride, pixman_format, data = msg.body
                payload = bytes(data)
                with self._lock:
                    if self._frame is not None:
                        x = int(x)
                        y = int(y)
                        width = int(width)
                        height = int(height)
                        stride = int(stride)
                        for row in range(height):
                            src = row * stride
                            dst = (y + row) * self._stride + x * 4
                            self._frame[dst:dst + width * 4] = payload[src:src + width * 4]
                        self._pixman_format = int(pixman_format)
                        self._last_update_ns = time.perf_counter_ns()
                self._ready.set()
            elif msg.member in {"Disable", "MouseSet", "CursorDefine"}:
                pass
            return Message.new_method_return(msg)

        left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
        peer = PeerBus(left)
        peer.add_message_handler(handle_message)
        peer_task = asyncio.create_task(peer.connect_peer())

        bus = await MessageBus(bus_address=self.bus_address, negotiate_unix_fd=True).connect()
        try:
            deadline = time.time() + 10.0
            while True:
                probe = Message(
                    destination="org.qemu",
                    path="/org/qemu/Display1/VM",
                    interface="org.freedesktop.DBus.Properties",
                    member="Get",
                    signature="ss",
                    body=["org.qemu.Display1.VM", "ConsoleIDs"],
                )
                reply = await bus.call(probe)
                if reply.message_type != MessageType.ERROR:
                    break
                if time.time() >= deadline:
                    raise RuntimeError(f"{reply.error_name}: {reply.body}")
                await asyncio.sleep(0.05)

            register = Message(
                destination="org.qemu",
                path="/org/qemu/Display1/Console_0",
                interface="org.qemu.Display1.Console",
                member="RegisterListener",
                signature="h",
                body=[0],
                unix_fds=[right.fileno()],
            )
            reply = await bus.call(register)
            if reply.message_type == MessageType.ERROR:
                raise RuntimeError(f"{reply.error_name}: {reply.body}")
            await peer_task
        finally:
            right.close()
            bus.disconnect()


_LISTENER_INTROSPECTION = """\
<node>
  <interface name="org.qemu.Display1.Listener">
    <method name="Scanout">
      <arg type="u" direction="in"/>
      <arg type="u" direction="in"/>
      <arg type="u" direction="in"/>
      <arg type="u" direction="in"/>
      <arg type="ay" direction="in"/>
    </method>
    <method name="Update">
      <arg type="i" direction="in"/>
      <arg type="i" direction="in"/>
      <arg type="i" direction="in"/>
      <arg type="i" direction="in"/>
      <arg type="u" direction="in"/>
      <arg type="u" direction="in"/>
      <arg type="ay" direction="in"/>
    </method>
    <method name="Disable"/>
    <method name="MouseSet">
      <arg type="i" direction="in"/>
      <arg type="i" direction="in"/>
      <arg type="i" direction="in"/>
    </method>
    <method name="CursorDefine">
      <arg type="i" direction="in"/>
      <arg type="i" direction="in"/>
      <arg type="i" direction="in"/>
      <arg type="i" direction="in"/>
      <arg type="ay" direction="in"/>
    </method>
  </interface>
</node>
"""
