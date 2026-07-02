"""Modal runner -- runs QemuNativeRunner inside a Modal VM Sandbox.

The heavy lifting (QEMU with KVM, VNC, SSH/ADB into the guest) happens inside
a Modal VM Sandbox (`experimental_options={"vm_runtime": True}`), which has a
real Linux kernel and a working /dev/kvm. A small HTTP shim (modal_shim.py)
wraps an unmodified QemuNativeRunner inside the sandbox; this class implements
the BaseRunner surface by proxying to it.

Base QCOW2 images and env checkpoints persist in a Modal Volume mounted at
/cache/qemu inside every sandbox, so images build once and are reused.

Usage:
    export GYM_ANYTHING_RUNNER=modal
    # requires: pip install modal && modal token set ...

Env vars:
    GYM_ANYTHING_MODAL_APP      Modal app name (default: gym-anything-runner)
    GYM_ANYTHING_MODAL_VOLUME   Volume name (default: gym-anything-qemu-cache)
    GYM_ANYTHING_MODAL_TIMEOUT  Sandbox lifetime seconds (default: 10800)
"""

from __future__ import annotations

import base64
import dataclasses
import io
import json
import os
import tarfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import requests

from ...contracts import RunnerRuntimeInfo
from ...specs import EnvSpec
from .base import BaseRunner

SHIM_PORT = 8377
VNC_TUNNEL_PORT = 5900

# Core deps the shim + QemuNativeRunner/AVDNativeRunner need inside the sandbox.
# The X/audio libs are for the Android emulator (headless swiftshader still
# links them); harmless for the QEMU path.
_SANDBOX_APT = [
    "qemu-system-x86",
    "qemu-utils",
    "wget",
    "genisoimage",
    "adb",
    "ca-certificates",
    "procps",
    "unzip",
    "openjdk-17-jre-headless",
    "libpulse0",
    "libasound2",
    "libgl1",
    "libegl1",
    "libnss3",
    "libxkbcommon0",
    "libglib2.0-0",
    "libx11-6",
    "libxext6",
    "libxrender1",
    "libxfixes3",
    "libxdamage1",
    "libxcomposite1",
    "libxcursor1",
    "libxi6",
    "libxtst6",
    "libxrandr2",
    "libfontconfig1",
]
_SANDBOX_PIP = [
    "jsonschema",
    "numpy",
    "paramiko",
    "Pillow",
    "pycryptodome",
    "PyYAML",
    "requests",
    "rich",
]


def _repo_root() -> Path:
    # src/gym_anything/runtime/runners/modal_runner.py -> repo root
    return Path(__file__).resolve().parents[4]


class ModalRunner(BaseRunner):
    """Runs the QEMU stack (Linux/Windows/Android guests) on Modal VM Sandboxes."""

    def __init__(self, spec: EnvSpec):
        super().__init__(spec)
        try:
            import modal  # noqa: F401
        except ImportError as e:
            raise RuntimeError(
                "ModalRunner requires the modal package. Install with: pip install modal"
            ) from e

        self.app_name = os.environ.get("GYM_ANYTHING_MODAL_APP", "gym-anything-runner")
        self.volume_name = os.environ.get(
            "GYM_ANYTHING_MODAL_VOLUME", "gym-anything-qemu-cache"
        )
        self.sandbox_timeout = int(os.environ.get("GYM_ANYTHING_MODAL_TIMEOUT", "10800"))

        # Guest sizing from spec; sandbox gets headroom on top. Floor of 12 GiB /
        # 5 CPUs because the one-time base image provision boots an 8G/4-cpu VM
        # regardless of the env's own resources.
        mem_gb = int(spec.resources.mem_gb or 8)
        cpus = int(spec.resources.cpu or 4)
        self.sandbox_cpu = max(cpus + 1, 5)
        self.sandbox_memory_mb = max(mem_gb + 3, 12) * 1024

        self._sandbox = None
        self._shim_proc = None
        self._base_url: Optional[str] = None
        self._vnc_tunnel: Optional[tuple] = None
        self._running = False

        self.instance_name: Optional[str] = None
        # Populated from the shim after start for get_runtime_info fallbacks
        self._remote_info: Optional[dict] = None

        # OS detection mirrors QemuApptainerRunner so platform_family is right
        # before the remote runner exists.
        base = getattr(spec, "base", "") or ""
        self.is_windows = (getattr(spec, "os_type", None) == "windows") or "windows" in base
        self.is_android = (getattr(spec, "os_type", None) == "android") or "android" in base
        from ...presets import is_avd_preset

        self.is_avd = is_avd_preset(base) or getattr(spec, "runner", None) in ("avd", "avd_native")

    # --- capability flags (delegated semantics of QemuNativeRunner) ---

    def supports_live_recording(self) -> bool:
        return False

    def supports_checkpoint_caching(self) -> bool:
        return True

    def supports_savevm(self) -> bool:
        # QEMU guests support savevm; the AVD emulator path does not.
        return not self.is_avd

    # --- sandbox lifecycle ---

    def _build_image(self):
        import modal

        image = (
            modal.Image.debian_slim()
            .apt_install(*_SANDBOX_APT)
            .pip_install(*_SANDBOX_PIP)
            .add_local_dir(
                str(_repo_root() / "src" / "gym_anything"),
                remote_path="/opt/ga/gym_anything",
            )
        )
        return image

    def _create_sandbox(self) -> None:
        import modal

        app = modal.App.lookup(self.app_name, create_if_missing=True)
        volume = modal.Volume.from_name(self.volume_name, create_if_missing=True)

        self._report_start("modal_sandbox", "creating VM sandbox")
        self._sandbox = modal.Sandbox.create(
            app=app,
            image=self._build_image(),
            cpu=self.sandbox_cpu,
            memory=self.sandbox_memory_mb,
            timeout=self.sandbox_timeout,
            volumes={"/cache/qemu": volume},
            unencrypted_ports=[SHIM_PORT, VNC_TUNNEL_PORT],
            experimental_options={"vm_runtime": True},
        )
        self.instance_name = self._sandbox.object_id

        tunnels = self._sandbox.tunnels()
        shim_host, shim_port = tunnels[SHIM_PORT].tcp_socket
        self._base_url = f"http://{shim_host}:{shim_port}"
        self._vnc_tunnel = tunnels[VNC_TUNNEL_PORT].tcp_socket
        self._report_done("modal_sandbox", self.instance_name)

    def _upload_env_tree(self) -> None:
        """Upload mount-source dirs to /repo so relative paths resolve there."""
        sources: List[str] = []
        for mount in getattr(self.spec, "mounts", []) or []:
            src = mount.get("source") if isinstance(mount, dict) else getattr(mount, "source", "")
            if src and not Path(src).is_absolute():
                sources.append(src)

        if not sources:
            return

        self._report_start("modal_upload", f"{len(sources)} mount trees")
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w:gz") as tar:
            for src in sources:
                local = Path.cwd() / src
                if local.exists():
                    tar.add(str(local), arcname=src)
        data = buf.getvalue()

        proc = self._sandbox.exec("bash", "-c", "mkdir -p /repo && tar xzf - -C /repo")
        proc.stdin.write(data)
        proc.stdin.write_eof()
        proc.stdin.drain()
        code = proc.wait()
        if code != 0:
            raise RuntimeError(f"env tree upload failed (exit {code})")
        self._report_done("modal_upload", f"{len(data) // 1024} KiB")

    def _start_shim(self) -> None:
        self._report_start("modal_shim", "starting runner shim")
        self._shim_proc = self._sandbox.exec(
            "bash",
            "-c",
            # AVD stack hardcodes ~/.cache/gym-anything; point it at the volume
            # so the SDK, AVDs, and checkpoints persist across sandboxes.
            "mkdir -p /root/.cache && ln -sfn /cache/qemu /root/.cache/gym-anything && "
            "cd /repo && "
            "GYM_ANYTHING_QEMU_CACHE=/cache/qemu "
            "PYTHONPATH=/opt/ga "
            f"python3 -u -m gym_anything.runtime.runners.modal_shim --port {SHIM_PORT} "
            "> /cache/qemu/shim.log 2>&1",
        )
        deadline = time.time() + 120
        last_err = None
        while time.time() < deadline:
            try:
                r = requests.get(f"{self._base_url}/health", timeout=5)
                if r.ok:
                    self._report_done("modal_shim")
                    return
            except Exception as e:
                last_err = e
            time.sleep(2)
        raise RuntimeError(f"shim did not become healthy: {last_err}")

    def _init_remote_runner(self) -> None:
        spec_dict = dataclasses.asdict(self.spec)
        r = requests.post(
            f"{self._base_url}/init", json={"spec": spec_dict}, timeout=120
        )
        if not r.ok:
            raise RuntimeError(f"shim init failed: {r.text[:2000]}")

    # --- RPC plumbing ---

    def _call(self, method: str, *args, poll_timeout: float = 3600.0, **kwargs) -> Any:
        """Submit a runner method call and poll for its result."""
        r = requests.post(
            f"{self._base_url}/submit",
            json={"method": method, "args": list(args), "kwargs": kwargs},
            timeout=60,
        )
        r.raise_for_status()
        job_id = r.json()["id"]

        deadline = time.time() + poll_timeout
        while time.time() < deadline:
            jr = requests.get(f"{self._base_url}/result", params={"id": job_id}, timeout=60)
            job = jr.json()
            status = job.get("status")
            if status == "done":
                result = job.get("result")
                if isinstance(result, dict) and "__bytes_b64__" in result:
                    return base64.b64decode(result["__bytes_b64__"])
                if isinstance(result, dict) and "__dataclass__" in result:
                    return result["__dataclass__"]
                return result
            if status == "error":
                raise RuntimeError(f"remote {method} failed:\n{job.get('error')}")
            time.sleep(2)
        raise TimeoutError(f"remote {method} timed out after {poll_timeout}s")

    # --- BaseRunner interface ---

    def start(self, seed: Optional[int] = None) -> None:
        self._ensure_infra()
        # First start may build the base qcow2 (cloud-init provision): allow hours
        self._call("start", seed, poll_timeout=3 * 3600.0)
        self._remote_info = self._call("get_runtime_info")
        self._running = True

    def stop(self) -> None:
        try:
            if self._base_url and self._running:
                self._call("stop", poll_timeout=300.0)
        except Exception as e:
            print(f"[ModalRunner] remote stop failed: {e}")
        finally:
            self._running = False
            if self._sandbox is not None:
                try:
                    self._sandbox.terminate()
                except Exception as e:
                    print(f"[ModalRunner] sandbox terminate failed: {e}")

    def run_reset(self, reset_script: str, seed: Optional[int] = None) -> None:
        self._call("run_reset", reset_script, seed, poll_timeout=1800.0)

    def run_task_init(self, init_script: str) -> None:
        self._call("run_task_init", init_script, poll_timeout=1800.0)

    def inject_action(self, action: Dict[str, Any]) -> None:
        self._call("inject_action", action, poll_timeout=300.0)

    def capture_observation(self) -> Dict[str, Any]:
        return self._call("capture_observation", poll_timeout=120.0)

    def capture_screenshot(self, host_path) -> bool:
        try:
            r = requests.get(f"{self._base_url}/screenshot", timeout=120)
            if r.ok and r.headers.get("Content-Type") == "application/octet-stream":
                host_path = Path(host_path)
                host_path.parent.mkdir(parents=True, exist_ok=True)
                host_path.write_bytes(r.content)
                return True
            print(f"[ModalRunner] screenshot failed: {r.text[:500]}")
            return False
        except Exception as e:
            print(f"[ModalRunner] screenshot error: {e}")
            return False

    def capture_audio_raw(self, duration_sec: float, rate: int, channels: int) -> bytes:
        return b""

    def capture_ui_tree(self) -> str:
        return self._call("capture_ui_tree", poll_timeout=120.0) or ""

    def exec(
        self,
        cmd: str,
        env: Optional[Dict[str, str]] = None,
        user: Optional[str] = None,
        use_pty: bool = True,
        timeout: int = 600,
    ) -> int:
        return self._call(
            "exec",
            cmd,
            env=env,
            user=user,
            use_pty=use_pty,
            timeout=timeout,
            poll_timeout=float(timeout) + 120.0,
        )

    def exec_capture(self, cmd: str) -> str:
        return self._call("exec_capture", cmd, poll_timeout=720.0)

    def exec_capture_bytes(self, cmd: str) -> bytes:
        result = self._call("exec_capture_bytes", cmd, poll_timeout=720.0)
        return result if isinstance(result, bytes) else (result or "").encode()

    def copy_to(self, host_src: str, container_dst: str) -> None:
        src = Path(host_src)
        if src.is_dir():
            # Rare in episode flow; ship as tar and extract shim-side via exec
            raise NotImplementedError("ModalRunner.copy_to supports files only")
        payload = {
            "name": src.name,
            "dst": container_dst,
            "data_b64": base64.b64encode(src.read_bytes()).decode(),
        }
        r = requests.post(f"{self._base_url}/copy_to", json=payload, timeout=300)
        if not r.ok:
            raise RuntimeError(f"copy_to failed: {r.text[:1000]}")

    def copy_from(self, container_src: str, host_dst: str) -> None:
        r = requests.post(
            f"{self._base_url}/copy_from", json={"src": container_src}, timeout=600
        )
        if not r.ok:
            raise RuntimeError(f"copy_from failed: {r.text[:1000]}")
        body = r.json()
        data = base64.b64decode(body["data_b64"])
        dst = Path(host_dst)
        if body.get("is_dir"):
            dst.mkdir(parents=True, exist_ok=True)
            with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
                tar.extractall(str(dst))
        else:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(data)

    def put_file(self, host_path) -> str:
        src = Path(host_path)
        payload = {
            "name": src.name,
            "data_b64": base64.b64encode(src.read_bytes()).decode(),
        }
        r = requests.post(f"{self._base_url}/put_file", json=payload, timeout=300)
        if not r.ok:
            raise RuntimeError(f"put_file failed: {r.text[:1000]}")
        return r.json()["path"]

    def save_state(self, save_paths: Optional[List[str]] = None) -> str:
        return self._call("save_state", save_paths, poll_timeout=1800.0)

    def load_state(self, snapshot_name: str) -> None:
        self._call("load_state", snapshot_name, poll_timeout=1800.0)

    # --- checkpoint support (persisted on the Modal volume) ---

    def set_checkpoint_key(
        self, cache_level: str, task_id: Optional[str] = None, use_savevm: bool = False
    ) -> None:
        # Sandbox may not exist yet when env.py sets the key; stash and replay.
        self._pending_checkpoint_key = (cache_level, task_id, use_savevm)
        if self._base_url and self._running:
            self._call("set_checkpoint_key", cache_level, task_id, use_savevm)

    def checkpoint_exists(self) -> bool:
        self._ensure_infra()
        self._replay_checkpoint_key()
        return bool(self._call("checkpoint_exists"))

    def create_checkpoint(self) -> bool:
        result = bool(self._call("create_checkpoint", poll_timeout=3600.0))
        return result

    def start_from_checkpoint(self, seed: Optional[int] = None) -> bool:
        self._ensure_infra()
        self._replay_checkpoint_key()
        ok = bool(self._call("start_from_checkpoint", seed, poll_timeout=3600.0))
        if ok:
            self._remote_info = self._call("get_runtime_info")
            self._running = True
        return ok

    def _ensure_infra(self) -> None:
        """Bring up sandbox + shim + remote runner without booting the VM."""
        if self._base_url is None:
            self._create_sandbox()
            self._upload_env_tree()
            self._start_shim()
            self._init_remote_runner()

    def _replay_checkpoint_key(self) -> None:
        key = getattr(self, "_pending_checkpoint_key", None)
        if key is not None:
            self._call("set_checkpoint_key", *key)

    # --- runtime info ---

    def get_runtime_info(self) -> RunnerRuntimeInfo:
        info = self._remote_info or {}
        vnc_host, vnc_port = (self._vnc_tunnel or (None, None))
        return RunnerRuntimeInfo(
            platform_family=info.get("platform_family") or self.get_platform_family(),
            container_name=None,
            instance_name=self.instance_name,
            vnc_port=vnc_port,
            vnc_password=info.get("vnc_password"),
            ssh_port=None,
            ssh_user=info.get("ssh_user"),
            ssh_password=info.get("ssh_password"),
        )

    def to_container_path(self, host_path):
        return host_path
