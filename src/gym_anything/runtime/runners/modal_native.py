"""Native Linux runner backed directly by Modal VM Sandboxes."""

from __future__ import annotations

import dataclasses
import hashlib
import json
import os
import re
import shlex
import tarfile
import tempfile
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Generator, List, Optional

from ...config.presets import is_android_preset, is_windows_preset
from ...contracts import RunnerRuntimeInfo
from ...specs import EnvSpec, MountSpec
from .base import BaseRunner
from .modal_native_image import MODAL_NATIVE_IMAGE_FINGERPRINT, build_modal_native_image
from .vnc_utils import VNCConnection, VNCConnectionPool


VNC_PORT = 5901
_MIN_MODAL_VERSION = (1, 4)
_CHECKPOINT_LEVELS = {"pre_start", "post_start", "post_task"}


def _version_tuple(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", value)[:3])


def _mount_value(mount: MountSpec | Dict[str, Any], name: str, default: Any = None) -> Any:
    if isinstance(mount, dict):
        return mount.get(name, default)
    return getattr(mount, name, default)


class ModalNativeRunner(BaseRunner):
    """Run an existing Linux CUA environment directly in a Modal VM Sandbox."""

    def __init__(self, spec: EnvSpec):
        super().__init__(spec)
        self._validate_spec()

        try:
            import modal
        except ImportError as exc:
            raise RuntimeError(
                "ModalNativeRunner requires modal>=1.4; install with "
                "pip install 'gym-anything[modal_native]'"
            ) from exc

        version = _version_tuple(getattr(modal, "__version__", "0"))
        if version < _MIN_MODAL_VERSION:
            raise RuntimeError(
                "ModalNativeRunner requires modal>=1.4 for Sandbox filesystem access "
                f"(found {getattr(modal, '__version__', 'unknown')})"
            )

        self._modal = modal
        self.app_name = os.environ.get(
            "GYM_ANYTHING_MODAL_NATIVE_APP", "gym-anything-modal-native-runner"
        )
        self.checkpoint_dict_name = os.environ.get(
            "GYM_ANYTHING_MODAL_NATIVE_CHECKPOINT_DICT",
            "gym-anything-modal-native-checkpoints",
        )
        self.sandbox_timeout = int(
            os.environ.get("GYM_ANYTHING_MODAL_NATIVE_TIMEOUT", "10800")
        )
        self.desktop_timeout = int(
            os.environ.get("GYM_ANYTHING_MODAL_NATIVE_DESKTOP_TIMEOUT", "300")
        )
        self.snapshot_timeout = int(
            os.environ.get("GYM_ANYTHING_MODAL_NATIVE_SNAPSHOT_TIMEOUT", "600")
        )
        self.lock_timeout = float(
            os.environ.get("GYM_ANYTHING_MODAL_NATIVE_LOCK_TIMEOUT", "1800")
        )
        self.lock_poll_seconds = float(
            os.environ.get("GYM_ANYTHING_MODAL_NATIVE_LOCK_POLL_SECONDS", "2")
        )
        self.snapshot_ttl = self._snapshot_ttl_from_env()

        self.cpu = float(spec.resources.cpu or 4)
        self.memory_mb = int(spec.resources.mem_gb or 8) * 1024
        if self.cpu <= 0 or self.memory_mb <= 0:
            raise ValueError(
                f"Modal Native resources must be positive, got cpu={self.cpu}, "
                f"memory={self.memory_mb} MiB"
            )
        if not 1 <= self.sandbox_timeout <= 86400:
            raise ValueError(
                "GYM_ANYTHING_MODAL_NATIVE_TIMEOUT must be between 1 and 86400 seconds"
            )
        screen_spec = next(
            (item for item in spec.observation if item.type == "rgb_screen"), None
        )
        self.resolution = tuple(
            screen_spec.resolution if screen_spec and screen_spec.resolution else (1920, 1080)
        )
        if len(self.resolution) != 2 or min(self.resolution) <= 0:
            raise ValueError(f"Invalid screen resolution for ModalNativeRunner: {self.resolution}")

        self.vnc_password = spec.vnc.password or "password"
        self.vnc_port: Optional[int] = None
        self.vnc_url: Optional[str] = None
        self.instance_name: Optional[str] = None

        self._app = None
        self._checkpoint_dict = None
        self._sandbox = None
        self._vnc_tunnel: Optional[tuple[str, int]] = None
        self._vnc_pool: Optional[VNCConnectionPool] = None
        self._running = False
        self._checkpoint_cache_level: Optional[str] = None
        self._checkpoint_task_id: Optional[str] = None
        self._env_hash: Optional[str] = None

    def _validate_spec(self) -> None:
        os_type = (getattr(self.spec, "os_type", None) or "linux").lower()
        base = getattr(self.spec, "base", None) or ""
        if (
            os_type != "linux"
            or is_android_preset(base)
            or is_windows_preset(base)
            or "macos" in base.lower()
        ):
            raise ValueError(
                "ModalNativeRunner currently supports Linux environments only; "
                f"environment {self.spec.id!r} targets {os_type!r}"
            )
        if (self.spec.resources.gpu or 0) > 0:
            raise ValueError(
                "ModalNativeRunner does not support GPU environments because Modal VM "
                f"Sandboxes currently have no GPU support ({self.spec.id!r} requests "
                f"gpu={self.spec.resources.gpu})"
            )

    @staticmethod
    def _snapshot_ttl_from_env() -> Optional[int]:
        value = os.environ.get("GYM_ANYTHING_MODAL_NATIVE_SNAPSHOT_TTL", "none")
        if value.strip().lower() in {"", "none", "indefinite"}:
            return None
        ttl = int(value)
        if ttl <= 0:
            raise ValueError("GYM_ANYTHING_MODAL_NATIVE_SNAPSHOT_TTL must be positive or 'none'")
        return ttl

    def supports_checkpoint_caching(self) -> bool:
        return True

    def supports_savevm(self) -> bool:
        return False

    def supports_fast_io(self) -> bool:
        return True

    def default_exec_env(self) -> Dict[str, str]:
        env = {
            "DISPLAY": ":1",
            "XAUTHORITY": "/home/ga/.Xauthority",
        }
        env.update(super().default_exec_env())
        return env

    def _ensure_modal_resources(self) -> None:
        if self._app is None:
            self._app = self._modal.App.lookup(self.app_name, create_if_missing=True)
        if self._checkpoint_dict is None:
            self._checkpoint_dict = self._modal.Dict.from_name(
                self.checkpoint_dict_name, create_if_missing=True
            )

    def _sandbox_create_kwargs(self) -> Dict[str, Any]:
        kwargs: Dict[str, Any] = {
            "app": self._app,
            "cpu": (self.cpu, self.cpu),
            "memory": (self.memory_mb, self.memory_mb),
            "timeout": self.sandbox_timeout,
            "unencrypted_ports": [VNC_PORT],
            "experimental_options": {"vm_runtime": True},
            "env": {
                "GYM_ANYTHING_VNC_GEOMETRY": f"{self.resolution[0]}x{self.resolution[1]}",
                "GYM_ANYTHING_VNC_PASSWORD": self.vnc_password,
            },
            "tags": {
                "gym-anything-runner": "modal-native",
                "gym-anything-env": re.sub(r"[^A-Za-z0-9_.-]", "_", self.spec.id)[:64],
            },
        }
        if self.spec.resources.net is False:
            kwargs["outbound_cidr_allowlist"] = []
            kwargs["outbound_domain_allowlist"] = []
        region = os.environ.get("GYM_ANYTHING_MODAL_NATIVE_REGION")
        if region:
            kwargs["region"] = region
        inbound = os.environ.get("GYM_ANYTHING_MODAL_NATIVE_INBOUND_CIDR")
        if inbound:
            kwargs["inbound_cidr_allowlist"] = [
                item.strip() for item in inbound.split(",") if item.strip()
            ]
        return kwargs

    def _create_sandbox(self, image=None) -> None:
        self._ensure_modal_resources()
        image = image or build_modal_native_image(self._modal)
        self._report_start("modal_native_sandbox", "creating Linux VM Sandbox")
        self._sandbox = self._modal.Sandbox.create(
            "/usr/local/sbin/ga-modal-native-bootstrap",
            image=image,
            **self._sandbox_create_kwargs(),
        )
        self.instance_name = self._sandbox.object_id
        tunnel = self._sandbox.tunnels()[VNC_PORT]
        self._vnc_tunnel = tuple(tunnel.tcp_socket)
        self.vnc_url = f"vnc://{self._vnc_tunnel[0]}:{self._vnc_tunnel[1]}"
        self.vnc_port = int(self._vnc_tunnel[1])
        self._report_done("modal_native_sandbox", self.instance_name or "")

    def _start_with_image(self, image=None, seed: Optional[int] = None) -> None:
        del seed
        if self._sandbox is not None:
            raise RuntimeError("ModalNativeRunner already has an active Sandbox")
        try:
            self._create_sandbox(image=image)
            self._wait_for_desktop()
            self._setup_mounts()
            self._connect_vnc()
            self._running = True
        except BaseException:
            self.stop()
            raise

    def start(self, seed: Optional[int] = None) -> None:
        if self._running:
            return
        self._start_with_image(seed=seed)

    def stop(self) -> None:
        pool, self._vnc_pool = self._vnc_pool, None
        if pool is not None:
            try:
                pool.close()
            except Exception as exc:
                self._report_log(f"Modal Native VNC cleanup failed: {exc}")

        sandbox, self._sandbox = self._sandbox, None
        if sandbox is not None:
            try:
                sandbox.terminate()
            except Exception as exc:
                self._report_log(f"Modal Native Sandbox termination failed: {exc}")

        self._running = False
        self._vnc_tunnel = None
        self.vnc_port = None
        self.vnc_url = None
        self.instance_name = None

    def _exec_process(
        self,
        cmd: str,
        *,
        env: Optional[Dict[str, str]] = None,
        user: Optional[str] = None,
        use_pty: bool = True,
        timeout: Optional[int] = 600,
        text: bool = True,
    ):
        if self._sandbox is None:
            raise RuntimeError("ModalNativeRunner is not started")
        command = ["/usr/local/sbin/ga-nsenter"]
        if user and user != "root":
            command.extend(["runuser", "-u", user, "-p", "--"])
        command.extend(["bash", "-lc", cmd])
        merged_env = self.merge_exec_env(env)
        return self._sandbox.exec(
            *command,
            env=merged_env or None,
            pty=use_pty,
            timeout=timeout,
            text=text,
        )

    @staticmethod
    def _process_stream_value(stream, *, binary: bool):
        if stream is None:
            return b"" if binary else ""
        value = stream.read()
        if binary:
            return value if isinstance(value, bytes) else str(value).encode()
        return value.decode(errors="replace") if isinstance(value, bytes) else value

    def exec(
        self,
        cmd: str,
        env: Optional[Dict[str, str]] = None,
        user: Optional[str] = None,
        use_pty: bool = True,
        timeout: int = 600,
    ) -> int:
        proc = self._exec_process(
            cmd, env=env, user=user, use_pty=use_pty, timeout=timeout
        )
        code = proc.wait()
        if code != 0:
            error = self._process_stream_value(getattr(proc, "stderr", None), binary=False)
            if error:
                self._report_log(f"Modal Native exec failed: {error[:500]}")
        return int(code)

    def exec_async(
        self,
        cmd: str,
        env: Optional[Dict[str, str]] = None,
        stdout=None,
        stderr=None,
    ):
        if stdout is not None or stderr is not None:
            raise NotImplementedError(
                "ModalNativeRunner does not expose redirected asynchronous process streams"
            )
        return self._exec_process(cmd, env=env, use_pty=False, timeout=None)

    def exec_capture(self, cmd: str) -> str:
        proc = self._exec_process(cmd, use_pty=False, timeout=600, text=True)
        output = self._process_stream_value(proc.stdout, binary=False)
        error = self._process_stream_value(proc.stderr, binary=False)
        code = proc.wait()
        if code != 0 and error:
            self._report_log(f"Modal Native exec_capture failed: {error[:500]}")
        return output

    def exec_capture_bytes(self, cmd: str) -> bytes:
        proc = self._exec_process(cmd, use_pty=False, timeout=600, text=False)
        output = self._process_stream_value(proc.stdout, binary=True)
        proc.wait()
        return output

    def run_reset(self, reset_script: str, seed: Optional[int] = None) -> None:
        env = {"SEED": str(seed)} if seed is not None else None
        self.exec(f"bash -lc {shlex.quote(reset_script)}", env=env)

    def run_task_init(self, init_script: str) -> None:
        self.exec(f"bash -lc {shlex.quote(init_script)}", use_pty=False)

    def _wait_for_desktop(self) -> None:
        self._report_start("modal_native_desktop", "waiting for systemd and VNC")
        deadline = time.monotonic() + self.desktop_timeout
        last_error = ""
        while time.monotonic() < deadline:
            try:
                proc = self._exec_process(
                    "timeout --signal=TERM --kill-after=1s 5s "
                    "systemctl is-active ga-vnc.service",
                    use_pty=False,
                    timeout=10,
                )
                output = self._process_stream_value(proc.stdout, binary=False).strip()
                code = proc.wait()
                if code == 0 and output == "active":
                    self._report_done("modal_native_desktop")
                    return
                last_error = output or f"exit {code}"
            except Exception as exc:
                last_error = str(exc)
            time.sleep(2)
        raise RuntimeError(
            "Modal Native desktop did not become ready within "
            f"{self.desktop_timeout}s: {last_error}"
        )

    def _connect_vnc(self) -> None:
        if self._vnc_tunnel is None:
            raise RuntimeError("Modal Native VNC tunnel is unavailable")
        host, port = self._vnc_tunnel
        self._vnc_pool = VNCConnectionPool(host, port, password=self.vnc_password)
        connection = self._vnc_pool.get_connection(retry_count=10, retry_delay=2.0)
        if connection is None:
            raise RuntimeError("Could not connect to the Modal Native VNC desktop")
        if tuple(connection.resolution) != tuple(self.resolution):
            raise RuntimeError(
                "Modal Native VNC resolution mismatch: "
                f"expected {self.resolution}, got {connection.resolution}"
            )

    def _vnc_connection(self) -> VNCConnection:
        if self._vnc_pool is None:
            raise RuntimeError("Modal Native VNC is not initialized")
        connection = self._vnc_pool.get_connection()
        if connection is None:
            raise RuntimeError("Modal Native VNC connection failed")
        return connection

    def inject_action(self, action: Dict[str, Any]) -> None:
        connection = self._vnc_connection()
        mouse = action.get("mouse") or {}
        if "left_click" in mouse:
            x, y = mouse["left_click"]
            connection.send_mouse_click(int(x), int(y), button=1)
        if "right_click" in mouse:
            x, y = mouse["right_click"]
            connection.send_mouse_click(int(x), int(y), button=3)
        if "middle_click" in mouse:
            x, y = mouse["middle_click"]
            connection.send_mouse_click(int(x), int(y), button=2)
        if "double_click" in mouse:
            x, y = mouse["double_click"]
            connection.send_mouse_click(int(x), int(y), button=1, double=True)
        if "triple_click" in mouse:
            x, y = mouse["triple_click"]
            for _ in range(3):
                connection.send_mouse_click(int(x), int(y), button=1)
        if "left_click_drag" in mouse:
            (x1, y1), (x2, y2) = mouse["left_click_drag"]
            connection.send_mouse_drag(int(x1), int(y1), int(x2), int(y2), button=1)
        if "right_click_drag" in mouse:
            (x1, y1), (x2, y2) = mouse["right_click_drag"]
            connection.send_mouse_drag(int(x1), int(y1), int(x2), int(y2), button=3)
        if "move" in mouse:
            x, y = mouse["move"]
            connection.send_mouse_move(int(x), int(y))

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
                connection.send_mouse_button(button=button, down=down)
        if "scroll" in mouse:
            x, y = connection.pointer_position
            connection.send_scroll(x, y, -int(mouse["scroll"]))

        keyboard = action.get("keyboard") or {}
        if "text" in keyboard:
            connection.type_text(str(keyboard["text"]))
        if "keys" in keyboard:
            keys = keyboard["keys"]
            connection.send_key_combo([str(key) for key in ([keys] if isinstance(keys, str) else keys)])
        if "keys_down" in keyboard:
            keys = keyboard["keys_down"]
            for key in ([keys] if isinstance(keys, str) else keys):
                connection.send_key(str(key), down=True)
        if "keys_up" in keyboard:
            keys = keyboard["keys_up"]
            for key in ([keys] if isinstance(keys, str) else keys):
                connection.send_key(str(key), down=False)

    def capture_observation(self) -> Dict[str, Any]:
        screen = next(
            (item for item in self.spec.observation if item.type == "rgb_screen"), None
        )
        if screen is None:
            return {}
        return {
            "screen": {
                "format": "rgb",
                "fps": screen.fps,
                "resolution": self.resolution,
            }
        }

    def capture_screenshot(self, host_path) -> bool:
        data = self._vnc_connection().capture_screenshot(Path(host_path))
        return data is not None

    def capture_screenshot_image(self):
        import io

        from PIL import Image

        data = self._vnc_connection().capture_screenshot()
        if data is None:
            raise RuntimeError("Modal Native screenshot capture failed")
        image = Image.open(io.BytesIO(data))
        image.load()
        return image.convert("RGB")

    def capture_audio_raw(self, duration_sec: float, rate: int, channels: int) -> bytes:
        del duration_sec, rate, channels
        return b""

    def capture_ui_tree(self) -> str:
        return ""

    def _setup_mounts(self) -> None:
        mounts = sorted(
            self.spec.mounts or [],
            key=lambda item: len(Path(str(_mount_value(item, "target", "/"))).parts),
        )
        if not mounts:
            return
        self._report_start("modal_native_mounts", f"copying {len(mounts)} mount trees")
        for mount in mounts:
            source_value = str(_mount_value(mount, "source", ""))
            target = str(_mount_value(mount, "target", ""))
            source = Path(source_value).expanduser()
            if not source.is_absolute():
                source = Path.cwd() / source
            if not source.exists() and not source.is_symlink():
                self._report_log(f"Modal Native mount source does not exist: {source}")
                continue
            parent = str(Path(target).parent)
            if target == "/":
                self.exec("mkdir -p -- /", use_pty=False)
            else:
                self.exec(
                    f"rm -rf -- {shlex.quote(target)} && mkdir -p -- {shlex.quote(parent)}",
                    use_pty=False,
                )
            self.copy_to(str(source), target)
        self._report_done("modal_native_mounts")

    def copy_to(self, host_src: str, container_dst: str) -> None:
        source = Path(host_src)
        if not source.exists() and not source.is_symlink():
            raise FileNotFoundError(f"Source not found: {source}")
        if self._sandbox is None:
            raise RuntimeError("ModalNativeRunner is not started")

        if source.is_dir():
            self.exec(f"mkdir -p -- {shlex.quote(container_dst)}", use_pty=False)
            proc = self._exec_process(
                f"tar -xzf - --no-same-owner -C {shlex.quote(container_dst)}",
                use_pty=False,
                timeout=1800,
                text=False,
            )
            with tempfile.TemporaryFile() as archive:
                with tarfile.open(fileobj=archive, mode="w:gz", dereference=False) as tar:
                    for child in sorted(source.iterdir(), key=lambda item: item.name):
                        tar.add(child, arcname=child.name, recursive=True)
                archive.seek(0)
                while True:
                    chunk = archive.read(1 << 20)
                    if not chunk:
                        break
                    proc.stdin.write(chunk)
                    proc.stdin.drain()
            proc.stdin.write_eof()
            proc.stdin.drain()
            code = proc.wait()
            if code != 0:
                error = self._process_stream_value(proc.stderr, binary=True)
                raise RuntimeError(f"Modal Native directory upload failed: {error[:500]!r}")
            mode = source.stat().st_mode & 0o7777
            self.exec(
                f"chmod {mode:o} -- {shlex.quote(container_dst)} && "
                f"chown -hR ga:ga -- {shlex.quote(container_dst)}",
                use_pty=False,
            )
            return

        parent = str(Path(container_dst).parent)
        self._sandbox.filesystem.make_directory(parent)
        self._sandbox.filesystem.copy_from_local(source, container_dst)
        mode = source.stat().st_mode & 0o7777
        self.exec(
            f"chmod {mode:o} -- {shlex.quote(container_dst)} && "
            f"chown -h ga:ga -- {shlex.quote(container_dst)}",
            use_pty=False,
        )

    @staticmethod
    def _safe_extract(archive: tarfile.TarFile, destination: Path) -> None:
        root = destination.resolve()
        for member in archive.getmembers():
            member_path = (destination / member.name).resolve()
            if member_path != root and root not in member_path.parents:
                raise RuntimeError(f"Unsafe archive path from Sandbox: {member.name}")
            if member.issym() or member.islnk():
                link_path = (member_path.parent / member.linkname).resolve()
                if link_path != root and root not in link_path.parents:
                    raise RuntimeError(f"Unsafe archive link from Sandbox: {member.name}")
        archive.extractall(destination)

    def copy_from(self, container_src: str, host_dst: str) -> None:
        if self._sandbox is None:
            raise RuntimeError("ModalNativeRunner is not started")
        kind = self.exec_capture(
            f"if [ -d {shlex.quote(container_src)} ]; then printf directory; "
            f"elif [ -e {shlex.quote(container_src)} ] || [ -L {shlex.quote(container_src)} ]; "
            "then printf file; else exit 44; fi"
        )
        if kind == "file":
            destination = Path(host_dst)
            destination.parent.mkdir(parents=True, exist_ok=True)
            self._sandbox.filesystem.copy_to_local(container_src, destination)
            return
        if kind != "directory":
            raise FileNotFoundError(f"Source not found: {container_src}")

        remote_archive = f"/tmp/ga_copy_{uuid.uuid4().hex}.tar.gz"
        code = self.exec(
            f"tar -czf {shlex.quote(remote_archive)} -C {shlex.quote(container_src)} .",
            use_pty=False,
            timeout=1800,
        )
        if code != 0:
            raise RuntimeError(f"Could not archive Sandbox directory: {container_src}")
        destination = Path(host_dst)
        destination.mkdir(parents=True, exist_ok=True)
        try:
            with tempfile.TemporaryDirectory() as temp_dir:
                local_archive = Path(temp_dir) / "archive.tar.gz"
                self._sandbox.filesystem.copy_to_local(remote_archive, local_archive)
                with tarfile.open(local_archive, mode="r:gz") as archive:
                    self._safe_extract(archive, destination)
        finally:
            try:
                self._sandbox.filesystem.remove(remote_archive)
            except Exception:
                pass

    def put_file(self, host_path) -> str:
        source = Path(host_path)
        destination = f"/tmp/ga_{uuid.uuid4().hex[:8]}_{source.name}"
        self.copy_to(str(source), destination)
        return destination

    def to_container_path(self, host_path):
        return str(host_path)

    def save_state(self, save_paths: Optional[List[str]]) -> str:
        paths = save_paths or ["/workspace"]
        destination = f"/tmp/ga_snapshot_{uuid.uuid4().hex[:8]}.tar"
        quoted = " ".join(shlex.quote(path) for path in paths)
        self.exec(
            f"tar -cf {shlex.quote(destination)} {quoted} 2>/dev/null || true",
            use_pty=False,
            timeout=1800,
        )
        return destination

    def load_state(self, snapshot_container_path: str) -> None:
        self.exec(
            f"tar -xf {shlex.quote(snapshot_container_path)} -C / 2>/dev/null || true",
            use_pty=False,
            timeout=1800,
        )

    def _hash_mount_source(self, source: Path) -> str:
        digest = hashlib.sha256()
        if not source.exists() and not source.is_symlink():
            digest.update(b"missing")
            return digest.hexdigest()
        paths = [source]
        if source.is_dir():
            paths.extend(sorted(source.rglob("*"), key=lambda item: str(item.relative_to(source))))
        for path in paths:
            relative = "." if path == source else str(path.relative_to(source))
            digest.update(relative.encode("utf-8", errors="surrogateescape"))
            if path.is_symlink():
                digest.update(b"link\0")
                digest.update(os.readlink(path).encode("utf-8", errors="surrogateescape"))
            elif path.is_dir():
                digest.update(b"dir\0")
            elif path.is_file():
                digest.update(b"file\0")
                with path.open("rb") as handle:
                    while True:
                        chunk = handle.read(1 << 20)
                        if not chunk:
                            break
                        digest.update(chunk)
        return digest.hexdigest()

    def _compute_env_hash(self) -> str:
        if self._env_hash is not None:
            return self._env_hash
        mounts = []
        for mount in self.spec.mounts or []:
            source_value = str(_mount_value(mount, "source", ""))
            source = Path(source_value).expanduser()
            if not source.is_absolute():
                source = Path.cwd() / source
            mounts.append(
                {
                    "source": source_value,
                    "target": _mount_value(mount, "target", ""),
                    "mode": _mount_value(mount, "mode", "ro"),
                    "content": self._hash_mount_source(source),
                }
            )
        security = self.spec.security
        payload = {
            "image_schema": MODAL_NATIVE_IMAGE_FINGERPRINT,
            "id": self.spec.id,
            "version": self.spec.version,
            "base": self.spec.base,
            "image": self.spec.image,
            "dockerfile": self.spec.dockerfile,
            "entrypoint": self.spec.entrypoint,
            "hooks": self.spec.hooks,
            "user_accounts": [dataclasses.asdict(item) for item in self.spec.user_accounts],
            "security": {
                "user": security.user,
                "privileged": security.privileged,
                "use_systemd": security.use_systemd,
                "resolved_env": security.resolved_env,
            },
            "mounts": mounts,
        }
        encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
        self._env_hash = hashlib.sha256(encoded.encode()).hexdigest()[:32]
        return self._env_hash

    def set_checkpoint_key(
        self,
        cache_level: str,
        task_id: Optional[str] = None,
        use_savevm: bool = False,
    ) -> None:
        if cache_level not in _CHECKPOINT_LEVELS:
            raise ValueError(f"Unsupported checkpoint level: {cache_level}")
        if use_savevm:
            raise ValueError(
                "ModalNativeRunner supports filesystem checkpoints but not use_savevm=True"
            )
        self._checkpoint_cache_level = cache_level
        self._checkpoint_task_id = task_id

    def _checkpoint_key(self) -> str:
        if self._checkpoint_cache_level is None:
            raise RuntimeError("set_checkpoint_key() must be called before checkpoint operations")
        suffix = self._checkpoint_cache_level
        if suffix == "post_task":
            task = self._checkpoint_task_id or "no-task"
            task_hash = hashlib.sha256(task.encode()).hexdigest()[:16]
            suffix = f"post_task:{task_hash}"
        return f"checkpoint:{MODAL_NATIVE_IMAGE_FINGERPRINT}:{self._compute_env_hash()}:{suffix}"

    def _checkpoint_record(self) -> Optional[Dict[str, Any]]:
        self._ensure_modal_resources()
        record = self._checkpoint_dict.get(self._checkpoint_key())
        if not isinstance(record, dict):
            return None
        if (
            record.get("image_schema") != MODAL_NATIVE_IMAGE_FINGERPRINT
            or not record.get("image_id")
        ):
            return None
        return record

    def checkpoint_exists(self) -> bool:
        return self._checkpoint_record() is not None

    @contextmanager
    def _checkpoint_lock(self) -> Generator[None, None, None]:
        self._ensure_modal_resources()
        key = f"lock:{self._checkpoint_key()}"
        token = uuid.uuid4().hex
        deadline = time.monotonic() + self.lock_timeout
        lease_seconds = max(60.0, self.lock_timeout)
        while True:
            lease = {"token": token, "expires_at": time.time() + lease_seconds}
            if self._checkpoint_dict.put(key, lease, skip_if_exists=True):
                break
            current = self._checkpoint_dict.get(key)
            if isinstance(current, dict) and float(current.get("expires_at", 0)) < time.time():
                if self._checkpoint_dict.get(key) == current:
                    self._checkpoint_dict.pop(key, None)
                    continue
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Timed out waiting for Modal checkpoint lock: {self._checkpoint_key()}")
            time.sleep(self.lock_poll_seconds)
        try:
            yield
        finally:
            current = self._checkpoint_dict.get(key)
            if isinstance(current, dict) and current.get("token") == token:
                self._checkpoint_dict.pop(key, None)

    def _restart_from_image(self, image) -> None:
        self.stop()
        self._start_with_image(image=image)

    def create_checkpoint(self) -> bool:
        if self._sandbox is None or not self._running:
            raise RuntimeError("ModalNativeRunner must be running to create a checkpoint")
        key = self._checkpoint_key()
        self._report_start("modal_native_checkpoint", self._checkpoint_cache_level or "")
        with self._checkpoint_lock():
            existing = self._checkpoint_record()
            if existing is not None:
                image = self._modal.Image.from_id(existing["image_id"])
                self._restart_from_image(image)
                self._report_done("modal_native_checkpoint", "used concurrently-created snapshot")
                return True

            self.exec(
                "systemctl stop docker.service docker.socket containerd.service >/dev/null 2>&1 || true; sync",
                use_pty=False,
                timeout=120,
            )
            try:
                image = self._sandbox.snapshot_filesystem(
                    timeout=self.snapshot_timeout,
                    ttl=self.snapshot_ttl,
                )
                image_id = image.object_id
                if not image_id:
                    raise RuntimeError("Modal returned a filesystem snapshot without an image ID")
                self._checkpoint_dict.put(
                    key,
                    {
                        "image_id": image_id,
                        "image_schema": MODAL_NATIVE_IMAGE_FINGERPRINT,
                        "env_hash": self._compute_env_hash(),
                        "cache_level": self._checkpoint_cache_level,
                        "task_id": self._checkpoint_task_id
                        if self._checkpoint_cache_level == "post_task"
                        else None,
                        "created_at": time.time(),
                    },
                )
            except Exception as exc:
                self.exec(
                    "systemctl start containerd.service docker.service >/dev/null 2>&1 || true",
                    use_pty=False,
                    timeout=120,
                )
                self._report_fail("modal_native_checkpoint", str(exc))
                return False

            self._restart_from_image(image)
            self._report_done("modal_native_checkpoint", image_id)
            return True

    def start_from_checkpoint(self, seed: Optional[int] = None) -> bool:
        record = self._checkpoint_record()
        if record is None:
            return False
        image = self._modal.Image.from_id(record["image_id"])
        self._start_with_image(image=image, seed=seed)
        return True

    def delete_checkpoint(self) -> bool:
        self._ensure_modal_resources()
        record = self._checkpoint_dict.pop(self._checkpoint_key(), None)
        if not isinstance(record, dict):
            return False
        image_id = record.get("image_id")
        if image_id:
            try:
                from modal.experimental import image_delete

                image_delete(image_id)
            except Exception as exc:
                self._report_log(f"Modal checkpoint image cleanup failed for {image_id}: {exc}")
        return True

    def get_runtime_info(self) -> RunnerRuntimeInfo:
        return RunnerRuntimeInfo(
            platform_family="linux",
            container_name=None,
            instance_name=self.instance_name,
            vnc_port=self.vnc_port,
            vnc_password=self.vnc_password,
            vnc_url=self.vnc_url,
            ssh_port=None,
            ssh_user=None,
            ssh_password=None,
        )


__all__ = ["ModalNativeRunner"]
