"""
QEMU-inside-Apptainer Runner for HPC/SLURM environments.

DROP-IN REPLACEMENT for DockerRunner. Uses the SAME env.json files.
Automatically creates and caches QCOW2 images based on the env specs.

Architecture:
    1. Base QCOW2 (Ubuntu + GNOME + VNC + tools) - downloaded once
    2. Env-specific checkpoint - auto-provisioned by running hooks
    3. COW overlay per instance - for parallelization

Usage:
    export GYM_ANYTHING_RUNNER=qemu
    python -m agents.evaluation.run_batch ...  # Same command as Docker!
"""

from __future__ import annotations

import base64

import fcntl
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import socket
import subprocess
import tempfile
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Generator, List, Optional, Tuple

from ...config.presets import is_android_preset, is_windows_preset
from ...security import wrap_posix_command_with_env, wrap_powershell_command_with_env
from ...specs import EnvSpec
from .base import BaseRunner
from .vnc_utils import VNCConnectionPool
from .windows_pyautogui_client import PyAutoGUIClient, PyAutoGUIClientError

# Configuration via environment variables
QEMU_CACHE = Path(os.environ.get("GYM_ANYTHING_QEMU_CACHE", os.path.expanduser("~/.cache/gym-anything/qemu")))
QEMU_CONTAINER = os.environ.get("GYM_ANYTHING_QEMU_CONTAINER", "docker://ghcr.io/dockur/windows:latest")
BASE_QCOW2_URL = os.environ.get("GYM_ANYTHING_BASE_QCOW2", "")  # URL to download base image
# Work directory for instance overlays (defaults to QEMU_CACHE/work if not set)
_work_dir_env = os.environ.get("GYM_ANYTHING_QEMU_WORK_DIR", "")
QEMU_WORK_DIR = Path(_work_dir_env).expanduser() if _work_dir_env else QEMU_CACHE / "work"

# Snapshot name for savevm/loadvm (consistent name so we can find it)
SAVEVM_SNAPSHOT_NAME = "ga_checkpoint"


def _find_free_port(start: int = 5900) -> int:
    """Find free port with random offset for parallel safety."""
    import socket
    import random
    offset = random.randint(0, 200)
    for i in range(300):
        port = start + offset + i
        if port > 65535:
            port = start + (i % 300)
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.bind(("0.0.0.0", port))
                return port
        except OSError:
            continue
    raise RuntimeError("No free port")


def _find_free_qemu_hostfwd_port(start: int = 45500) -> int:
    """Find a hostfwd port using the same bind constraints QEMU will use."""
    import socket
    import random
    offset = random.randint(0, 200)
    for i in range(300):
        port = start + offset + i
        if port > 65535:
            port = start + (i % 300)
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(("0.0.0.0", port))
                return port
        except OSError:
            continue
    raise RuntimeError("No free QEMU hostfwd port")


def _check_apptainer() -> bool:
    try:
        return subprocess.run(["apptainer", "--version"], capture_output=True, timeout=5).returncode == 0
    except:
        return False


def _check_kvm() -> bool:
    return os.path.exists("/dev/kvm") and os.access("/dev/kvm", os.R_OK | os.W_OK)


def _get_env_hash(spec: EnvSpec) -> str:
    """Generate hash for environment (for caching checkpoints)."""
    # Hash based on: preset/image + hooks + scripts
    key_parts = [
        spec.base or "",
        spec.image or "",
        spec.dockerfile or "",
        str(getattr(spec, "hooks", {})),
    ]
    return hashlib.sha256("|".join(key_parts).encode()).hexdigest()[:16]


class _QMPClient:
    """Small synchronous QMP client for host-side fast I/O commands."""

    def __init__(self, socket_path: Path, timeout: float = 5.0):
        self.socket_path = socket_path
        self.timeout = timeout
        self._socket: Optional[socket.socket] = None
        self._buffer = b""
        self._lock = threading.RLock()

    def connect(self) -> None:
        if self._socket is not None:
            return
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        sock.connect(str(self.socket_path))
        self._socket = sock
        self._read_message()  # QMP greeting
        self.execute("qmp_capabilities")

    def close(self) -> None:
        if self._socket is None:
            return
        try:
            self._socket.close()
        finally:
            self._socket = None
            self._buffer = b""

    def execute(self, command: str, arguments: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        with self._lock:
            try:
                return self._execute_once(command, arguments)
            except OSError:
                self.close()
                return self._execute_once(command, arguments)

    def _execute_once(self, command: str, arguments: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        self.connect()
        payload: Dict[str, Any] = {"execute": command}
        if arguments:
            payload["arguments"] = arguments
        assert self._socket is not None
        self._socket.sendall(json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\r\n")
        while True:
            message = self._read_message()
            if "event" in message:
                continue
            if "error" in message:
                raise RuntimeError(f"QMP {command} failed: {message['error']}")
            return message.get("return", {})

    def _read_message(self) -> Dict[str, Any]:
        assert self._socket is not None
        while b"\n" not in self._buffer:
            chunk = self._socket.recv(65536)
            if not chunk:
                raise RuntimeError("QMP connection closed")
            self._buffer += chunk
        line, self._buffer = self._buffer.split(b"\n", 1)
        return json.loads(line.strip().decode("utf-8"))


class _FastInputAgentClient:
    """Persistent host-side client for the Linux guest uinput input service."""

    def __init__(self, host: str, port: int, timeout: float = 1.0):
        self.host = host
        self.port = int(port)
        self.timeout = timeout
        self._socket: Optional[socket.socket] = None
        self._buffer = b""
        self._lock = threading.RLock()

    def connect(self) -> None:
        if self._socket is not None:
            return
        sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
        sock.settimeout(self.timeout)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self._socket = sock

    def close(self) -> None:
        if self._socket is None:
            return
        try:
            self._socket.close()
        finally:
            self._socket = None
            self._buffer = b""

    def request(self, payload: Dict[str, Any], allow_error: bool = False) -> Dict[str, Any]:
        with self._lock:
            try:
                return self._request_once(payload, allow_error)
            except OSError:
                self.close()
                return self._request_once(payload, allow_error)

    def _request_once(self, payload: Dict[str, Any], allow_error: bool = False) -> Dict[str, Any]:
        self.connect()
        assert self._socket is not None
        self._socket.sendall(json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n")
        response = self._read_line()
        # allow_error hands a refusal back to the caller to act on. The agent
        # refuses before touching the device, so a rerouted request cannot
        # double-inject.
        if not response.get("ok") and not allow_error:
            raise RuntimeError(f"fast input agent error: {response.get('error', response)}")
        return response

    def _read_line(self) -> Dict[str, Any]:
        assert self._socket is not None
        while b"\n" not in self._buffer:
            chunk = self._socket.recv(65536)
            if not chunk:
                raise RuntimeError("fast input agent connection closed")
            self._buffer += chunk
        line, self._buffer = self._buffer.split(b"\n", 1)
        return json.loads(line.decode("utf-8"))


# X11 button bits in XQueryPointer's mask, used to confirm the guest actually
# received a button transition. 4 and 5 are the wheel, which is why a wheel
# tick can be acked at all.
_X_BUTTON_MASK = {
    "left": 1 << 8,
    "middle": 1 << 9,
    "right": 1 << 10,
    "wheel-up": 1 << 11,
    "wheel-down": 1 << 12,
}

_KEYBOARD_XLIB_PREAMBLE = 'import time, base64\nfrom Xlib import X, XK, display\nfrom Xlib.ext import xtest\n_D = display.Display()\n_INF = _D.display.info\n_MINKC, _MAXKC = _INF.min_keycode, _INF.max_keycode\n_NAME = {\n "ctrl":"Control_L","control":"Control_L","shift":"Shift_L","alt":"Alt_L",\n "super":"Super_L","win":"Super_L","meta":"Super_L","cmd":"Super_L","command":"Super_L",\n "enter":"Return","return":"Return","esc":"Escape","escape":"Escape",\n "tab":"Tab","space":"space","backspace":"BackSpace","delete":"Delete","del":"Delete",\n "up":"Up","down":"Down","left":"Left","right":"Right","home":"Home","end":"End",\n "pageup":"Prior","pagedown":"Next","pgup":"Prior","pgdn":"Next","page_up":"Prior",\n "page_down":"Next","insert":"Insert","ins":"Insert","kp_enter":"KP_Enter",\n "kp_add":"KP_Add","kp_subtract":"KP_Subtract","kp_multiply":"KP_Multiply",\n "kp_divide":"KP_Divide","menu":"Menu","caps_lock":"Caps_Lock","capslock":"Caps_Lock",\n "num_lock":"Num_Lock","numlock":"Num_Lock","print":"Print",\n}\nfor _n in range(1, 13):\n    _NAME["f%d" % _n] = "F%d" % _n\ndef _spares():\n    m = _D.get_keyboard_mapping(_MINKC, _MAXKC - _MINKC + 1)\n    return [_MINKC + i for i, r in enumerate(m) if not any(r)]\ndef _char_ks(ch):\n    cp = ord(ch)\n    return cp if cp <= 0xff else (cp | 0x01000000)\ndef _name_ks(name):\n    ks = XK.string_to_keysym(_NAME.get(name.lower(), name))\n    if ks == 0 and len(name) == 1:\n        ks = _char_ks(name)\n    return ks\ndef _kc_of_name(name, pool):\n    ks = _name_ks(name)\n    kc = _D.keysym_to_keycode(ks)\n    if kc == 0 and pool:\n        kc = pool.pop()\n        _D.change_keyboard_mapping(kc, [[ks, ks]])\n        _D.sync(); time.sleep(0.03)\n    return kc\n_SETTLE = 0.12\ndef type_text(text):\n    pool_all = _spares()\n    S = len(pool_all)\n    if S == 0:\n        return\n    ret = _D.keysym_to_keycode(XK.XK_Return)\n    tab = _D.keysym_to_keycode(XK.XK_Tab)\n    def _flush(seg):\n        # One batch of <= S distinct chars: remap all, settle ONCE, type,\n        # restore. No remap happens during typing, so no keypress can race a\n        # remap. Every char is typed via a spare keycode at level 0, so no\n        # shift logic and no layout dependence (fixes < -> > too).\n        remap = {}\n        pool = list(pool_all)\n        for ch in dict.fromkeys(seg):\n            if ch in "\\n\\t":\n                continue\n            kc = pool.pop()\n            ks = _char_ks(ch)\n            _D.change_keyboard_mapping(kc, [[ks, ks]])\n            remap[ch] = kc\n        _D.sync(); time.sleep(_SETTLE)\n        for ch in seg:\n            kc = ret if ch == "\\n" else tab if ch == "\\t" else remap.get(ch)\n            if not kc:\n                continue\n            xtest.fake_input(_D, X.KeyPress, kc)\n            xtest.fake_input(_D, X.KeyRelease, kc)\n            _D.sync(); time.sleep(0.006)\n        _D.sync(); time.sleep(_SETTLE / 3.0)\n        for kc in remap.values():\n            _D.change_keyboard_mapping(kc, [[X.NoSymbol, X.NoSymbol]])\n        _D.sync()\n    # Split the text into segments each having <= S distinct typeable chars,\n    # so an unlimited alphabet still fits the available spare keycodes.\n    seg = []\n    seen = set()\n    for ch in text:\n        typeable = ch not in "\\n\\t"\n        if typeable and ch not in seen and len(seen) >= S:\n            _flush(seg); seg = []; seen = set()\n        seg.append(ch)\n        if typeable:\n            seen.add(ch)\n    if seg:\n        _flush(seg)\ndef chord(keys):\n    pool = _spares()\n    kcs = [_kc_of_name(k, pool) for k in keys]\n    for kc in kcs:\n        if kc:\n            xtest.fake_input(_D, X.KeyPress, kc)\n            _D.sync(); time.sleep(0.01)\n    for kc in reversed(kcs):\n        if kc:\n            xtest.fake_input(_D, X.KeyRelease, kc)\n            _D.sync(); time.sleep(0.01)\ndef hold(keys, down):\n    pool = _spares()\n    for k in keys:\n        kc = _kc_of_name(k, pool)\n        if kc:\n            xtest.fake_input(_D, X.KeyPress if down else X.KeyRelease, kc)\n            _D.sync(); time.sleep(0.01)\n'


class QemuApptainerRunner(BaseRunner):
    """
    QEMU-inside-Apptainer runner for HPC/SLURM.
    
    Workflow:
    1. Ensure base QCOW2 exists (Ubuntu + GNOME + VNC + tools)
    2. Check for env-specific checkpoint (already provisioned)
    3. If no checkpoint, provision by running pre_start/post_start hooks
    4. Create COW overlay for this instance
    5. Boot VM, interact via VNC
    """
    
    def __init__(self, spec: EnvSpec):
        super().__init__(spec)

        self._check_prerequisites()

        self.instance_id = uuid.uuid4().hex[:12]
        self.instance_name = f"ga_qemu_{self.instance_id}"

        # Determine OS type (Linux vs Windows vs Android)
        self.is_windows = self._detect_windows(spec)
        self.is_android = self._detect_android(spec)

        # Paths - select base image based on OS type
        QEMU_CACHE.mkdir(parents=True, exist_ok=True)
        if self.is_android:
            self.base_qcow2 = QEMU_CACHE / "base_android_14.qcow2"
            # Android uses ADB, not SSH
            self._ssh_user = None
            self._ssh_password = None
        elif self.is_windows:
            self.base_qcow2 = QEMU_CACHE / "base_windows_11.qcow2"
            # SSH credentials for Windows - get from spec or use defaults
            ssh_cfg = getattr(spec, "ssh", None)
            if ssh_cfg and hasattr(ssh_cfg, "user") and ssh_cfg.user:
                self._ssh_user = ssh_cfg.user
                self._ssh_password = ssh_cfg.password if hasattr(ssh_cfg, "password") else "GymAnything123!"
            else:
                # Default credentials set by setup_windows_for_gym_anything.ps1
                self._ssh_user = "Docker"
                self._ssh_password = "GymAnything123!"
        else:
            self.base_qcow2 = QEMU_CACHE / "base_ubuntu_gnome.qcow2"
            # SSH credentials for Linux
            self._ssh_user = "ga"
            self._ssh_password = "password123"

        self.env_hash = _get_env_hash(spec)
        self.env_checkpoint = QEMU_CACHE / f"checkpoint_{self.env_hash}.qcow2"

        # VNC
        vnc_cfg = getattr(spec, "vnc", None)
        self.vnc_password = vnc_cfg.password if vnc_cfg else "password"
        self.vnc_port: Optional[int] = None
        self.ssh_port: Optional[int] = None

        # ADB port (Android only)
        adb_cfg = getattr(spec, "adb", None)
        self.adb_port: Optional[int] = None
        self._adb_guest_port = adb_cfg.guest_port if adb_cfg else 5555
        self._adb_timeout = adb_cfg.timeout if adb_cfg else 180
        self._adb_path: Optional[str] = None  # Path to adb binary

        # PyAutoGUI server (Windows only)
        self.pyautogui_port: int = 5555  # Default port for pyautogui server
        self._pyautogui_client: Optional[PyAutoGUIClient] = None

        # Consecutive SSH failure tracking — abort after too many
        self._consecutive_ssh_failures = 0
        self._max_consecutive_ssh_failures = 5

        # Resources
        self.memory = f"{spec.resources.mem_gb or 8}G"
        self.cpus = int(spec.resources.cpu or 4)
        self.enable_kvm = self._detect_acceleration()

        # GPU support - check if GPU is requested
        self.enable_gpu = bool(spec.resources.gpu and spec.resources.gpu > 0)
        if self.enable_gpu:
            # Check for NVIDIA GPU availability
            self._has_nvidia = os.path.exists("/dev/nvidia0") or os.path.exists("/dev/nvidiactl")
            # Check for DRI (Intel/AMD/software rendering)
            self._has_dri = os.path.exists("/dev/dri")
            if not self._has_nvidia and not self._has_dri:
                print("[QemuApptainer] WARNING: GPU requested but no /dev/nvidia* or /dev/dri found")
        else:
            self._has_nvidia = False
            self._has_dri = False

        # Screen
        screen_spec = next((o for o in spec.observation if o.type == "rgb_screen"), None)
        self.resolution = screen_spec.resolution if screen_spec else (1920, 1080)

        # State
        self._running = False
        self._process: Optional[subprocess.Popen] = None
        self._vnc_pool: Optional[VNCConnectionPool] = None
        self._qmp_socket_path: Optional[Path] = None
        self._qmp_client: Optional[_QMPClient] = None
        self._fast_input_client: Optional[_FastInputAgentClient] = None
        self._fast_input_host_port: Optional[int] = None
        self._fast_input_guest_port = int(os.environ.get("GYM_ANYTHING_QEMU_FAST_INPUT_GUEST_PORT", "5599"))
        self._fast_input_device_name = "GymAnything Fast Keyboard"
        self._fast_io_dir: Optional[Path] = None
        self._fast_io_container_dir: Optional[Path] = None
        self._dbus_display = None
        self._work_dir: Optional[Path] = None
        self._instance_qcow2: Optional[Path] = None
        self._artifacts_root = os.path.abspath(spec.recording.output_dir)

        self._lock = threading.Lock()
        self._stop_event = threading.Event()

        # Checkpoint key components (set via set_checkpoint_key)
        self._checkpoint_cache_level: str = "pre_start"
        self._checkpoint_task_id: Optional[str] = None
        # Whether to use QEMU savevm/loadvm for true memory+CPU state checkpointing
        # When True: saves full VM state (instant restore, preserves running processes)
        # When False: only saves disk state (requires full reboot on restore)
        self._use_savevm: bool = False
        self._container_image = QEMU_CONTAINER

    def _check_prerequisites(self) -> None:
        """Check that required system tools are available. Subclasses override."""
        if not _check_apptainer():
            raise RuntimeError(
                "Apptainer not found. Install Apptainer or set "
                "GYM_ANYTHING_RUNNER=qemu_native if QEMU is installed directly."
            )

    def _detect_acceleration(self) -> bool:
        """Detect hardware acceleration. Returns True if available. Subclasses override."""
        return _check_kvm()

    def _run_qemu_img(self, args: List[str], bind_paths: Optional[List[str]] = None) -> subprocess.CompletedProcess:
        """Run qemu-img command inside Apptainer container. Subclasses override."""
        cmd = [
            "apptainer", "exec",
            "--contain",
        ]

        # Auto-detect paths from args and bind them
        paths_to_bind = set()
        if bind_paths:
            paths_to_bind.update(bind_paths)

        for arg in args:
            if arg.startswith("/") and not arg.startswith("/dev"):
                parent = str(Path(arg).parent)
                if parent != "/":
                    paths_to_bind.add(parent)

        # Also bind the cache directory
        paths_to_bind.add(str(QEMU_CACHE))

        for path in paths_to_bind:
            if os.path.exists(path):
                cmd.extend(["--bind", f"{path}:{path}"])

        cmd.append(self._container_image)
        cmd.extend(["qemu-img"] + args)

        return subprocess.run(cmd, capture_output=True, text=True)

    def supports_checkpoint_caching(self) -> bool:
        return True

    def supports_savevm(self) -> bool:
        return True

    def supports_fast_io(self) -> bool:
        return True

    def set_fast_io(self, enabled: bool) -> None:
        super().set_fast_io(enabled)
        if self._fast_io:
            self._validate_fast_keyboard_backend()
        if self._fast_io and self._fast_io_backend() == "dbus":
            self._ensure_dbus_display_container()

    def _detect_windows(self, spec: EnvSpec) -> bool:
        """Detect if this is a Windows environment."""
        # Check os_type field directly
        if hasattr(spec, 'os_type') and spec.os_type == 'windows':
            return True
        # Check base preset
        if hasattr(spec, 'base') and spec.base and is_windows_preset(spec.base):
            return True
        return False

    def _detect_android(self, spec: EnvSpec) -> bool:
        """Detect if this is an Android environment."""
        # Check os_type field directly
        if hasattr(spec, 'os_type') and spec.os_type == 'android':
            return True
        # Check base preset
        if hasattr(spec, 'base') and spec.base and is_android_preset(spec.base):
            return True
        return False
    
    def start(self, seed: Optional[int] = None) -> None:
        """Start the QEMU VM.

        This just boots the VM from base image. Hooks are handled by env.py,
        consistent with Docker runner. Use start_from_checkpoint() for cached boot.
        """
        print(f"[QemuApptainer] Instance: {self.instance_name}")
        print(f"[QemuApptainer] KVM: {'enabled' if self.enable_kvm else 'DISABLED (slow!)'}")
        if self.enable_gpu:
            gpu_type = "NVIDIA" if self._has_nvidia else ("DRI/Mesa" if self._has_dri else "none found")
            print(f"[QemuApptainer] GPU: enabled ({gpu_type})")

        # Step 1: Ensure base image exists
        if not self.base_qcow2.exists():
            self._create_base_qcow2()

        # Step 2: Create work directory and COW overlay (from base, not checkpoint)
        # Use cache directory for work instead of /tmp (which may be full).
        # In fast_io mode, prefer local scratch for screenshot exchange and COW overlays.
        work_base = self._get_work_base()
        work_base.mkdir(parents=True, exist_ok=True)
        self._work_dir = Path(tempfile.mkdtemp(prefix=f"ga_qemu_{self.instance_id}_", dir=work_base))
        self._instance_qcow2 = self._work_dir / "disk.qcow2"

        # Run qemu-img inside Apptainer (qemu-img not on host)
        # Boot from base image directly (hooks handled by env.py)
        result = self._run_qemu_img([
            "create", "-f", "qcow2",
            "-b", str(self.base_qcow2.absolute()),
            "-F", "qcow2",
            str(self._instance_qcow2)
        ])
        if result.returncode != 0:
            raise RuntimeError(f"qemu-img failed: {result.stderr}")
        print(f"[QemuApptainer] COW overlay created")
        
        # Step 4: Find ports
        with self._lock:
            self.vnc_port = _find_free_port(5900)
            if self.is_android:
                self.adb_port = _find_free_port(15555)  # ADB instead of SSH
            else:
                self.ssh_port = _find_free_port(2222)
            if self.is_windows:
                self.pyautogui_port = _find_free_port(5555)
            self._assign_fast_input_port()
        if self.is_android:
            print(f"[QemuApptainer] VNC: {self.vnc_port}, ADB: {self.adb_port}")
        elif self.is_windows:
            print(f"[QemuApptainer] VNC: {self.vnc_port}, SSH: {self.ssh_port}, PyAutoGUI: {self.pyautogui_port}")
        else:
            print(f"[QemuApptainer] VNC: {self.vnc_port}, SSH: {self.ssh_port}")
            if self._fast_input_host_port:
                print(f"[QemuApptainer] Fast input: {self._fast_input_host_port}->{self._fast_input_guest_port}")
        
        # Step 5: Start VM
        self._start_vm()
        
        # Step 6: Wait for VNC to become available
        if not self._wait_for_vnc(timeout=120):
            self._dump_log()
            self.stop()
            raise RuntimeError("VM boot failed")

        # Step 7: Platform-specific connectivity wait
        if self.is_android:
            # Android: Wait for ADB to be available
            if not self._wait_for_adb(timeout=self._adb_timeout):
                self._dump_log()
                self.stop()
                raise RuntimeError("ADB not available")
            # Handle first-boot setup (dismiss launcher dialog, etc.)
            self._android_first_boot_setup()
            # Setup mounts via ADB (push files to device)
            self._setup_mounts_adb()
        else:
            # Linux/Windows: Wait for SSH to be available (needed for mounts and exec)
            # Windows needs more time to boot than Linux
            ssh_timeout = 600 if self.is_windows else int(os.environ.get("GYM_ANYTHING_SSH_TIMEOUT", "300"))
            if not self._wait_for_ssh(self.ssh_port, timeout=ssh_timeout):
                self._dump_log()
                self.stop()
                raise RuntimeError("SSH not available")

            # For Windows: Check if user is logged in, unlock if needed
            if self.is_windows:
                # Test if SSH auth works
                if self._test_ssh_auth():
                    # Auth works - check if explorer.exe is running (user logged in to desktop)
                    result = self._run_ssh_cmd(
                        self.ssh_port,
                        'powershell -Command "Get-Process explorer -ErrorAction SilentlyContinue"',
                        timeout=15
                    )
                    stdout = result.stdout.decode() if result.stdout else ""
                    if "explorer" not in stdout.lower():
                        # User not logged in to desktop - unlock via VNC
                        print("[QemuApptainer] SSH works but explorer not running - unlocking desktop via VNC...")
                        self._unlock_windows_via_vnc()
                        time.sleep(10)
                else:
                    print("[QemuApptainer] SSH auth failed - attempting VNC unlock...")
                    self._unlock_windows_via_vnc()
                    time.sleep(10)

            # Step 8: Setup mounts (copy hook scripts and other files to VM)
            self._setup_mounts(self.ssh_port)

            # Step 9: Wait for desktop to be ready (polls wmctrl until window manager responds)
            desktop_timeout = int(os.environ.get("GYM_ANYTHING_DESKTOP_TIMEOUT", "120"))
            if not self._wait_for_desktop(timeout=desktop_timeout):
                print("[QemuApptainer] Warning: Desktop may not be fully ready, continuing anyway...")
                # For Windows: Try to connect to PyAutoGUI server anyway (it may be running via scheduled task)
                if self.is_windows and not self._pyautogui_client:
                    print("[QemuApptainer] Attempting to connect to PyAutoGUI server...")
                    self._try_connect_pyautogui_client()
            self._ensure_fast_input_agent()

        # Step 10: Connect VNC (now should get proper desktop resolution)
        self._vnc_pool = VNCConnectionPool(
            host="localhost",
            port=self.vnc_port,
            password=self.vnc_password
        )

        conn = self._vnc_pool.get_connection(retry_count=10, retry_delay=2.0)
        if not conn:
            self.stop()
            raise RuntimeError("VNC connection failed")

        self._running = True
        print(f"[QemuApptainer] VM ready! Resolution: {conn.resolution}")

        settle = self._post_boot_settle_seconds()
        if settle > 0:
            print(f"[QemuApptainer] Waiting {settle}s for compositor to render...")
            time.sleep(settle)

    def _create_base_qcow2(self) -> None:
        """Create or download the base Ubuntu Desktop QCOW2 image.
        
        The base image must have:
        - Ubuntu Desktop with GNOME
        - TigerVNC server (password: 'password' on :1)
        - SSH server
        - xdotool, ffmpeg, python3, etc.
        """
        print(f"[QemuApptainer] Base QCOW2 image not found at: {self.base_qcow2}")
        
        # Check for pre-built base image URL
        if BASE_QCOW2_URL:
            print(f"[QemuApptainer] Downloading base image from {BASE_QCOW2_URL}...")
            result = subprocess.run(
                ["wget", "-q", "--show-progress", "-O", str(self.base_qcow2), BASE_QCOW2_URL],
                capture_output=False
            )
            if result.returncode == 0 and self.base_qcow2.exists():
                print(f"[QemuApptainer] Base image downloaded successfully")
                return
            else:
                raise RuntimeError(f"Failed to download base image from {BASE_QCOW2_URL}")
        
        # Try to build automatically using cloud-init
        print(f"[QemuApptainer] Attempting to build base image automatically...")
        try:
            from .build_base_qcow2_nodocker import main as build_main
            import sys
            old_argv = sys.argv
            sys.argv = ['build_base_qcow2_nodocker', '--timeout', '7200']  # 2 hour timeout
            try:
                build_main()
            finally:
                sys.argv = old_argv
            
            if self.base_qcow2.exists():
                print(f"[QemuApptainer] Base image created successfully")
                return
        except Exception as e:
            print(f"[QemuApptainer] Auto-build failed: {e}")
        
        # No pre-built image available - provide instructions
        raise RuntimeError(
            f"\n{'='*70}\n"
            f"BASE QCOW2 IMAGE REQUIRED\n"
            f"{'='*70}\n\n"
            f"QemuApptainerRunner needs a base QCOW2 image with:\n"
            f"  - Ubuntu Desktop + GNOME\n"
            f"  - TigerVNC server (port 5901, password: 'password')\n"
            f"  - SSH server (port 22, user: 'ga', sudo enabled)\n"
            f"  - Tools: xdotool, ffmpeg, python3, pyautogui\n\n"
            f"RUN THE SETUP SCRIPT:\n\n"
            f"  ./setup_base_qcow2.sh --interactive\n\n"
            f"This will guide you through creating the base image.\n\n"
            f"ALTERNATIVE: Download pre-built image:\n"
            f"  export GYM_ANYTHING_BASE_QCOW2='https://your-url/ubuntu-desktop.qcow2'\n\n"
            f"{'='*70}"
        )
    
    # NOTE: _create_env_checkpoint removed - hooks are now handled by env.py
    # Checkpointing is done via create_checkpoint() called from env.py

    def _build_container_prefix(self, work_dir: Path, disk: Path) -> List[str]:
        """Build the container wrapper prefix. Subclasses override (e.g. return [])."""
        work_dir_abs = str(work_dir.absolute())
        cache_dir_abs = str(QEMU_CACHE.absolute())

        cmd = [
            "apptainer", "exec",
            "--contain", "--writable-tmpfs",
        ]

        if self.enable_kvm:
            cmd.extend(["--bind", "/dev/kvm"])

        # GPU support: Bind GPU devices and use --nv for NVIDIA
        if self.enable_gpu:
            if self._has_nvidia:
                cmd.append("--nv")
                for dev in ["/dev/nvidia0", "/dev/nvidiactl", "/dev/nvidia-uvm", "/dev/nvidia-modeset"]:
                    if os.path.exists(dev):
                        cmd.extend(["--bind", dev])
            if self._has_dri:
                cmd.extend(["--bind", "/dev/dri"])

        # Bind paths at same location inside/outside container
        cmd.extend(["--bind", f"{work_dir_abs}:{work_dir_abs}"])
        cmd.extend(["--bind", f"{cache_dir_abs}:{cache_dir_abs}"])

        if self._fast_io:
            self._fast_io_dir, self._fast_io_container_dir = self._make_fast_io_dirs(work_dir)

        artifacts_dir = Path(self._artifacts_root)
        artifacts_dir.mkdir(parents=True, exist_ok=True)
        artifacts_abs = str(artifacts_dir.absolute())
        cmd.extend(["--bind", f"{artifacts_abs}:{artifacts_abs}"])

        cmd.append(self._container_image)
        return cmd

    def _get_work_base(self) -> Path:
        if not self._fast_io:
            return QEMU_WORK_DIR

        override = os.environ.get("GYM_ANYTHING_FAST_IO_WORK_DIR")
        if override:
            base = Path(override).expanduser()
            return base if self._usable_work_base(base) else QEMU_WORK_DIR

        if _work_dir_env:
            return QEMU_WORK_DIR

        base = Path(tempfile.gettempdir()) / "gym-anything-qemu-work"
        return base if self._usable_work_base(base) else QEMU_WORK_DIR

    def _usable_work_base(self, base: Path) -> bool:
        try:
            base.mkdir(parents=True, exist_ok=True)
        except OSError:
            return False
        if not os.access(base, os.W_OK | os.X_OK):
            return False
        try:
            required = 512 * 1024 * 1024
            if self._use_savevm:
                checkpoint_path = self._get_checkpoint_path()
                if checkpoint_path.exists():
                    required += checkpoint_path.stat().st_size
            free = shutil.disk_usage(base).free
        except OSError:
            return False
        return free >= required

    def _make_fast_io_dirs(self, work_dir: Path) -> tuple[Path, Path]:
        host_path = work_dir / self.instance_id
        host_path.mkdir(parents=True, exist_ok=True)
        return host_path, host_path

    def _fast_io_backend(self) -> str:
        return os.environ.get("GYM_ANYTHING_QEMU_FAST_IO_BACKEND", "qmp").strip().lower()

    def _fast_keyboard_backend(self) -> str:
        if getattr(self, "is_android", False):
            return "adb"
        if getattr(self, "is_windows", False):
            return os.environ.get("GYM_ANYTHING_QEMU_FAST_KEYBOARD_BACKEND", "qmp-experimental").strip().lower()
        return os.environ.get("GYM_ANYTHING_QEMU_FAST_KEYBOARD_BACKEND", "uinput").strip().lower()

    def _fast_uinput_keyboard_enabled(self) -> bool:
        return (
            self._fast_io
            and not getattr(self, "is_android", False)
            and not getattr(self, "is_windows", False)
            and self._fast_keyboard_backend() == "uinput"
        )

    def _validate_fast_keyboard_backend(self) -> None:
        backend = self._fast_keyboard_backend()
        if getattr(self, "is_android", False):
            return
        allowed = {"uinput", "qmp-experimental"} if not getattr(self, "is_windows", False) else {"qmp-experimental"}
        if backend not in allowed:
            raise RuntimeError(
                f"Unsupported QEMU fast keyboard backend {backend!r}. "
                f"Allowed values for this guest are: {', '.join(sorted(allowed))}."
            )

    def _assign_fast_input_port(self) -> None:
        self._fast_input_host_port = _find_free_qemu_hostfwd_port(45500) if self._fast_uinput_keyboard_enabled() else None

    def _dbus_auto_install_enabled(self) -> bool:
        value = os.environ.get("GYM_ANYTHING_QEMU_DBUS_AUTO_INSTALL", "1")
        return value.strip().lower() in {"1", "true", "yes", "on"}

    def _dbus_sandbox_path(self) -> Path:
        override = os.environ.get("GYM_ANYTHING_QEMU_DBUS_SANDBOX")
        if override:
            return Path(override).expanduser()
        source_hash = hashlib.sha256(QEMU_CONTAINER.encode("utf-8")).hexdigest()[:16]
        return QEMU_CACHE / "containers" / f"qemu-dbus-{source_hash}"

    def _container_supports_dbus_display(self, container: str) -> bool:
        try:
            result = subprocess.run(
                [
                    "apptainer",
                    "exec",
                    "--contain",
                    container,
                    "qemu-system-x86_64",
                    "-display",
                    "help",
                ],
                capture_output=True,
                text=True,
                timeout=30,
            )
        except Exception:
            return False
        output = f"{result.stdout}\n{result.stderr}"
        return any(line.strip() == "dbus" for line in output.splitlines())

    def _ensure_dbus_display_container(self) -> None:
        sandbox = self._dbus_sandbox_path()
        if sandbox.exists() and self._container_supports_dbus_display(str(sandbox)):
            self._container_image = str(sandbox)
            return

        if self._container_supports_dbus_display(self._container_image):
            return
        if not self._dbus_auto_install_enabled():
            raise RuntimeError(
                "QEMU D-Bus display backend requested, but the Apptainer image "
                "does not provide '-display dbus'. Install qemu-system-modules-opengl "
                "in the image or unset GYM_ANYTHING_QEMU_DBUS_AUTO_INSTALL=0."
            )

        lock_path = sandbox.with_suffix(".lock")
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with open(lock_path, "w") as lock_file:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
            try:
                if self._container_supports_dbus_display(str(sandbox)):
                    self._container_image = str(sandbox)
                    return

                tmp_sandbox = sandbox.with_name(f".{sandbox.name}.tmp-{os.getpid()}")
                shutil.rmtree(tmp_sandbox, ignore_errors=True)
                print(f"[QemuApptainer] Preparing D-Bus-capable QEMU sandbox: {sandbox}")

                try:
                    build = subprocess.run(
                        [
                            "apptainer",
                            "build",
                            "--fakeroot",
                            "--sandbox",
                            str(tmp_sandbox),
                            QEMU_CONTAINER,
                        ],
                        capture_output=True,
                        text=True,
                        timeout=1800,
                    )
                    if build.returncode != 0:
                        raise RuntimeError(
                            "Failed to build QEMU D-Bus sandbox:\n"
                            + (build.stderr or build.stdout)
                        )

                    install = subprocess.run(
                        [
                            "apptainer",
                            "exec",
                            "--fakeroot",
                            "--writable",
                            str(tmp_sandbox),
                            "bash",
                            "-lc",
                            (
                                "apt-get update && "
                                "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "
                                "qemu-system-modules-opengl dbus && "
                                "rm -rf /var/lib/apt/lists/*"
                            ),
                        ],
                        capture_output=True,
                        text=True,
                        timeout=1800,
                    )
                    if install.returncode != 0:
                        raise RuntimeError(
                            "Failed to install QEMU D-Bus display modules:\n"
                            + (install.stderr or install.stdout)
                        )

                    if not self._container_supports_dbus_display(str(tmp_sandbox)):
                        raise RuntimeError(
                            "QEMU D-Bus sandbox was prepared, but '-display dbus' is still unavailable"
                        )
                except Exception:
                    shutil.rmtree(tmp_sandbox, ignore_errors=True)
                    raise

                shutil.rmtree(sandbox, ignore_errors=True)
                tmp_sandbox.rename(sandbox)
                self._container_image = str(sandbox)
            finally:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

    def _display_backend_arg(self, work_dir: Path) -> str:
        if not self._fast_io or self._fast_io_backend() != "dbus":
            return "none"
        if self._dbus_display is None:
            from .qemu_dbus_display import QemuDbusDisplayCapture

            self._dbus_display = QemuDbusDisplayCapture(work_dir)
            self._dbus_display.start_bus()
        return f"dbus,addr={self._dbus_display.bus_address}"

    def _start_fast_io_display_listener(self) -> None:
        if self._fast_io and self._fast_io_backend() == "dbus":
            if self._dbus_display is None:
                raise RuntimeError("QEMU D-Bus display was not initialized")
            self._dbus_display.start_listener()

    def _fast_input_agent_script(self) -> Path:
        return Path(__file__).parent / "linux_uinput_fast_inputd.py"

    def _ensure_fast_input_agent(self) -> None:
        if not self._fast_uinput_keyboard_enabled():
            return
        if not self.ssh_port or not self._fast_input_host_port:
            raise RuntimeError("fast uinput keyboard requested before SSH and host forwarding were configured")

        script_path = self._fast_input_agent_script()
        if not script_path.exists():
            raise RuntimeError(f"fast input agent script is missing: {script_path}")

        remote_tmp = "/tmp/gym_anything_fast_inputd.py"
        remote_bin = "/usr/local/bin/gym-anything-fast-inputd"
        log_path = "/tmp/gym_anything_fast_inputd.log"

        self._sftp_copy_to(str(script_path), remote_tmp)
        install_cmd = (
            f"sudo -n install -m 0755 {shlex.quote(remote_tmp)} {shlex.quote(remote_bin)} && "
            "(sudo -n modprobe uinput 2>/dev/null || true); "
            "test -e /dev/uinput"
        )
        result = self._ssh_command(f"bash -lc {shlex.quote(install_cmd)}", timeout=30, use_pty=False)
        if result.returncode != 0:
            stderr = result.stderr.decode(errors="replace") if result.stderr else ""
            raise RuntimeError(f"fast uinput keyboard requires /dev/uinput in the guest: {stderr[:500]}")

        try:
            self._connect_fast_input_agent(timeout=1.0)
        except RuntimeError:
            if self._fast_input_client:
                self._fast_input_client.close()
                self._fast_input_client = None
        else:
            self._validate_fast_input_agent()
            return

        start_cmd = (
            f"sudo -n env PYTHONUNBUFFERED=1 DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority "
            f"nohup python3 {shlex.quote(remote_bin)} "
            f"--host 0.0.0.0 "
            f"--port {int(self._fast_input_guest_port)} "
            f"--device-name {shlex.quote(self._fast_input_device_name)} "
            f"--x11-display :1 "
            f"--require-x11 "
            f"> {shlex.quote(log_path)} 2>&1 < /dev/null &"
        )
        result = self._ssh_command(f"bash -lc {shlex.quote(start_cmd)}", timeout=10, use_pty=False)
        try:
            self._connect_fast_input_agent(timeout=15.0)
        except RuntimeError as exc:
            stdout = result.stdout.decode(errors="replace") if result.stdout else ""
            stderr = result.stderr.decode(errors="replace") if result.stderr else ""
            raise RuntimeError(
                "failed to start fast input agent "
                f"(ssh exit={result.returncode}, stdout={stdout[:500]!r}, stderr={stderr[:500]!r}): {exc}"
            ) from exc
        self._validate_fast_input_agent()

    def _connect_fast_input_agent(self, timeout: float = 15.0) -> None:
        if not self._fast_input_host_port:
            raise RuntimeError("fast input host port is not configured")
        deadline = time.time() + timeout
        last_error: Optional[Exception] = None
        while time.time() < deadline:
            client = _FastInputAgentClient("127.0.0.1", self._fast_input_host_port, timeout=1.0)
            try:
                response = client.request({"op": "ping"})
                if response.get("version") != 1 or response.get("backend") != "uinput":
                    raise RuntimeError(f"unexpected fast input agent handshake: {response}")
                self._fast_input_client = client
                return
            except Exception as exc:
                last_error = exc
                client.close()
                time.sleep(0.2)

        log = self._read_fast_input_agent_log()
        raise RuntimeError(
            "fast input agent did not become reachable "
            f"on localhost:{self._fast_input_host_port}: {last_error}\n{log}"
        )

    def _read_fast_input_agent_log(self) -> str:
        if not self.ssh_port:
            return ""
        result = self._ssh_command("tail -n 80 /tmp/gym_anything_fast_inputd.log 2>/dev/null || true", timeout=10, use_pty=False)
        stdout = result.stdout.decode(errors="replace") if result.stdout else ""
        stderr = result.stderr.decode(errors="replace") if result.stderr else ""
        return (stdout + "\n" + stderr).strip()

    def _validate_fast_input_agent(self) -> None:
        if not self.ssh_port:
            raise RuntimeError("cannot validate fast input agent without SSH")
        deadline = time.time() + 8.0
        last_xinput = ""
        last_devices = ""
        while time.time() < deadline:
            xinput_result = self._ssh_command("DISPLAY=:1 xinput list --short", timeout=5, use_pty=False)
            devices_result = self._ssh_command("cat /proc/bus/input/devices", timeout=5, use_pty=False)
            last_xinput = xinput_result.stdout.decode(errors="replace") if xinput_result.stdout else ""
            last_devices = devices_result.stdout.decode(errors="replace") if devices_result.stdout else ""
            combined = f"{last_xinput}\n{last_devices}".lower()
            if self._fast_input_device_name.lower() in combined and "usb tablet" in combined:
                return
            time.sleep(0.25)

        log = self._read_fast_input_agent_log()
        raise RuntimeError(
            "fast input agent started, but the expected uinput keyboard/tablet devices "
            "were not visible in the guest.\n"
            f"xinput:\n{last_xinput[-2000:]}\n"
            f"/proc/bus/input/devices:\n{last_devices[-2000:]}\n"
            f"agent log:\n{log}"
        )

    def _get_fast_input_client(self) -> _FastInputAgentClient:
        if not self._fast_uinput_keyboard_enabled():
            raise RuntimeError("fast input agent is only available for the uinput keyboard backend")
        if self._fast_input_client is None:
            self._connect_fast_input_agent(timeout=3.0)
        assert self._fast_input_client is not None
        return self._fast_input_client

    def _get_accel_args(self) -> List[str]:
        """Return QEMU acceleration arguments. Subclasses override for HVF etc."""
        if self.enable_kvm:
            return ["-accel", "kvm"]
        return []

    def _get_cpu_model(self) -> str:
        """Return CPU model for -cpu flag. Subclasses override for TCG."""
        return "host"

    def _get_linux_display_device(self, width: int, height: int) -> str:
        """Return the display device for Linux guests. Subclasses override for TCG."""
        return f"virtio-vga,xres={width},yres={height}"

    def _fast_input_hid_args(self) -> List[str]:
        return [
            "-device", "qemu-xhci,id=fastio_xhci",
            "-device", "usb-kbd,id=fastio_kbd,bus=fastio_xhci.0",
            "-device", "usb-tablet,id=fastio_tablet,bus=fastio_xhci.0",
        ]

    def _post_boot_settle_seconds(self) -> int:
        """Seconds to wait after desktop is ready for compositor to render.
        Subclasses override for TCG where software rendering is slow."""
        return 0

    def _build_qemu_cmd(self, disk: Path, vnc_port: int, ssh_port: int, work_dir: Path, loadvm_snapshot: Optional[str] = None) -> List[str]:
        """Build QEMU command. Delegates to overridable helpers for container/accel."""
        # Debug: show savevm state when building command
        if self.is_windows:
            print(f"[QemuApptainer] Building QEMU command: _use_savevm={self._use_savevm}, loadvm={loadvm_snapshot}")
        disk_abs = str(disk.absolute())

        # Stage 1: Container prefix (overridable — empty for native runner)
        cmd = self._build_container_prefix(work_dir, disk)

        # Stage 2: QEMU binary + acceleration
        cmd.append("qemu-system-x86_64")
        cmd.extend(self._get_accel_args())

        # Calculate VNC display number from port (port 5900 = display :0)
        vnc_display = vnc_port - 5900

        # Use virtio-gpu with specific resolution for proper display
        width, height = self.resolution
        display_backend = self._display_backend_arg(work_dir)

        # Build netdev with port forwards
        if self.is_android:
            port_forwards = f"hostfwd=tcp::{self.adb_port}-:{self._adb_guest_port}"
        else:
            port_forwards = f"hostfwd=tcp::{ssh_port}-:22"
            if self.is_windows:
                port_forwards += f",hostfwd=tcp::{self.pyautogui_port}-:5555"
            fast_input_host_port = getattr(self, "_fast_input_host_port", None)
            if self._fast_uinput_keyboard_enabled() and fast_input_host_port:
                port_forwards += f",hostfwd=tcp::{fast_input_host_port}-:{self._fast_input_guest_port}"

        netdev_options = f"user,id=net0,{port_forwards}"
        if getattr(getattr(getattr(self, "spec", None), "resources", None), "net", None) is False:
            netdev_options = f"user,id=net0,restrict=on,{port_forwards}"

        cmd.extend([
            "-m", self.memory,
            "-smp", str(self.cpus),
            "-cpu", self._get_cpu_model(),
        ])

        if self._fast_io:
            self._qmp_socket_path = work_dir / "qmp.sock"
            try:
                self._qmp_socket_path.unlink()
            except FileNotFoundError:
                pass
            cmd.extend(["-qmp", f"unix:{self._qmp_socket_path},server=on,wait=off"])

        if self.is_android:
            # Android (BlissOS): Boot from live ISO with virtio disk for persistence
            # The ISO provides the live system, disk is for user data
            iso_path = QEMU_CACHE / "blissos-16.iso"
            cmd.extend([
                "-drive", f"file={disk_abs},format=qcow2,if=virtio",
                "-cdrom", str(iso_path),
                "-device", f"virtio-vga,xres={width},yres={height}",
                "-vnc", f":{vnc_display},password=on",
                "-display", display_backend,
                "-monitor", "stdio",
                "-device", "virtio-net-pci,netdev=net0",
                "-netdev", netdev_options,
                "-boot", "d",  # Boot from CD-ROM (live ISO)
                # USB for keyboard/mouse (Android needs USB HID)
                "-usb",
                "-device", "usb-kbd",
                "-device", "usb-tablet",
            ])
        elif self.is_windows:
            # Windows: Use UEFI boot with virtio for best performance
            # MUST match the build script configuration exactly!
            # OVMF firmware files are required for UEFI boot
            ovmf_code = QEMU_CACHE / "OVMF_CODE_4M.fd"
            ovmf_vars = work_dir / "OVMF_VARS.fd"

            # Copy OVMF_VARS to work directory (each instance needs its own copy)
            ovmf_vars_src = QEMU_CACHE / "base_windows_11_vars.fd"
            if not ovmf_vars.exists() and ovmf_vars_src.exists():
                shutil.copy(ovmf_vars_src, ovmf_vars)

            # NOTE: For savevm to work, ALL writable disks must support snapshots.
            # pflash (raw format) does NOT support snapshots, causing savevm to fail with:
            # "Error: Device 'pflash1' is writable but does not support snapshots"
            # Solution: Make OVMF_VARS readonly. This prevents EFI variable changes
            # after boot, but that's acceptable for checkpoint/restore scenarios.
            # See: https://lists.gnu.org/archive/html/qemu-discuss/2022-10/msg00010.html
            ovmf_vars_readonly = "readonly=on" if self._use_savevm else ""
            ovmf_vars_drive = f"if=pflash,format=raw,file={ovmf_vars}"
            if ovmf_vars_readonly:
                ovmf_vars_drive += f",{ovmf_vars_readonly}"

            cmd.extend([
                # UEFI firmware (pflash devices)
                "-drive", f"if=pflash,format=raw,readonly=on,file={ovmf_code}",
                "-drive", ovmf_vars_drive,
                # Disk with virtio (best performance)
                "-drive", f"file={disk_abs},format=qcow2,if=virtio",
                # Display with virtio-vga
                "-device", "virtio-vga",
                "-vnc", f":{vnc_display},password=on",
                "-display", display_backend,
                "-monitor", "stdio",
                # Network with virtio
                "-device", "virtio-net-pci,netdev=net0",
                "-netdev", netdev_options,
                "-boot", "c",
            ])
            if self._fast_io:
                cmd.extend(self._fast_input_hid_args())
        else:
            # Linux: Use virtio for better performance
            # Note: VirGL with egl-headless requires qemu-system-modules-opengl
            # which may not be available in all container images.
            # For now, use standard virtio-vga with software rendering.
            # GPU devices are still passed through for applications that
            # access them directly (e.g., DaVinci Resolve uses OpenCL).
            display_device = self._get_linux_display_device(width, height)

            cmd.extend([
                "-drive", f"file={disk_abs},format=qcow2,if=virtio",
                "-device", display_device,
                "-vnc", f":{vnc_display},password=on",
                "-display", display_backend,
                "-monitor", "stdio",
                "-device", "virtio-net-pci,netdev=net0",
                "-netdev", netdev_options,
                "-boot", "c",
            ])
            if self._fast_io:
                cmd.extend(self._fast_input_hid_args())

        # Load VM state from snapshot (the correct way to restore savevm snapshots)
        if loadvm_snapshot:
            cmd.extend(["-loadvm", loadvm_snapshot])

        return cmd
    
    def _start_vm(self, loadvm_snapshot: Optional[str] = None) -> None:
        """Start the VM.

        Args:
            loadvm_snapshot: If provided, start QEMU with -loadvm to restore this snapshot.
        """
        cmd = self._build_qemu_cmd(self._instance_qcow2, self.vnc_port, self.ssh_port, self._work_dir, loadvm_snapshot=loadvm_snapshot)

        log_file = self._work_dir / "qemu.log"
        with open(log_file, "w") as lf:
            self._process = subprocess.Popen(
                cmd, stdin=subprocess.PIPE, stdout=lf, stderr=subprocess.STDOUT,
                cwd=str(self._work_dir), preexec_fn=os.setsid
            )
        self._start_fast_io_display_listener()

        # Set VNC password via QEMU monitor (required for macOS Screen Sharing compatibility)
        self._set_vnc_password()

    def _set_vnc_password(self) -> None:
        """Set VNC password via QEMU monitor.

        QEMU is started with -vnc :N,password=on which requires the password
        to be set via the monitor before clients can connect.
        """
        if not self._process or not self._process.stdin:
            return

        try:
            # Wait a moment for QEMU to initialize
            time.sleep(0.5)

            # Send password command to monitor
            # Format: change vnc password <password>
            cmd = f"change vnc password {self.vnc_password}\n"
            self._process.stdin.write(cmd.encode())
            self._process.stdin.flush()
            print(f"[QemuApptainer] VNC password set (port {self.vnc_port})")
        except Exception as e:
            print(f"[QemuApptainer] Warning: Failed to set VNC password: {e}")
    
    def _wait_for_vnc(self, timeout: float = 120) -> bool:
        """Wait for VNC."""
        import socket
        start = time.time()
        while time.time() - start < timeout:
            if self._process and self._process.poll() is not None:
                return False
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.settimeout(2)
                    s.connect(("localhost", self.vnc_port))
                    data = s.recv(12)
                    if data.startswith(b"RFB "):
                        return True
            except:
                pass
            time.sleep(2)
        return False
    
    def _wait_for_ssh(self, port: int, timeout: float = 120) -> bool:
        """Wait for SSH to become available."""
        import socket
        print(f"[QemuApptainer] Waiting for SSH on port {port}...")
        start = time.time()
        while time.time() - start < timeout:
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.settimeout(5)
                    s.connect(("localhost", port))
                    data = s.recv(256)
                    if b"SSH" in data:
                        print(f"[QemuApptainer] SSH available!")
                        time.sleep(5)  # Give SSH a moment to fully initialize
                        return True
            except:
                pass
            time.sleep(2)
        print(f"[QemuApptainer] SSH timeout after {timeout}s")
        return False

    def _test_ssh_auth(self) -> bool:
        """Test if SSH authentication works.

        Returns True if auth succeeds, False otherwise.
        """
        try:
            import paramiko
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect(
                "localhost",
                port=self.ssh_port,
                username=self._ssh_user,
                password=self._ssh_password,
                timeout=10,
                look_for_keys=False
            )
            # Auth succeeded - try a simple command
            stdin, stdout, stderr = client.exec_command("echo ok", timeout=10)
            result = stdout.read().decode().strip()
            client.close()
            if result == "ok":
                print("[QemuApptainer] SSH auth test: SUCCESS")
                return True
            print(f"[QemuApptainer] SSH auth test: command returned '{result}'")
            return False
        except paramiko.AuthenticationException:
            print("[QemuApptainer] SSH auth test: FAILED (authentication error)")
            return False
        except Exception as e:
            print(f"[QemuApptainer] SSH auth test: FAILED ({e})")
            return False

    def _unlock_windows_via_vnc(self) -> bool:
        """Unlock Windows lock screen via VNC keyboard.

        This is needed when Windows has a password set and auto-login is disabled.
        The method tries multiple approaches:
        1. Click center of screen to dismiss lock screen clock
        2. Try with configured password
        3. If that fails, try with empty password (dockur/windows default)

        Returns True if unlock was attempted, False if VNC not available.
        """
        print("[QemuApptainer] Attempting to unlock Windows via VNC...")

        # Connect VNC temporarily for unlock
        temp_vnc = VNCConnectionPool(
            host="localhost",
            port=self.vnc_port,
            password=self.vnc_password
        )
        conn = temp_vnc.get_connection(retry_count=3, retry_delay=2.0)
        if not conn:
            print("[QemuApptainer] VNC not available for unlock")
            return False

        try:
            width, height = conn.resolution
            center_x, center_y = width // 2, height // 2

            # Step 1: Click center of screen to dismiss the lock screen clock
            print("[QemuApptainer] Clicking to dismiss lock screen...")
            conn.send_mouse_click(center_x, center_y, button=1)
            time.sleep(0.5)
            # Also try pressing a key
            conn.send_key("space", down=True)
            time.sleep(0.05)
            conn.send_key("space", down=False)
            time.sleep(3)  # Wait for password prompt to appear

            # Step 2: Try with configured password first
            if self._ssh_password:
                print(f"[QemuApptainer] Trying password: {self._ssh_password[:3]}***")
                conn.type_text(self._ssh_password, delay=0.05)
                time.sleep(0.5)
                conn.send_key("Return", down=True)
                time.sleep(0.05)
                conn.send_key("Return", down=False)
                time.sleep(5)

                # Check if it worked by looking for explorer
                result = self._run_ssh_cmd(
                    self.ssh_port,
                    'powershell -Command "Get-Process explorer -ErrorAction SilentlyContinue"',
                    timeout=10
                )
                stdout = result.stdout.decode() if result.stdout else ""
                if "explorer" in stdout.lower():
                    print("[QemuApptainer] Login successful with password!")
                    time.sleep(10)
                    return True

            # Step 3: If password didn't work, try empty password (just Enter)
            print("[QemuApptainer] Trying empty password (dockur/windows default)...")
            # Click again to reset
            conn.send_mouse_click(center_x, center_y, button=1)
            time.sleep(1)
            conn.send_key("Escape", down=True)  # Clear any typed text
            time.sleep(0.05)
            conn.send_key("Escape", down=False)
            time.sleep(1)
            conn.send_mouse_click(center_x, center_y, button=1)
            time.sleep(2)
            # Just press Enter for empty password
            conn.send_key("Return", down=True)
            time.sleep(0.05)
            conn.send_key("Return", down=False)

            # Wait for desktop to load
            print("[QemuApptainer] Waiting for desktop to load after unlock...")
            time.sleep(15)

            return True

        except Exception as e:
            print(f"[QemuApptainer] VNC unlock error: {e}")
            return False
        finally:
            temp_vnc.close()

    def _wait_for_desktop(self, timeout: float = 120) -> bool:
        """Wait for desktop to be fully ready.

        Linux: Polls wmctrl to check if the window manager is responding.
        Windows: Checks if explorer.exe is running and pyautogui can access screen.

        This is more reliable than a fixed sleep because it adapts to
        actual boot time and confirms the desktop is truly ready.
        """
        print(f"[QemuApptainer] Waiting for desktop to be ready...")
        start = time.time()
        last_error = ""

        if self.is_windows:
            # Windows: Wait for desktop by checking explorer.exe, then start pyautogui server
            unlock_attempted = False
            ssh_auth_failed_count = 0

            while time.time() - start < timeout:
                result = None
                try:
                    # Check if explorer.exe is running (Windows shell)
                    result = self._run_ssh_cmd(
                        self.ssh_port,
                        'powershell -Command "Get-Process explorer -ErrorAction SilentlyContinue | Select-Object -First 1"',
                        timeout=15
                    )
                    stdout = result.stdout.decode() if result.stdout else ""

                    if result.returncode == 0 and "explorer" in stdout.lower():
                        elapsed = time.time() - start
                        print(f"[QemuApptainer] Windows desktop ready after {elapsed:.1f}s")

                        # Start pyautogui server in desktop session
                        if self._start_windows_pyautogui_server():
                            print(f"[QemuApptainer] PyAutoGUI server started and connected")
                            return True
                        else:
                            last_error = "Failed to start pyautogui server"
                    else:
                        last_error = "explorer.exe not running yet"

                except Exception as e:
                    last_error = str(e)

                # Check if SSH auth failed (indicates lock screen) - check result stderr
                stderr_str = result.stderr.decode() if result and result.stderr else ""
                if "Authentication failed" in stderr_str or "authentication failed" in stderr_str.lower():
                    ssh_auth_failed_count += 1
                    # Try VNC unlock after a few auth failures (to give VM time to boot first)
                    if ssh_auth_failed_count >= 2 and not unlock_attempted:
                        print("[QemuApptainer] SSH auth failing - Windows may be at lock screen")
                        unlock_attempted = True
                        if self._unlock_windows_via_vnc():
                            print("[QemuApptainer] VNC unlock completed, retrying SSH...")
                            time.sleep(5)  # Give Windows time after login
                            continue

                time.sleep(3)

            print(f"[QemuApptainer] Windows desktop timeout after {timeout}s (last error: {last_error})")
            return False

        # Linux: Poll wmctrl
        while time.time() - start < timeout:
            try:
                # Try wmctrl - it will fail if window manager isn't ready
                # We use _run_ssh_cmd directly to avoid the sudo wrapper
                result = self._run_ssh_cmd(
                    self.ssh_port,
                    "DISPLAY=:1 wmctrl -l 2>&1",
                    timeout=10
                )
                stdout = result.stdout.decode() if result.stdout else ""
                stderr = result.stderr.decode() if result.stderr else ""

                if result.returncode == 0:
                    elapsed = time.time() - start
                    print(f"[QemuApptainer] Desktop ready after {elapsed:.1f}s")
                    # Setup X authentication for pyautogui access:
                    # 1. Create .Xauthority file (python-xlib requires it to exist)
                    # 2. Disable X auth for local connections
                    self._run_ssh_cmd(self.ssh_port, "touch /home/ga/.Xauthority", timeout=10)
                    self._run_ssh_cmd(self.ssh_port, "DISPLAY=:1 xhost +local: 2>/dev/null || true", timeout=10)
                    print(f"[QemuApptainer] X authentication configured for pyautogui access")
                    return True

                # Check for specific errors that indicate we should keep waiting
                output = stdout + stderr
                if "Cannot open display" in output or "Authorization required" in output:
                    # X11 not ready yet, keep waiting
                    last_error = output.strip()[:100]
                elif result.returncode != 0:
                    last_error = f"wmctrl exit code {result.returncode}"

            except Exception as e:
                last_error = str(e)

            time.sleep(2)

        print(f"[QemuApptainer] Desktop timeout after {timeout}s (last error: {last_error})")
        return False

    # === ADB methods (Android only) ===

    def _find_adb(self) -> Optional[str]:
        """Find the ADB binary path."""
        if self._adb_path:
            return self._adb_path

        # Check if adb is in PATH
        adb_path = shutil.which("adb")
        if adb_path:
            self._adb_path = adb_path
            return adb_path

        # Check common locations
        common_paths = [
            Path.home() / "Android" / "Sdk" / "platform-tools" / "adb",
            Path.home() / ".android" / "platform-tools" / "adb",
            Path("/opt/android-sdk/platform-tools/adb"),
            QEMU_CACHE / "platform-tools" / "adb",
        ]
        for p in common_paths:
            if p.exists():
                self._adb_path = str(p)
                return self._adb_path

        print("[QemuApptainer] Warning: ADB not found. Install Android SDK platform-tools.")
        return None

    def _adb_command(self, args: List[str], timeout: int = 60, capture: bool = True) -> subprocess.CompletedProcess:
        """Run an ADB command targeting this instance."""
        adb = self._find_adb()
        if not adb:
            return subprocess.CompletedProcess([], 1, b"", b"adb not found")

        # Connect to the Android device via TCP
        device = f"localhost:{self.adb_port}"
        cmd = [adb, "-s", device] + args

        try:
            result = subprocess.run(cmd, capture_output=capture, timeout=timeout)
            return result
        except subprocess.TimeoutExpired:
            print(f"[QemuApptainer] ADB command timed out: {' '.join(args[:3])}...")
            return subprocess.CompletedProcess(cmd, 1, b"", b"timeout")
        except Exception as e:
            print(f"[QemuApptainer] ADB error: {e}")
            return subprocess.CompletedProcess(cmd, 1, b"", str(e).encode())

    def _wait_for_adb(self, timeout: float = 180) -> bool:
        """Wait for ADB to become available on the Android device."""
        adb = self._find_adb()
        if not adb:
            print("[QemuApptainer] ADB binary not found")
            return False

        print(f"[QemuApptainer] Waiting for ADB on port {self.adb_port}...")
        device = f"localhost:{self.adb_port}"
        start = time.time()

        while time.time() - start < timeout:
            # Try to connect to the device
            try:
                # First connect to the device
                connect_result = subprocess.run(
                    [adb, "connect", device],
                    capture_output=True,
                    timeout=10
                )
                connect_stdout = connect_result.stdout.decode()

                if "connected" in connect_stdout.lower():
                    # Wait a moment for connection to stabilize
                    time.sleep(2)

                    # Check device status
                    devices_result = subprocess.run(
                        [adb, "devices"],
                        capture_output=True,
                        timeout=10
                    )
                    devices_stdout = devices_result.stdout.decode()

                    if device in devices_stdout and "device" in devices_stdout:
                        # Try a simple command to verify
                        test_result = subprocess.run(
                            [adb, "-s", device, "shell", "getprop", "ro.build.version.sdk"],
                            capture_output=True,
                            timeout=10
                        )
                        if test_result.returncode == 0:
                            sdk_version = test_result.stdout.decode().strip()
                            elapsed = time.time() - start
                            print(f"[QemuApptainer] ADB connected! SDK version: {sdk_version} ({elapsed:.1f}s)")
                            return True

            except subprocess.TimeoutExpired:
                pass
            except Exception as e:
                pass

            time.sleep(3)

        print(f"[QemuApptainer] ADB timeout after {timeout}s")
        return False

    def _android_first_boot_setup(self) -> None:
        """Handle Android first-boot setup via ADB.

        This dismisses the launcher selection dialog and sets up the desktop.
        """
        print("[QemuApptainer] Running Android first-boot setup...")

        # Wait a moment for the UI to be ready
        time.sleep(5)

        # Try to dismiss the "Select a Home app" dialog by selecting Launcher3
        # and pressing "Always"
        try:
            # Select Launcher3 (tap on it)
            self._adb_command(["shell", "input", "tap", "485", "613"])
            time.sleep(1)

            # Tap on "Always" button
            self._adb_command(["shell", "input", "tap", "825", "733"])
            time.sleep(2)

            # Press Home to go to home screen
            self._adb_command(["shell", "input", "keyevent", "KEYCODE_HOME"])
            time.sleep(1)

            print("[QemuApptainer] First-boot setup completed")
        except Exception as e:
            print(f"[QemuApptainer] First-boot setup error (may be ok): {e}")

    def _setup_mounts_adb(self) -> None:
        """Setup mounts for Android via ADB push."""
        mounts = getattr(self.spec, "mounts", [])
        if not mounts:
            return

        print(f"[QemuApptainer] Setting up {len(mounts)} mounts via ADB...")

        for mount in mounts:
            if isinstance(mount, dict):
                source = mount.get("source", "")
                target = mount.get("target", "")
            else:
                source = getattr(mount, "source", "")
                target = getattr(mount, "target", "")

            if not source or not target:
                continue

            # Resolve source path relative to workspace
            source_path = Path(source)
            if not source_path.is_absolute():
                source_path = Path.cwd() / source_path

            if not source_path.exists():
                print(f"[QemuApptainer] Mount source not found: {source_path}")
                continue

            # Push files to Android - create target dir first and push contents
            print(f"[QemuApptainer] Pushing {source_path} -> {target}")

            # Create the target directory
            self._adb_command(["shell", "mkdir", "-p", target])

            if source_path.is_dir():
                # For directories, push contents recursively
                # First, create all subdirectories
                for subdir in source_path.rglob("*"):
                    if subdir.is_dir():
                        rel_path = subdir.relative_to(source_path)
                        target_subdir = f"{target}/{rel_path}"
                        self._adb_command(["shell", "mkdir", "-p", target_subdir])

                # Then push all files individually
                for file_path in source_path.rglob("*"):
                    if file_path.is_file():
                        rel_path = file_path.relative_to(source_path)
                        target_file = f"{target}/{rel_path}"
                        result = self._adb_command(["push", str(file_path), target_file])
                        if result.returncode != 0:
                            print(f"[QemuApptainer] ADB push failed for {file_path.name}: {result.stderr.decode()[:100]}")
            else:
                # Single file push
                result = self._adb_command(["push", str(source_path), target])
                if result.returncode != 0:
                    print(f"[QemuApptainer] ADB push failed: {result.stderr.decode()[:200]}")

    def _start_windows_pyautogui_server(self) -> bool:
        """Start the pyautogui server on Windows and connect to it.

        The pyautogui server needs to run in the desktop session (not SSH session)
        to have access to mouse/keyboard/screen. We use Windows Task Scheduler
        to start it in the interactive session.

        Returns True if server started and client connected successfully.
        """
        if not self.ssh_port:
            return False

        print(f"[QemuApptainer] Starting PyAutoGUI server on Windows...")

        # Kill any stale servers before we try to connect/start.
        #
        # On Windows, multiple python processes can sometimes end up bound to the same
        # port (5555) when /IT scheduled tasks are retried without cleanup. If any of
        # those processes run an older protocol, clients will intermittently receive
        # non-matching responses and fail health checks ("ping"/screenshots).
        try:
            self._run_ssh_cmd(
                self.ssh_port,
                (
                    "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" "
                    "| Where-Object { $_.CommandLine -match 'pyautogui_server\\.py' -or $_.CommandLine -match '--port\\s+5555' } "
                    "| ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
                ),
                timeout=30,
            )
        except Exception:
            # Best-effort; if this fails we'll still attempt to start/connect.
            pass

        # First, check if server is already running
        try:
            self._pyautogui_client = PyAutoGUIClient(
                host="localhost",
                port=self.pyautogui_port,
                timeout=5.0
            )
            self._pyautogui_client.connect()
            if self._pyautogui_client.ping():
                print(f"[QemuApptainer] PyAutoGUI server already running")
                return True
        except:
            pass

        # Copy the server script to Windows
        server_script_path = Path(__file__).parent / "windows_pyautogui_server.py"
        if not server_script_path.exists():
            print(f"[QemuApptainer] Server script not found: {server_script_path}")
            return False

        # Copy to Windows temp directory (use C:\Windows\Temp for reliability)
        # The SSH user may vary (Docker, ga, etc.) so we use a system temp path
        remote_script = "C:\\Windows\\Temp\\pyautogui_server.py"
        print(f"[QemuApptainer] Copying server script from {server_script_path} to {remote_script}")
        try:
            self._sftp_copy_to(str(server_script_path), remote_script)
            print(f"[QemuApptainer] Script copied successfully")
        except Exception as e:
            print(f"[QemuApptainer] Script copy failed: {e}")
            return False

        # Start the server using schtasks to run in interactive session
        # Create a scheduled task that runs immediately in the desktop session
        task_name = "PyAutoGUIServer"
        # Server listens on guest port 5555, QEMU forwards host:pyautogui_port -> guest:5555
        guest_port = 5555
        remote_launcher = "C:\\Windows\\Temp\\pyautogui_server_hidden.vbs"

        launcher_body = (
            'Set WshShell = CreateObject("WScript.Shell")\r\n'
            f'WshShell.Run "cmd /c python ""{remote_script}"" --port {guest_port}", 0, False\r\n'
        )
        local_launcher: Optional[str] = None
        try:
            with tempfile.NamedTemporaryFile("w", suffix=".vbs", delete=False, encoding="ascii", newline="") as tmp:
                tmp.write(launcher_body)
                local_launcher = tmp.name
            self._sftp_copy_to(local_launcher, remote_launcher)
            print(f"[QemuApptainer] Hidden launcher copied to {remote_launcher}")
        except Exception as e:
            print(f"[QemuApptainer] Hidden launcher copy failed: {e}")
            return False
        finally:
            if local_launcher:
                try:
                    os.unlink(local_launcher)
                except OSError:
                    pass

        # First delete any existing task (use $null for PowerShell compatibility)
        self._run_ssh_cmd(
            self.ssh_port,
            f'schtasks /Delete /TN "{task_name}" /F 2>$null',
            timeout=15
        )

        # Create and run a task in interactive session
        # Using /IT flag to run only when user is logged on, /RL HIGHEST for admin
        # Avoid schtasks warnings about start-time being earlier than current time by
        # setting a far-future start date. We still run the task immediately via /Run.
        create_cmd = (
            f'schtasks /Create /TN "{task_name}" /TR '
            f'"wscript.exe {remote_launcher}" '
            f'/SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F'
        )
        print(f"[QemuApptainer] Creating scheduled task: {create_cmd}")
        result = self._run_ssh_cmd(self.ssh_port, create_cmd, timeout=15)
        print(f"[QemuApptainer] Task creation result: returncode={result.returncode}, stdout={result.stdout.decode()[:200] if result.stdout else ''}")
        if result.returncode != 0:
            print(f"[QemuApptainer] Failed to create scheduled task: {result.stderr.decode()[:200] if result.stderr else ''}")
            # Try alternative: start via powershell with -WindowStyle Hidden
            alt_cmd = (
                f'powershell -Command "Start-Process python -ArgumentList '
                f'\'{remote_script} --port {guest_port}\' -WindowStyle Hidden"'
            )
            print(f"[QemuApptainer] Trying alternative: {alt_cmd}")
            self._run_ssh_cmd(self.ssh_port, alt_cmd, timeout=15)

        # Run the task
        run_cmd = f'schtasks /Run /TN "{task_name}"'
        print(f"[QemuApptainer] Running task: {run_cmd}")
        run_result = self._run_ssh_cmd(self.ssh_port, run_cmd, timeout=15)
        print(f"[QemuApptainer] Task run result: returncode={run_result.returncode}, stdout={run_result.stdout.decode()[:200] if run_result.stdout else ''}")

        # Wait for server to be available (client connects to host port which forwards to guest)
        print(f"[QemuApptainer] Waiting for PyAutoGUI server (guest:{guest_port} via host:{self.pyautogui_port})...")
        for attempt in range(30):  # 30 seconds timeout
            try:
                self._pyautogui_client = PyAutoGUIClient(
                    host="localhost",
                    port=self.pyautogui_port,  # Client connects to host port, QEMU forwards to guest
                    timeout=5.0
                )
                self._pyautogui_client.connect()
                if self._pyautogui_client.ping():
                    screen_size = self._pyautogui_client.get_screen_size()
                    print(f"[QemuApptainer] PyAutoGUI server connected! Screen: {screen_size}")
                    return True
            except Exception as e:
                if attempt == 29:
                    print(f"[QemuApptainer] PyAutoGUI server connection failed: {e}")
            time.sleep(1)

        print(f"[QemuApptainer] PyAutoGUI server failed to start")
        return False

    def _kill_existing_pyautogui_server(self) -> bool:
        """Kill any existing PyAutoGUI server processes.

        This is needed after loadvm restore because the restored server process
        has corrupted socket/threading state and cannot accept new connections.
        The TCP connections from when savevm was created become zombie connections.

        Returns True if any process was killed.
        """
        if not self.ssh_port:
            return False

        print(f"[QemuApptainer] Killing any existing PyAutoGUI server processes...")

        try:
            # Find and kill any python processes running the pyautogui server
            # Use taskkill with /F (force) and /IM (image name)
            # Note: Use PowerShell-compatible error suppression ($null instead of nul)
            result = self._ssh_command(
                'taskkill /F /IM python.exe 2>$null',
                timeout=30
            )
            # taskkill returns 0 on success, 128 if no matching processes
            if result.returncode == 0:
                print(f"[QemuApptainer] Killed existing Python processes")
                # Give the system a moment to clean up
                time.sleep(2)
                return True
            else:
                # No python processes running, that's fine
                print(f"[QemuApptainer] No existing Python processes to kill")
                return False
        except Exception as e:
            print(f"[QemuApptainer] Error killing PyAutoGUI server: {e}")
            return False

    def _try_connect_pyautogui_client(self, timeout: int = 30) -> bool:
        """Try to connect to an already-running PyAutoGUI server.

        This is a fallback for when desktop detection times out but the server
        may still be running (e.g., via Windows scheduled task at login).
        """
        port = self.pyautogui_port
        print(f"[QemuApptainer] Trying to connect to PyAutoGUI server on port {port}...")

        for attempt in range(timeout):
            try:
                self._pyautogui_client = PyAutoGUIClient(
                    host="localhost",
                    port=port,
                    timeout=5.0
                )
                self._pyautogui_client.connect()
                if self._pyautogui_client.ping():
                    print(f"[QemuApptainer] PyAutoGUI server connected!")
                    return True
            except Exception as e:
                if attempt == timeout - 1:
                    print(f"[QemuApptainer] PyAutoGUI connection failed: {e}")
                self._pyautogui_client = None
            time.sleep(1)

        print(f"[QemuApptainer] Could not connect to PyAutoGUI server")
        return False

    def _run_ssh_cmd(self, port: int, cmd: str, timeout: int = 120) -> subprocess.CompletedProcess:
        """Run SSH command to specific port using key or password auth."""
        ssh_key = Path.home() / ".ssh" / "ga_qemu_key"
        user = self._ssh_user
        password = self._ssh_password

        # For Windows or if SSH key doesn't exist, prefer paramiko with password auth
        if self.is_windows or not ssh_key.exists():
            try:
                import paramiko
                client = paramiko.SSHClient()
                client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                client.connect("localhost", port=port, username=user,
                              password=password, timeout=15, look_for_keys=False)
                # Don't use PTY for Windows - it causes terminal escape sequences that corrupt output
                # PTY is mainly needed for Linux sudo/su compatibility
                use_pty = not self.is_windows
                stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout, get_pty=use_pty)
                exit_code = stdout.channel.recv_exit_status()
                out = stdout.read()
                err = stderr.read()
                client.close()
                if exit_code != 0:
                    print(f"[QemuApptainer] SSH cmd failed: {err.decode()[:500]}")
                return subprocess.CompletedProcess([], exit_code, out, err)
            except Exception as pe:
                print(f"[QemuApptainer] SSH error: {pe}")
                return subprocess.CompletedProcess([], 1, b"", str(pe).encode())

        # Linux with SSH key
        full_cmd = [
            "ssh",
            "-t", "-t",  # Force TTY allocation for sudo/su compatibility
            "-i", str(ssh_key),
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=10",
            "-p", str(port),
            f"{user}@localhost",
            cmd
        ]
        try:
            result = subprocess.run(full_cmd, capture_output=True, timeout=timeout)
            if result.returncode != 0:
                print(f"[QemuApptainer] SSH cmd failed: {result.stderr.decode()[:500]}")
            return result
        except subprocess.TimeoutExpired:
            print(f"[QemuApptainer] SSH cmd timed out: {cmd[:50]}...")
            return subprocess.CompletedProcess(full_cmd, 1, b"", b"timeout")
        except Exception as e:
            # Try paramiko fallback with password
            try:
                import paramiko
                client = paramiko.SSHClient()
                client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                client.connect("localhost", port=port, username=user,
                              password=password, timeout=10, look_for_keys=False)
                stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout, get_pty=True)
                exit_code = stdout.channel.recv_exit_status()
                out = stdout.read()
                err = stderr.read()
                client.close()
                if exit_code != 0:
                    print(f"[QemuApptainer] SSH cmd failed: {err.decode()[:500]}")
                return subprocess.CompletedProcess([], exit_code, out, err)
            except Exception as pe:
                print(f"[QemuApptainer] SSH error: {pe}")
                return subprocess.CompletedProcess([], 1, b"", str(pe).encode())
    
    def _scp_to_vm(self, port: int, host_src: str, vm_dst: str) -> bool:
        """Copy file/directory to VM via SCP or SFTP."""
        ssh_key = Path.home() / ".ssh" / "ga_qemu_key"
        user = self._ssh_user
        password = self._ssh_password

        # For Windows or if SSH key doesn't exist, use paramiko SFTP
        if self.is_windows or not ssh_key.exists():
            try:
                import paramiko
                client = paramiko.SSHClient()
                client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                client.connect("localhost", port=port, username=user,
                              password=password, timeout=15, look_for_keys=False)
                sftp = client.open_sftp()

                src_path = Path(host_src.rstrip("/."))
                if src_path.is_dir():
                    # Copy directory recursively
                    for root, dirs, files in os.walk(src_path):
                        rel_root = Path(root).relative_to(src_path)
                        remote_dir = f"{vm_dst}/{rel_root}" if str(rel_root) != "." else vm_dst
                        try:
                            sftp.mkdir(remote_dir)
                        except:
                            pass
                        for f in files:
                            local_file = Path(root) / f
                            remote_file = f"{remote_dir}/{f}"
                            sftp.put(str(local_file), remote_file)
                else:
                    sftp.put(str(src_path), vm_dst)

                sftp.close()
                client.close()
                return True
            except Exception as e:
                print(f"[QemuApptainer] SFTP error: {e}")
                return False

        # Linux with SSH key - use native scp
        cmd = [
            "scp", "-r",
            "-i", str(ssh_key),
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-P", str(port),
            host_src, f"{user}@localhost:{vm_dst}"
        ]
        try:
            result = subprocess.run(cmd, capture_output=True, timeout=120)
            if result.returncode != 0:
                print(f"[QemuApptainer] SCP failed: {result.stderr.decode()[:200]}")
                return False
            return True
        except Exception as e:
            print(f"[QemuApptainer] SCP error: {e}")
            return False
    
    def _setup_mounts(self, ssh_port: int) -> None:
        """Copy mount directories to VM."""
        mounts = getattr(self.spec, "mounts", [])
        if not mounts:
            return

        print(f"[QemuApptainer] Setting up {len(mounts)} mounts...")

        for mount in mounts:
            if isinstance(mount, dict):
                source = mount.get("source", "")
                target = mount.get("target", "")
            else:
                source = getattr(mount, "source", "")
                target = getattr(mount, "target", "")

            if not source or not target:
                continue

            # Resolve source path relative to workspace
            source_path = Path(source)
            if not source_path.is_absolute():
                source_path = Path.cwd() / source_path

            if not source_path.exists():
                print(f"[QemuApptainer] Mount source not found: {source_path}")
                continue

            # Create target directory in VM (Windows vs Linux)
            if self.is_windows:
                # Convert Linux-style path to Windows path (e.g., /workspace -> C:\workspace)
                win_target = target.replace("/", "\\")
                if win_target.startswith("\\"):
                    win_target = "C:" + win_target

                # Create directory using PowerShell
                mkdir_cmd = f'powershell -Command "New-Item -ItemType Directory -Force -Path \'{win_target}\' | Out-Null"'
                self._ssh_command(mkdir_cmd)

                # Copy contents via SFTP
                print(f"[QemuApptainer] Copying {source_path} -> {win_target}")
                self._sftp_copy_to_windows(source_path, win_target)
            else:
                # Linux: Use sudo for permissions
                self._run_ssh_cmd(ssh_port, f"sudo mkdir -p {target}")
                self._run_ssh_cmd(ssh_port, f"sudo chown ga:ga {target}")

                # Copy contents
                print(f"[QemuApptainer] Copying {source_path} -> {target}")
                if source_path.is_dir():
                    # Copy directory contents
                    self._scp_to_vm(ssh_port, f"{source_path}/.", target)
                else:
                    self._scp_to_vm(ssh_port, str(source_path), target)

    def _sftp_copy_to_windows(self, source_path: Path, win_target: str) -> bool:
        """Copy files/directories to Windows VM via SFTP."""
        try:
            import paramiko

            # Create SSH connection directly for SFTP
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect("localhost", port=self.ssh_port, username=self._ssh_user,
                       password=self._ssh_password, timeout=30, look_for_keys=False)

            sftp = ssh.open_sftp()

            # Convert Windows path to SFTP path format (forward slashes, no drive letter prefix for SFTP)
            sftp_target = win_target.replace("\\", "/")
            if sftp_target.startswith("C:"):
                sftp_target = sftp_target[2:]  # Remove "C:" prefix for SFTP

            if source_path.is_dir():
                # Copy directory recursively
                for item in source_path.rglob("*"):
                    if item.is_file():
                        rel_path = item.relative_to(source_path)
                        remote_path = sftp_target + "/" + str(rel_path).replace("\\", "/")

                        # Create parent directories
                        remote_dir = "/".join(remote_path.split("/")[:-1])
                        try:
                            sftp.stat(remote_dir)
                        except FileNotFoundError:
                            # Create directory hierarchy
                            parts = remote_dir.split("/")
                            for i in range(1, len(parts) + 1):
                                partial_path = "/".join(parts[:i])
                                if partial_path:
                                    try:
                                        sftp.stat(partial_path)
                                    except FileNotFoundError:
                                        try:
                                            sftp.mkdir(partial_path)
                                        except:
                                            pass

                        # Copy file
                        sftp.put(str(item), remote_path)
            else:
                # Single file
                sftp.put(str(source_path), sftp_target)

            sftp.close()
            ssh.close()
            return True

        except Exception as e:
            print(f"[QemuApptainer] SFTP copy error: {e}")
            return False
    
    def _dump_log(self):
        log = self._work_dir / "qemu.log"
        if log.exists():
            print(f"[QemuApptainer] === LOG ===\n{log.read_text()[-2000:]}")
    
    def stop(self) -> None:
        """Stop VM."""
        if not self._running and not self._process:
            return
        
        print(f"[QemuApptainer] Stopping {self.instance_name}")
        self._stop_event.set()

        # Close pyautogui client (Windows)
        if self._pyautogui_client:
            try:
                self._pyautogui_client.close()
            except:
                pass
            self._pyautogui_client = None

        if self._vnc_pool:
            self._vnc_pool.close()
            self._vnc_pool = None

        if self._fast_input_client:
            self._fast_input_client.close()
            self._fast_input_client = None

        if self._qmp_client:
            self._qmp_client.close()
            self._qmp_client = None

        if self._dbus_display:
            self._dbus_display.stop()
            self._dbus_display = None
        
        if self._process and self._process.poll() is None:
            try:
                self._process.stdin.write(b"quit\n")
                self._process.stdin.flush()
                self._process.wait(timeout=5)
            except:
                pass
            if self._process.poll() is None:
                try:
                    os.killpg(os.getpgid(self._process.pid), signal.SIGKILL)
                except:
                    self._process.kill()
        
        self._process = None
        self._running = False
        
        if self._work_dir and self._work_dir.exists():
            shutil.rmtree(self._work_dir, ignore_errors=True)
        if self._fast_io_dir and self._fast_io_dir.exists():
            shutil.rmtree(self._fast_io_dir, ignore_errors=True)
        self._fast_io_dir = None
        self._fast_io_container_dir = None
    
    # === Actions via pyautogui (SSH) ===

    # Key name normalization map (matches Docker runner)
    _KEY_NAME_MAP = {
        "ctrl": "ctrl",
        "control": "ctrl",
        "alt": "alt",
        "shift": "shift",
        "super": "win",
        "win": "win",
        "meta": "win",
        "command": "win",
        "cmd": "win",
        "enter": "enter",
        "return": "enter",
        "esc": "escape",
        "escape": "escape",
        "backspace": "backspace",
        "delete": "delete",
        "del": "delete",
        "tab": "tab",
        "space": "space",
        "up": "up",
        "down": "down",
        "left": "left",
        "right": "right",
        "home": "home",
        "end": "end",
        "pageup": "pageup",
        "pagedown": "pagedown",
        "pgup": "pageup",
        "pgdn": "pagedown",
        "insert": "insert",
        "ins": "insert",
        "f1": "f1", "f2": "f2", "f3": "f3", "f4": "f4",
        "f5": "f5", "f6": "f6", "f7": "f7", "f8": "f8",
        "f9": "f9", "f10": "f10", "f11": "f11", "f12": "f12",
    }

    _QMP_POINTER_MAX = 0x7FFF
    _QMP_TEXT_CHUNK_EVENTS = 256
    _QMP_DRAG_STEPS = 8
    # Experimental QMP keyboard pacing defaults. These are temporary margins
    # around QEMU's asynchronous send-key release scheduling, not a correctness
    # contract for production input.
    _QMP_EXPERIMENTAL_KEY_HOLD_MS_DEFAULT = 5
    _QMP_EXPERIMENTAL_KEY_GAP_MS_DEFAULT = 10

    _QMP_KEY_NAME_MAP = {
        "ctrl": "ctrl",
        "control": "ctrl",
        "alt": "alt",
        "shift": "shift",
        "super": "meta_l",
        "win": "meta_l",
        "meta": "meta_l",
        "command": "meta_l",
        "cmd": "meta_l",
        "enter": "ret",
        "return": "ret",
        "esc": "esc",
        "escape": "esc",
        "backspace": "backspace",
        "delete": "delete",
        "del": "delete",
        "tab": "tab",
        "space": "spc",
        "up": "up",
        "down": "down",
        "left": "left",
        "right": "right",
        "home": "home",
        "end": "end",
        "pageup": "pgup",
        "pagedown": "pgdn",
        "pgup": "pgup",
        "pgdn": "pgdn",
        "insert": "insert",
        "ins": "insert",
        "plus": "equal",
        "minus": "minus",
        "comma": "comma",
        "period": "dot",
        "dot": "dot",
        "slash": "slash",
        "backslash": "backslash",
        "semicolon": "semicolon",
        "apostrophe": "apostrophe",
        "quote": "apostrophe",
        "grave": "grave_accent",
        "backtick": "grave_accent",
        "f1": "f1", "f2": "f2", "f3": "f3", "f4": "f4",
        "f5": "f5", "f6": "f6", "f7": "f7", "f8": "f8",
        "f9": "f9", "f10": "f10", "f11": "f11", "f12": "f12",
    }

    _QMP_CHAR_KEY_MAP = {
        " ": ("spc", False),
        "\n": ("ret", False),
        "\r": ("ret", False),
        "\t": ("tab", False),
        "`": ("grave_accent", False),
        "~": ("grave_accent", True),
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

    def _build_keyboard_script(self, keyboard: Dict[str, Any]) -> str:
        lines = [_KEYBOARD_XLIB_PREAMBLE]
        settle_ms = os.environ.get("GYM_ANYTHING_KBD_SETTLE_MS")
        if settle_ms:
            lines.append(f"_SETTLE = {float(settle_ms) / 1000.0!r}")
        if "text" in keyboard:
            b64 = base64.b64encode(str(keyboard["text"]).encode("utf-8")).decode("ascii")
            lines.append(f"type_text(base64.b64decode('{b64}').decode())")
        if "keys" in keyboard:
            keys = keyboard["keys"]
            keys = [keys] if isinstance(keys, str) else list(keys)
            lines.append(f"chord({keys!r})")
        if "keys_down" in keyboard:
            keys = keyboard["keys_down"]
            keys = [keys] if isinstance(keys, str) else list(keys)
            lines.append(f"hold({keys!r}, True)")
        if "keys_up" in keyboard:
            keys = keyboard["keys_up"]
            keys = [keys] if isinstance(keys, str) else list(keys)
            lines.append(f"hold({keys!r}, False)")
        return "\n".join(lines)

    def _normalize_key_name(self, key: str) -> str:
        """Normalize key name for pyautogui compatibility."""
        return self._KEY_NAME_MAP.get(key.lower(), key.lower())

    def _normalize_qmp_key_name(self, key: str) -> str:
        normalized = self._QMP_KEY_NAME_MAP.get(key.lower(), key.lower())
        if len(normalized) == 1:
            return normalized.lower()
        return normalized

    @staticmethod
    def _read_nonnegative_int_env(name: str, default: int) -> int:
        raw = os.environ.get(name)
        if raw is None or raw.strip() == "":
            return default
        try:
            value = int(raw)
        except ValueError as exc:
            raise RuntimeError(f"{name} must be an integer number of milliseconds, got {raw!r}") from exc
        if value < 0:
            raise RuntimeError(f"{name} must be >= 0 milliseconds, got {value}")
        return value

    def _qmp_experimental_key_hold_ms(self) -> int:
        return self._read_nonnegative_int_env(
            "GYM_ANYTHING_QEMU_QMP_KEY_HOLD_MS",
            self._QMP_EXPERIMENTAL_KEY_HOLD_MS_DEFAULT,
        )

    def _qmp_experimental_key_gap_seconds(self) -> float:
        gap_ms = self._read_nonnegative_int_env(
            "GYM_ANYTHING_QEMU_QMP_KEY_GAP_MS",
            self._QMP_EXPERIMENTAL_KEY_GAP_MS_DEFAULT,
        )
        return gap_ms / 1000.0

    def _build_pyautogui_script(self, commands: List[str]) -> str:
        """Build a pyautogui script from a list of commands."""
        script_lines = [
            "import pyautogui",
            "import time",
            "pyautogui.FAILSAFE = False",
            "pyautogui.PAUSE = 0.02",
        ]
        script_lines.extend(commands)
        return "; ".join(script_lines)

    def _run_pyautogui(self, commands: List[str], timeout: int = 60) -> None:
        """Execute pyautogui commands via SSH.

        Linux: Uses DISPLAY=:1 with X authentication disabled (via xhost +local:).
        Windows: No DISPLAY needed, uses python instead of python3.
        """
        if not self.ssh_port:
            return
        script = self._build_pyautogui_script(commands)
        self._run_guest_python(script, timeout=timeout)

    def _run_guest_python(self, script: str, timeout: int = 60) -> None:
        """Run a python script in the guest, transported base64-encoded so the
        guest shell never interprets its contents."""
        if not self.ssh_port:
            return
        encoded = base64.b64encode(script.encode("utf-8")).decode("ascii")
        bootstrap = f"import base64;exec(base64.b64decode('{encoded}').decode())"
        if self.is_windows:
            cmd = f'python -c "{bootstrap}"'
        else:
            cmd = f'DISPLAY=:1 python3 -c "{bootstrap}"'
        self._ssh_command(cmd, timeout=timeout)

    def _qmp_key_event(self, qcode: str, down: bool) -> Dict[str, Any]:
        return {
            "type": "key",
            "data": {
                "down": down,
                "key": {"type": "qcode", "data": qcode},
            },
        }

    def _qmp_button_event(self, button: str, down: bool) -> Dict[str, Any]:
        return {
            "type": "btn",
            "data": {"down": down, "button": button},
        }

    def _qmp_abs_event(self, axis: str, value: int) -> Dict[str, Any]:
        return {
            "type": "abs",
            "data": {"axis": axis, "value": value},
        }

    def _qmp_pointer_value(self, coordinate: int, axis_size: int) -> int:
        if axis_size <= 1:
            return 0
        clipped = max(0, min(int(coordinate), axis_size - 1))
        return round(clipped * self._QMP_POINTER_MAX / (axis_size - 1))

    def _qmp_move_events(self, x: int, y: int) -> List[Dict[str, Any]]:
        width, height = self.resolution
        return [
            self._qmp_abs_event("x", self._qmp_pointer_value(x, width)),
            self._qmp_abs_event("y", self._qmp_pointer_value(y, height)),
        ]

    def _qmp_key_tap_events(self, qcode: str) -> List[Dict[str, Any]]:
        return [
            self._qmp_key_event(qcode, True),
            self._qmp_key_event(qcode, False),
        ]

    def _qmp_key_combo_events(self, keys: List[str]) -> List[Dict[str, Any]]:
        qcodes = [self._normalize_qmp_key_name(str(key)) for key in keys]
        events: List[Dict[str, Any]] = []
        for qcode in qcodes:
            events.append(self._qmp_key_event(qcode, True))
        for qcode in reversed(qcodes):
            events.append(self._qmp_key_event(qcode, False))
        return events

    def _qmp_text_event_groups(self, text: str) -> List[List[Dict[str, Any]]]:
        groups: List[List[Dict[str, Any]]] = []
        for char in text:
            if "a" <= char <= "z":
                qcode, shifted = char, False
            elif "A" <= char <= "Z":
                qcode, shifted = char.lower(), True
            else:
                mapped = self._QMP_CHAR_KEY_MAP.get(char)
                if mapped is None:
                    raise ValueError(f"QMP fast input cannot type character {char!r}")
                qcode, shifted = mapped
            events: List[Dict[str, Any]] = []
            if shifted:
                events.append(self._qmp_key_event("shift", True))
            events.extend(self._qmp_key_tap_events(qcode))
            if shifted:
                events.append(self._qmp_key_event("shift", False))
            groups.append(events)
        return groups

    def _qmp_text_key_groups(self, text: str) -> List[List[str]]:
        groups: List[List[str]] = []
        for char in text:
            if "a" <= char <= "z":
                qcode, shifted = char, False
            elif "A" <= char <= "Z":
                qcode, shifted = char.lower(), True
            else:
                mapped = self._QMP_CHAR_KEY_MAP.get(char)
                if mapped is None:
                    raise ValueError(f"QMP fast input cannot type character {char!r}")
                qcode, shifted = mapped
            groups.append(["shift", qcode] if shifted else [qcode])
        return groups

    def _qmp_text_events(self, text: str) -> List[Dict[str, Any]]:
        events: List[Dict[str, Any]] = []
        for group in self._qmp_text_event_groups(text):
            events.extend(group)
        return events

    def _qmp_send_key_combo(self, qcodes: List[str]) -> None:
        if not qcodes:
            return
        client = self._get_qmp_client()
        client.execute(
            "send-key",
            {
                "keys": [{"type": "qcode", "data": qcode} for qcode in qcodes],
                "hold-time": self._qmp_experimental_key_hold_ms(),
            },
        )
        time.sleep(self._qmp_experimental_key_gap_seconds())


    def _qmp_send_input_events(self, events: List[Dict[str, Any]]) -> None:
        if not events:
            return
        client = self._get_qmp_client()
        for index in range(0, len(events), self._QMP_TEXT_CHUNK_EVENTS):
            client.execute("input-send-event", {"events": events[index:index + self._QMP_TEXT_CHUNK_EVENTS]})

    def _inject_action_via_qmp(self, action: Dict[str, Any]) -> None:
        events: List[Dict[str, Any]] = []

        def flush_events() -> None:
            nonlocal events
            if events:
                self._qmp_send_input_events(events)
                events = []

        def send_pointer_move(x: int, y: int) -> None:
            events.extend(self._qmp_move_events(int(x), int(y)))
            flush_events()
            self._await_pointer({"x": int(x), "y": int(y)})

        def send_button_tap(button: str) -> None:
            events.append(self._qmp_button_event(button, True))
            flush_events()
            self._await_pointer({"mask_set": _X_BUTTON_MASK.get(button, 0)})
            events.append(self._qmp_button_event(button, False))
            flush_events()
            self._await_pointer({"mask_clear": _X_BUTTON_MASK.get(button, 0)})

        mouse = action.get("mouse")
        if mouse:
            if "move" in mouse:
                x, y = mouse["move"]
                send_pointer_move(int(x), int(y))
            if "left_click" in mouse:
                x, y = mouse["left_click"]
                send_pointer_move(int(x), int(y))
                send_button_tap("left")
            if "right_click" in mouse:
                x, y = mouse["right_click"]
                send_pointer_move(int(x), int(y))
                send_button_tap("right")
            if "middle_click" in mouse:
                x, y = mouse["middle_click"]
                send_pointer_move(int(x), int(y))
                send_button_tap("middle")
            if "double_click" in mouse:
                x, y = mouse["double_click"]
                send_pointer_move(int(x), int(y))
                for _ in range(2):
                    send_button_tap("left")
            if "triple_click" in mouse:
                x, y = mouse["triple_click"]
                send_pointer_move(int(x), int(y))
                for _ in range(3):
                    send_button_tap("left")
            if "left_click_drag" in mouse:
                (x1, y1), (x2, y2) = mouse["left_click_drag"]
                send_pointer_move(int(x1), int(y1))
                events.append(self._qmp_button_event("left", True))
                flush_events()
                self._await_pointer({"mask_set": _X_BUTTON_MASK["left"],
                                     "x": int(x1), "y": int(y1)})
                for step in range(1, self._QMP_DRAG_STEPS + 1):
                    x = int(x1 + (x2 - x1) * step / self._QMP_DRAG_STEPS)
                    y = int(y1 + (y2 - y1) * step / self._QMP_DRAG_STEPS)
                    # Acked one waypoint at a time. Sent as one batch the
                    # guest latches only the last coordinate, which is how a
                    # drag arrived as a press at its own endpoint.
                    send_pointer_move(x, y)
                events.append(self._qmp_button_event("left", False))
                flush_events()
                self._await_pointer({"mask_clear": _X_BUTTON_MASK["left"]})
            if "right_click_drag" in mouse:
                (x1, y1), (x2, y2) = mouse["right_click_drag"]
                send_pointer_move(int(x1), int(y1))
                events.append(self._qmp_button_event("right", True))
                flush_events()
                self._await_pointer({"mask_set": _X_BUTTON_MASK["right"],
                                     "x": int(x1), "y": int(y1)})
                for step in range(1, self._QMP_DRAG_STEPS + 1):
                    x = int(x1 + (x2 - x1) * step / self._QMP_DRAG_STEPS)
                    y = int(y1 + (y2 - y1) * step / self._QMP_DRAG_STEPS)
                    # Acked one waypoint at a time. Sent as one batch the
                    # guest latches only the last coordinate, which is how a
                    # drag arrived as a press at its own endpoint.
                    send_pointer_move(x, y)
                events.append(self._qmp_button_event("right", False))
                flush_events()
                self._await_pointer({"mask_clear": _X_BUTTON_MASK["right"]})
            buttons = mouse.get("buttons", {})
            for name in ("left", "right", "middle"):
                for suffix, down in (("_down", True), ("_up", False)):
                    if not buttons.get(name + suffix):
                        continue
                    events.append(self._qmp_button_event(name, down))
                    flush_events()
                    key = "mask_set" if down else "mask_clear"
                    self._await_pointer({key: _X_BUTTON_MASK[name]})
            if "scroll" in mouse:
                dy = int(mouse["scroll"])
                button = "wheel-down" if dy > 0 else "wheel-up"
                # One input-send-event per tick, which is what stops the guest
                # coalescing them (25 requested arrived as 24 when all the
                # events went in a single command). Deliberately NOT acked
                # like a real button: QEMU turns a wheel btn into REL_WHEEL,
                # so the guest never holds a wheel button and XQueryPointer's
                # mask can never show one. Waiting for that state is waiting
                # for something that cannot happen.
                for _ in range(abs(dy)):
                    events.append(self._qmp_button_event(button, True))
                    flush_events()
                    events.append(self._qmp_button_event(button, False))
                    flush_events()

        keyboard = action.get("keyboard")
        if keyboard:
            if "text" in keyboard:
                flush_events()
                for group in self._qmp_text_key_groups(str(keyboard["text"])):
                    self._qmp_send_key_combo(group)
            if "keys" in keyboard:
                keys = keyboard["keys"]
                if isinstance(keys, str):
                    keys = [keys]
                qcodes = [self._normalize_qmp_key_name(str(key)) for key in keys]
                flush_events()
                self._qmp_send_key_combo(qcodes)
            # keys_down / keys_up hold a modifier across the pointer action
            # between them. send-key always taps, so the hold has to go
            # through input-send-event as separate down and up events.
            if "keys_down" in keyboard:
                flush_events()
                for qcode in self._qmp_key_names(keyboard["keys_down"]):
                    events.append(self._qmp_key_event(qcode, True))
                flush_events()
            if "keys_up" in keyboard:
                flush_events()
                for qcode in self._qmp_key_names(keyboard["keys_up"]):
                    events.append(self._qmp_key_event(qcode, False))
                flush_events()

        flush_events()

    def acks_input_delivery(self) -> bool:
        # Pointer events are confirmed against the guest's X server, and
        # keyboard requests against its keymap, both through the in-guest
        # agent. Without an agent provisioned for this instance injection is
        # still fire-and-forget, and callers must keep pacing themselves.
        return bool(
            self._fast_io
            and self._fast_uinput_keyboard_enabled()
            and getattr(self, "_fast_input_host_port", None)
        )

    def _await_pointer(self, expect: Dict[str, Any]) -> None:
        """Barrier: return once the guest's X server shows the state we sent.

        QMP's input-send-event returns when QEMU has QUEUED events into the
        virtio device, not when the guest consumed them, so without this the
        next action races the previous one: a keyboard release injected
        in-guest overtakes a queued click (the modifier arrives dropped), a
        second click lands before the first is seen (repeats collapse), and a
        batch of moves latches only its last coordinate (a drag presses at its
        own endpoint). The wait is on observed state, never on a clock; the
        timeout exists to fail loudly, not to pace.
        """
        if not self.acks_input_delivery():
            return
        client = self._get_fast_input_client()
        response = client.request({"op": "await_pointer", "expect": expect},
                                  allow_error=True)
        if not response.get("ok"):
            raise RuntimeError(
                f"fast input agent error: {response.get('error', response)}")
        if not response.get("matched"):
            raise RuntimeError(
                f"pointer event never reached the guest X server: wanted "
                f"{expect}, saw x={response.get('x')} y={response.get('y')} "
                f"mask={response.get('mask')}")

    def _qmp_key_names(self, keys: Any) -> List[str]:
        if isinstance(keys, str):
            keys = [keys]
        return [self._normalize_qmp_key_name(str(key)) for key in keys]

    def _inject_keyboard_via_fast_input_agent(self, keyboard: Dict[str, Any]) -> None:
        client = self._get_fast_input_client()
        response = client.request({"op": "keyboard", "keyboard": keyboard},
                                  allow_error=True)
        if response.get("ok"):
            return
        if response.get("error") in ("unsupported_text", "unsupported_keys"):
            # uinput can only reach what the guest layout maps. Text outside
            # it (accents, emoji) and key names outside it (numpad, menu,
            # lock keys) go through the guest's Xlib typer, which remaps spare
            # keycodes and resolves any keysym. Slow path, entered only for
            # input the fast device provably cannot express, so ordinary
            # typing and chords keep the fast path untouched.
            self._run_guest_python(self._build_keyboard_script(keyboard))
            return
        raise RuntimeError(f"fast input agent error: {response.get('error', response)}")

    def _inject_action_via_fast_io(self, action: Dict[str, Any]) -> None:
        mouse = action.get("mouse")
        if mouse:
            self._inject_action_via_qmp({"mouse": mouse})

        keyboard = action.get("keyboard")
        if keyboard:
            if self._fast_uinput_keyboard_enabled():
                self._inject_keyboard_via_fast_input_agent(keyboard)
            elif self._fast_keyboard_backend() == "qmp-experimental":
                self._inject_action_via_qmp({"keyboard": keyboard})
            else:
                self._validate_fast_keyboard_backend()

    def inject_action(self, action: Dict[str, Any]) -> None:
        """Inject keyboard/mouse actions via pyautogui or ADB.

        On Windows: Uses the pyautogui TCP server running in the desktop session.
        On Android: Uses ADB input commands.
        On Linux: Uses pyautogui over SSH with DISPLAY=:1.
        """
        if self._fast_io and not self.is_android:
            self._inject_action_via_fast_io(action)
            return

        # Windows: Use the pyautogui client (TCP server protocol)
        if self.is_windows and self._pyautogui_client:
            self._inject_action_via_client(action)
            return

        # Android: Use ADB input commands
        if self.is_android:
            self._inject_action_via_adb(action)
            return

        # Linux: Use pyautogui via SSH
        commands: List[str] = []

        mouse = action.get("mouse")
        if mouse:
            if "left_click" in mouse:
                x, y = mouse["left_click"]
                commands.append(f"pyautogui.click({int(x)}, {int(y)}, button='left')")
            if "right_click" in mouse:
                x, y = mouse["right_click"]
                commands.append(f"pyautogui.click({int(x)}, {int(y)}, button='right')")
            if "middle_click" in mouse:
                x, y = mouse["middle_click"]
                commands.append(f"pyautogui.click({int(x)}, {int(y)}, button='middle')")
            if "double_click" in mouse:
                x, y = mouse["double_click"]
                commands.append(f"pyautogui.doubleClick({int(x)}, {int(y)})")
            if "triple_click" in mouse:
                x, y = mouse["triple_click"]
                commands.append(f"pyautogui.tripleClick({int(x)}, {int(y)})")
            if "left_click_drag" in mouse:
                (x1, y1), (x2, y2) = mouse["left_click_drag"]
                commands.append(f"pyautogui.moveTo({int(x1)}, {int(y1)})")
                commands.append(f"pyautogui.drag({int(x2 - x1)}, {int(y2 - y1)}, duration=0.5, button='left')")
            if "right_click_drag" in mouse:
                (x1, y1), (x2, y2) = mouse["right_click_drag"]
                commands.append(f"pyautogui.moveTo({int(x1)}, {int(y1)})")
                commands.append(f"pyautogui.drag({int(x2 - x1)}, {int(y2 - y1)}, duration=0.5, button='right')")
            if "move" in mouse:
                x, y = mouse["move"]
                commands.append(f"pyautogui.moveTo({int(x)}, {int(y)})")
            # Handle button states (left_down, left_up, right_down)
            buttons = mouse.get("buttons", {})
            if buttons.get("left_down"):
                commands.append("pyautogui.mouseDown(button='left')")
            if buttons.get("left_up"):
                commands.append("pyautogui.mouseUp(button='left')")
            if buttons.get("right_down"):
                commands.append("pyautogui.mouseDown(button='right')")
            if buttons.get("right_up"):
                commands.append("pyautogui.mouseUp(button='right')")
            if "scroll" in mouse:
                dy = int(mouse["scroll"])
                # pyautogui.scroll: positive = up, negative = down
                # Our convention: positive = down, so invert
                commands.append(f"pyautogui.scroll({-dy})")

        # Mouse via pyautogui; run it before keyboard so within-action order
        # is preserved.
        if commands:
            print(f"[QemuApptainer] Executing pyautogui commands: {commands}")
            self._run_pyautogui(commands)

        # Keyboard via direct Xlib in the guest (race-free batch keycode
        # remap): types Unicode and `<` correctly and presses numpad/menu
        # keys, without xdotool's per-character remap race.
        keyboard = action.get("keyboard")
        if keyboard:
            self._run_guest_python(self._build_keyboard_script(keyboard))

    def _inject_action_via_client(self, action: Dict[str, Any]) -> None:
        """Inject actions using the PyAutoGUI TCP client (Windows)."""
        if not self._pyautogui_client:
            return

        try:
            mouse = action.get("mouse")
            if mouse:
                if "left_click" in mouse:
                    x, y = mouse["left_click"]
                    self._pyautogui_client.click(int(x), int(y), button="left")
                if "right_click" in mouse:
                    x, y = mouse["right_click"]
                    self._pyautogui_client.click(int(x), int(y), button="right")
                if "middle_click" in mouse:
                    x, y = mouse["middle_click"]
                    self._pyautogui_client.click(int(x), int(y), button="middle")
                if "double_click" in mouse:
                    x, y = mouse["double_click"]
                    self._pyautogui_client.double_click(int(x), int(y))
                if "triple_click" in mouse:
                    x, y = mouse["triple_click"]
                    self._pyautogui_client.click(int(x), int(y), clicks=3)
                if "left_click_drag" in mouse:
                    (x1, y1), (x2, y2) = mouse["left_click_drag"]
                    self._pyautogui_client.move(int(x1), int(y1))
                    self._pyautogui_client.drag(int(x2 - x1), int(y2 - y1), duration=0.5, button="left")
                if "right_click_drag" in mouse:
                    (x1, y1), (x2, y2) = mouse["right_click_drag"]
                    self._pyautogui_client.move(int(x1), int(y1))
                    self._pyautogui_client.drag(int(x2 - x1), int(y2 - y1), duration=0.5, button="right")
                if "move" in mouse:
                    x, y = mouse["move"]
                    self._pyautogui_client.move(int(x), int(y))
                # Handle button states
                buttons = mouse.get("buttons", {})
                if buttons.get("left_down"):
                    self._pyautogui_client.key_down("left")  # mouseDown not directly supported, use workaround
                if buttons.get("left_up"):
                    self._pyautogui_client.key_up("left")
                if "scroll" in mouse:
                    dy = int(mouse["scroll"])
                    # Our convention: positive = down, so invert
                    self._pyautogui_client.scroll(-dy)

            keyboard = action.get("keyboard")
            if keyboard:
                if "text" in keyboard:
                    text = keyboard["text"]
                    # Use slower interval (0.08s) to prevent character drops on Windows 11
                    self._pyautogui_client.write(text, interval=0.08)
                if "keys" in keyboard:
                    keys = keyboard["keys"]
                    if isinstance(keys, str):
                        keys = [keys]
                    # Normalize key names
                    keys_norm = [self._normalize_key_name(k) for k in keys]
                    self._pyautogui_client.hotkey(*keys_norm)
                # keys_down / keys_up support modifier-held clicks and hold_key.
                if "keys_down" in keyboard:
                    keys = keyboard["keys_down"]
                    if isinstance(keys, str):
                        keys = [keys]
                    for k in keys:
                        self._pyautogui_client.key_down(self._normalize_key_name(k))
                if "keys_up" in keyboard:
                    keys = keyboard["keys_up"]
                    if isinstance(keys, str):
                        keys = [keys]
                    for k in keys:
                        self._pyautogui_client.key_up(self._normalize_key_name(k))

        except PyAutoGUIClientError as e:
            print(f"[QemuApptainer] PyAutoGUI client error: {e}")

    def _inject_action_via_adb(self, action: Dict[str, Any]) -> None:
        """Inject actions using ADB input commands (Android)."""
        mouse = action.get("mouse")
        if mouse:
            if "left_click" in mouse:
                x, y = mouse["left_click"]
                self._adb_command(["shell", "input", "tap", str(int(x)), str(int(y))])
            if "double_click" in mouse:
                x, y = mouse["double_click"]
                # Double tap for double click
                self._adb_command(["shell", "input", "tap", str(int(x)), str(int(y))])
                time.sleep(0.1)
                self._adb_command(["shell", "input", "tap", str(int(x)), str(int(y))])
            if "left_click_drag" in mouse:
                (x1, y1), (x2, y2) = mouse["left_click_drag"]
                # ADB swipe: input swipe x1 y1 x2 y2 [duration_ms]
                self._adb_command(["shell", "input", "swipe",
                                   str(int(x1)), str(int(y1)),
                                   str(int(x2)), str(int(y2)), "500"])
            if "move" in mouse:
                # Android doesn't have a direct mouse move, but we can use swipe with same start/end
                x, y = mouse["move"]
                # No-op for Android - just track position if needed
                pass
            if "scroll" in mouse:
                dy = int(mouse["scroll"])
                # ADB scroll: use swipe for scrolling
                # Positive dy = scroll down (swipe up)
                center_x = self.resolution[0] // 2
                center_y = self.resolution[1] // 2
                scroll_amount = dy * 100  # Scale the scroll
                self._adb_command(["shell", "input", "swipe",
                                   str(center_x), str(center_y),
                                   str(center_x), str(center_y - scroll_amount), "300"])

        keyboard = action.get("keyboard")
        if keyboard:
            if "text" in keyboard:
                text = keyboard["text"]
                # ADB text input - escape special characters
                # Note: ADB input text has limitations with special chars
                escaped = text.replace(" ", "%s").replace("'", "\\'").replace('"', '\\"')
                self._adb_command(["shell", "input", "text", escaped])

            if "keys" in keyboard:
                keys = keyboard["keys"]
                if isinstance(keys, str):
                    keys = [keys]

                # Map key names to Android keycodes
                keycode_map = {
                    "enter": "KEYCODE_ENTER",
                    "return": "KEYCODE_ENTER",
                    "backspace": "KEYCODE_DEL",
                    "delete": "KEYCODE_FORWARD_DEL",
                    "tab": "KEYCODE_TAB",
                    "escape": "KEYCODE_ESCAPE",
                    "esc": "KEYCODE_ESCAPE",
                    "home": "KEYCODE_HOME",
                    "back": "KEYCODE_BACK",
                    "menu": "KEYCODE_MENU",
                    "up": "KEYCODE_DPAD_UP",
                    "down": "KEYCODE_DPAD_DOWN",
                    "left": "KEYCODE_DPAD_LEFT",
                    "right": "KEYCODE_DPAD_RIGHT",
                    "space": "KEYCODE_SPACE",
                    "volumeup": "KEYCODE_VOLUME_UP",
                    "volumedown": "KEYCODE_VOLUME_DOWN",
                    "power": "KEYCODE_POWER",
                }

                for key in keys:
                    key_lower = key.lower()
                    if key_lower in keycode_map:
                        self._adb_command(["shell", "input", "keyevent", keycode_map[key_lower]])
                    elif len(key) == 1:
                        # Single character - send as text
                        self._adb_command(["shell", "input", "text", key])
                    else:
                        # Try as keycode directly
                        self._adb_command(["shell", "input", "keyevent", key.upper()])

    # === Observations ===
    
    def capture_observation(self) -> Dict[str, Any]:
        obs = {}
        screen_spec = next((o for o in self.spec.observation if o.type == "rgb_screen"), None)
        if screen_spec:
            obs["screen"] = {"format": "rgb", "fps": screen_spec.fps, "resolution": self.resolution}
        return obs

    @staticmethod
    def _ppm_token(data: bytes, index: int) -> tuple[bytes, int]:
        while index < len(data):
            byte = data[index]
            if byte == 35:  # '#'
                index = data.find(b"\n", index)
                if index < 0:
                    raise ValueError("unterminated PPM comment")
                index += 1
                continue
            if byte not in b" \t\r\n":
                break
            index += 1
        start = index
        while index < len(data) and data[index] not in b" \t\r\n":
            index += 1
        return data[start:index], index

    @classmethod
    def _load_ppm_rgb_fast(cls, path: Path):
        from PIL import Image

        data = path.read_bytes()
        magic, index = cls._ppm_token(data, 0)
        if magic != b"P6":
            raise ValueError(f"unsupported PPM magic: {magic!r}")
        width_token, index = cls._ppm_token(data, index)
        height_token, index = cls._ppm_token(data, index)
        maxval_token, index = cls._ppm_token(data, index)
        if maxval_token != b"255":
            raise ValueError(f"unsupported PPM maxval: {maxval_token!r}")
        if data[index:index + 2] == b"\r\n":
            index += 2
        elif index < len(data) and data[index] in b" \t\r\n":
            index += 1
        width = int(width_token)
        height = int(height_token)
        expected = width * height * 3
        payload = data[index:index + expected]
        if len(payload) != expected:
            raise ValueError(f"truncated PPM payload: expected {expected}, got {len(payload)}")
        return Image.frombuffer("RGB", (width, height), payload, "raw", "RGB", 0, 1)

    def _get_qmp_client(self) -> _QMPClient:
        if not self._fast_io:
            raise RuntimeError("QMP screenshot capture requires fast_io=True")
        if self._qmp_socket_path is None:
            raise RuntimeError("QMP socket was not configured for this QEMU instance")
        if self._qmp_client is not None and self._qmp_client.socket_path != self._qmp_socket_path:
            self._qmp_client.close()
            self._qmp_client = None
        if self._qmp_client is None:
            deadline = time.time() + 5
            last_error: Optional[Exception] = None
            while time.time() < deadline:
                try:
                    client = _QMPClient(self._qmp_socket_path, timeout=1.0)
                    client.connect()
                    self._qmp_client = client
                    break
                except Exception as exc:
                    last_error = exc
                    time.sleep(0.05)
            if self._qmp_client is None:
                raise RuntimeError(f"QMP fast I/O connection failed: {last_error}")
        return self._qmp_client

    def _capture_screenshot_image_qmp(self, image_format: str = "ppm", parser: str = "pil"):
        """Capture via QMP screendump and return a loaded PIL Image."""
        host_output_dir = self._fast_io_dir or self._work_dir
        qmp_output_dir = self._fast_io_container_dir or host_output_dir
        if not host_output_dir or not qmp_output_dir:
            raise RuntimeError("QEMU work directory is not initialized")
        from PIL import Image

        image_format = image_format.lower()
        suffix = "png" if image_format == "png" else "ppm"
        filename = f"fast_screenshot_{uuid.uuid4().hex[:8]}.{suffix}"
        host_path = host_output_dir / filename
        qmp_path = qmp_output_dir / filename
        args: Dict[str, Any] = {"filename": str(qmp_path)}
        if image_format != "ppm":
            args["format"] = image_format
        client = self._get_qmp_client()
        client.execute("screendump", args)
        try:
            if image_format == "ppm" and parser == "fast":
                return self._load_ppm_rgb_fast(host_path)
            image = Image.open(host_path)
            image.load()
            return image.convert("RGB")
        finally:
            try:
                host_path.unlink()
            except FileNotFoundError:
                pass

    def _capture_screenshot_image_legacy(self):
        """Capture through the runner's existing screenshot path and return PIL Image."""
        tmp_dir = Path(tempfile.mkdtemp(prefix=f"ga_capture_{self.instance_id}_", dir=str(QEMU_WORK_DIR)))
        try:
            out_path = tmp_dir / "screenshot.png"
            fast_io_enabled = self._fast_io
            self._fast_io = False
            try:
                if not self.capture_screenshot(out_path):
                    raise RuntimeError("screenshot capture failed")
            finally:
                self._fast_io = fast_io_enabled
            from PIL import Image

            image = Image.open(out_path)
            image.load()
            return image.convert("RGB")
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)

    def capture_screenshot_image(self):
        """Capture the display as a PIL Image without guest SSH, ffmpeg, or VNC."""
        if self._fast_io:
            if self._fast_io_backend() == "dbus":
                if self._dbus_display is None:
                    raise RuntimeError("QEMU D-Bus display capture is not initialized")
                return self._dbus_display.capture_image()
            image_format = os.environ.get("GYM_ANYTHING_QEMU_SCREENSHOT_FORMAT", "ppm")
            parser = os.environ.get("GYM_ANYTHING_QEMU_SCREENSHOT_PARSER", "pil")
            return self._capture_screenshot_image_qmp(image_format=image_format, parser=parser)
        return self._capture_screenshot_image_legacy()
    
    def capture_screenshot(self, host_path) -> bool:
        """Capture a screenshot.

        Android: Uses ADB screencap.
        Windows: Uses pyautogui via the TCP server (runs in desktop session).
        Linux: Uses X11/ffmpeg inside the VM (captures mouse pointer).
        Fallback: VNC framebuffer capture.
        """
        host_path = Path(host_path)
        host_path.parent.mkdir(parents=True, exist_ok=True)

        if self._fast_io:
            try:
                img = self.capture_screenshot_image()
                img.save(str(host_path), "PNG")
                return True
            except Exception as e:
                print(f"[QemuApptainer] QMP fast screenshot failed: {e}")
                return False

        # --- Android: Use ADB screencap ---
        if self.is_android:
            try:
                # Use adb exec-out screencap -p to get PNG directly to stdout
                result = self._adb_command(["exec-out", "screencap", "-p"], timeout=30)
                if result.returncode == 0 and result.stdout:
                    with open(host_path, "wb") as f:
                        f.write(result.stdout)
                    return True
                else:
                    print(f"[QemuApptainer] ADB screencap failed: {result.stderr.decode()[:200] if result.stderr else 'empty output'}")
            except Exception as e:
                print(f"[QemuApptainer] ADB screencap exception: {e}")
            # Fall through to VNC fallback

        # --- Windows: Use pyautogui client ---
        if self.is_windows and self._pyautogui_client:
            try:
                img = self._pyautogui_client.screenshot()
                if img:
                    img.save(str(host_path), "PNG")
                    return True
                else:
                    print(f"[QemuApptainer] PyAutoGUI screenshot returned None")
            except PyAutoGUIClientError as e:
                print(f"[QemuApptainer] PyAutoGUI screenshot error: {e}")
            except Exception as e:
                print(f"[QemuApptainer] PyAutoGUI screenshot exception: {e}")
            # Fall through to VNC fallback

        # --- Linux: ffmpeg x11grab inside VM ---
        # NOTE: The VM desktop is expected on DISPLAY=:1 (see _wait_for_desktop()).
        # We run without sudo to avoid X11 auth issues.
        if not self.is_windows:
            try:
                if self.ssh_port:
                    remote_tmp = f"/tmp/ga_screenshot_{uuid.uuid4().hex[:8]}.png"
                    screen_spec = next((o for o in self.spec.observation if o.type == "rgb_screen"), None)
                    size_arg = (
                        f"-video_size {screen_spec.resolution[0]}x{screen_spec.resolution[1]}"
                        if (screen_spec and screen_spec.resolution)
                        else ""
                    )
                    # IMPORTANT: don't use `$DISPLAY` here.
                    # If we do `DISPLAY=:1 ffmpeg ... -i $DISPLAY`, `$DISPLAY` is expanded by the shell
                    # BEFORE running ffmpeg and may be empty, causing ffmpeg to treat the next flag
                    # (e.g. -vframes) as the display name. Pass the display literally instead.
                    display = os.environ.get("GYM_ANYTHING_QEMU_X11_DISPLAY", ":1")
                    ffmpeg_cmd = (
                        f"ffmpeg -nostdin -y -loglevel error -f x11grab -draw_mouse 1 "
                        f"{size_arg} -i {shlex.quote(display)} -vframes 1 {shlex.quote(remote_tmp)}"
                    )
                    # Use bash -lc for consistent PATH/shell behavior inside the VM user session
                    res = self._ssh_command(f"bash -lc {shlex.quote(ffmpeg_cmd)}", timeout=60)
                    if res.returncode == 0:
                        self.copy_from(remote_tmp, str(host_path))
                        # Cleanup remote tmp best-effort
                        self._ssh_command(f"rm -f {shlex.quote(remote_tmp)}", timeout=20)
                        return True
                    else:
                        print(f"[QemuApptainer] ffmpeg screenshot failed: {res.stdout.decode()[:200]}")
            except Exception as e:
                print(f"[QemuApptainer] ffmpeg screenshot exception: {e}")

        print(f"[QemuApptainer] VNC capture fallback")

        # --- Fallback: VNC capture (existing behavior) ---
        if not self._vnc_pool:
            return False
        conn = self._vnc_pool.get_connection()
        if not conn:
            return False
        try:
            return conn.capture_screenshot(save_path=host_path) is not None
        except Exception as e:
            print(f"[QemuApptainer] VNC screenshot error: {e}")
            return False
    
    def capture_audio_raw(self, duration_sec: float, rate: int, channels: int) -> bytes:
        return b""
    
    def capture_ui_tree(self) -> str:
        return ""
    
    # === Exec via SSH ===
    
    def _ssh_command(self, cmd: str, capture: bool = True, timeout: int = 600, use_pty: bool = True) -> subprocess.CompletedProcess:
        """Run SSH command with key-based auth, falling back to password via paramiko.

        Args:
            cmd: Command to execute
            capture: Whether to capture output
            timeout: Command timeout in seconds
            use_pty: Whether to allocate a PTY. Set to False for task init scripts
                     to prevent SIGHUP from killing background processes when the
                     SSH session ends.
        """
        if not self.ssh_port:
            return subprocess.CompletedProcess([], 0, b"", b"")

        # Check if we've already hit too many consecutive SSH failures
        if self._consecutive_ssh_failures >= self._max_consecutive_ssh_failures:
            raise RuntimeError(
                f"VM unresponsive: {self._consecutive_ssh_failures} consecutive SSH failures. Aborting."
            )

        # For Windows, go directly to paramiko with password auth
        if self.is_windows:
            result = self._ssh_with_paramiko(cmd, capture, timeout, use_pty)
            self._track_ssh_result(result)
            return result

        # SSH key path (generated for gym-anything)
        ssh_key = Path.home() / ".ssh" / "ga_qemu_key"

        # Try SSH with key first (if key exists) - Linux only
        if ssh_key.exists():
            full_cmd = [
                "ssh",
                "-i", str(ssh_key),
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "ConnectTimeout=10",
                "-p", str(self.ssh_port),
                "ga@localhost",
                cmd
            ]
            # Only allocate PTY if requested (needed for sudo/su compatibility,
            # but causes SIGHUP to kill background processes when session ends)
            if use_pty:
                full_cmd.insert(1, "-t")
                full_cmd.insert(1, "-t")

            try:
                result = subprocess.run(full_cmd, capture_output=capture, timeout=timeout)
                if result.returncode == 0:
                    self._consecutive_ssh_failures = 0
                    return result
                # Key auth failed, fall through to paramiko
                print(f"[QemuApptainer] SSH key auth failed (code {result.returncode}), trying paramiko with password...")
            except subprocess.TimeoutExpired:
                print(f"[QemuApptainer] SSH command timed out: {cmd[:50]}...")
                self._consecutive_ssh_failures += 1
                if self._consecutive_ssh_failures >= self._max_consecutive_ssh_failures:
                    raise RuntimeError(
                        f"VM unresponsive: {self._consecutive_ssh_failures} consecutive SSH failures. Aborting."
                    )
                return subprocess.CompletedProcess(full_cmd, 1, b"", b"timeout")
            except Exception as e:
                print(f"[QemuApptainer] SSH error: {e}, trying paramiko...")

        # Fallback to paramiko with password
        result = self._ssh_with_paramiko(cmd, capture, timeout, use_pty)
        self._track_ssh_result(result)
        return result

    def _track_ssh_result(self, result: subprocess.CompletedProcess) -> None:
        """Update consecutive SSH failure counter and raise if threshold exceeded."""
        if result.returncode == 0:
            self._consecutive_ssh_failures = 0
        else:
            self._consecutive_ssh_failures += 1
            if self._consecutive_ssh_failures >= self._max_consecutive_ssh_failures:
                raise RuntimeError(
                    f"VM unresponsive: {self._consecutive_ssh_failures} consecutive SSH failures. Aborting."
                )

    def _ssh_with_paramiko(self, cmd: str, capture: bool, timeout: int, use_pty: bool = True) -> subprocess.CompletedProcess:
        """Fallback SSH using Python's paramiko with key or password authentication.

        Connection setup is retried: back-to-back SSH sessions (hooks, exec,
        screenshots, verifier copies) can trip sshd MaxStartups throttling or
        drop the banner, which otherwise surfaces as a silent empty result.
        """
        try:
            import paramiko
        except ImportError:
            print("[QemuApptainer] Warning: paramiko not available, SSH commands may fail")
            return subprocess.CompletedProcess([], 1, b"", b"paramiko not available")

        ssh_key = Path.home() / ".ssh" / "ga_qemu_key"
        last_err = None
        for attempt in range(4):
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            try:
                # For Windows, use password auth directly with configured credentials
                if self.is_windows:
                    client.connect("localhost", port=self.ssh_port, username=self._ssh_user,
                                  password=self._ssh_password, timeout=15, look_for_keys=False)
                else:
                    # Try key-based auth first for Linux
                    try:
                        client.connect("localhost", port=self.ssh_port, username="ga",
                                      key_filename=str(ssh_key), timeout=15, look_for_keys=False)
                    except Exception:
                        # Fallback to password
                        client.connect("localhost", port=self.ssh_port, username=self._ssh_user,
                                      password=self._ssh_password, timeout=15, look_for_keys=False)
            except Exception as e:
                last_err = e
                try:
                    client.close()
                except Exception:
                    pass
                if attempt < 3:
                    print(f"[QemuApptainer] Paramiko connect failed ({e}); retry in {2 * (attempt + 1)}s")
                    time.sleep(2 * (attempt + 1))
                    continue
                print(f"[QemuApptainer] Paramiko error: {e}")
                return subprocess.CompletedProcess([], 1, b"", str(e).encode())

            try:
                # Only request PTY if needed (for sudo/su compatibility)
                # Disable PTY for task init to prevent SIGHUP killing background processes
                stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout, get_pty=use_pty)
                exit_code = stdout.channel.recv_exit_status()
                out = stdout.read()
                err = stderr.read()
                client.close()
                return subprocess.CompletedProcess([], exit_code, out, err)
            except Exception as e:
                try:
                    client.close()
                except Exception:
                    pass
                print(f"[QemuApptainer] Paramiko exec error: {e}")
                return subprocess.CompletedProcess([], 1, b"", str(e).encode())
        return subprocess.CompletedProcess([], 1, b"", str(last_err).encode())
    
    def exec(self, cmd: str, env: Optional[Dict[str, str]] = None, user: Optional[str] = None, use_pty: bool = True, timeout: int = 600) -> int:
        """Execute command via SSH or ADB shell.

        For Linux, commands are wrapped with sudo to match Docker's root execution behavior.
        The ga user has NOPASSWD sudo access configured via cloud-init.
        For Windows, commands run directly (no sudo).

        Args:
            cmd: Command to execute
            env: Environment variables (currently unused in QEMU runner)
            user: User to run as (currently unused, always uses sudo on Linux)
            use_pty: Whether to allocate a PTY. Set to False for task init scripts
                     to prevent SIGHUP from killing background processes.
            timeout: Command timeout in seconds (default 600)
        """
        env = self.merge_exec_env(env)
        # Android: Use ADB shell
        if self.is_android:
            cmd = wrap_posix_command_with_env(cmd, env, export=True)
            result = self._adb_command(["shell", cmd])
            if result.returncode != 0 and result.stderr:
                print(f"[QemuApptainer] exec failed: {result.stderr.decode()[:200]}")
            return result.returncode

        # Windows: Execute directly without sudo
        if self.is_windows:
            cmd = wrap_powershell_command_with_env(cmd, env)
            result = self._ssh_command(cmd, use_pty=use_pty, timeout=timeout)
            if result.returncode != 0 and result.stderr:
                print(f"[QemuApptainer] exec failed: {result.stderr.decode()[:200]}")
            return result.returncode

        # Linux: Wrap with sudo to match Docker's root execution (Docker container runs as root)
        # Use sudo -E to preserve environment variables
        wrapped_cmd = f"sudo -E {wrap_posix_command_with_env(cmd, env)}"
        result = self._ssh_command(wrapped_cmd, use_pty=use_pty, timeout=timeout)
        if result.returncode != 0 and result.stderr:
            print(f"[QemuApptainer] exec failed: {result.stderr.decode()[:200]}")
        return result.returncode

    def exec_capture(self, cmd: str) -> str:
        env = self.default_exec_env()
        # Android: Use ADB shell
        if self.is_android:
            cmd = wrap_posix_command_with_env(cmd, env, export=True)
            result = self._adb_command(["shell", cmd])
            if result.returncode != 0 and result.stderr:
                print(f"[QemuApptainer] exec_capture stderr: {result.stderr.decode()[:200]}")
            return result.stdout.decode() if isinstance(result.stdout, bytes) else result.stdout

        # Windows: Execute directly without sudo
        if self.is_windows:
            cmd = wrap_powershell_command_with_env(cmd, env)
            result = self._ssh_command(cmd)
            if result.returncode != 0 and result.stderr:
                print(f"[QemuApptainer] exec_capture stderr: {result.stderr.decode()[:200]}")
            return result.stdout.decode() if isinstance(result.stdout, bytes) else result.stdout

        # Linux: Wrap with sudo to match Docker's root execution
        wrapped_cmd = f"sudo -E {wrap_posix_command_with_env(cmd, env)}"
        result = self._ssh_command(wrapped_cmd)
        if result.returncode != 0 and result.stderr:
            print(f"[QemuApptainer] exec_capture stderr: {result.stderr.decode()[:200]}")
        return result.stdout.decode() if isinstance(result.stdout, bytes) else result.stdout

    def exec_capture_bytes(self, cmd: str) -> bytes:
        # Android: Use ADB shell
        if self.is_android:
            result = self._adb_command(["shell", cmd])
            return result.stdout if isinstance(result.stdout, bytes) else result.stdout.encode()

        # Windows: Execute directly without sudo
        if self.is_windows:
            result = self._ssh_command(cmd)
            return result.stdout if isinstance(result.stdout, bytes) else result.stdout.encode()

        # Linux: Wrap with sudo to match Docker's root execution
        wrapped_cmd = f"sudo -E {cmd}"
        result = self._ssh_command(wrapped_cmd)
        return result.stdout if isinstance(result.stdout, bytes) else result.stdout.encode()

    def run_reset(self, reset_script: str, seed: Optional[int] = None) -> None:
        if self.is_windows:
            # Windows: Execute PowerShell script directly
            # Convert script path if needed
            win_script = reset_script.replace("/", "\\")
            if win_script.startswith("\\"):
                win_script = "C:" + win_script
            env_vars = {"SEED": str(seed)} if seed is not None else None
            self.exec(f'powershell -ExecutionPolicy Bypass -Command "{win_script}"', env=env_vars)
        else:
            env_vars = {"SEED": str(seed)} if seed is not None else None
            self.exec(f"bash -lc {repr(reset_script)}", env=env_vars)

    def run_task_init(self, init_script: str) -> None:
        # Disable PTY to prevent SIGHUP from killing background processes (like Google Earth)
        # when the SSH session ends. Task init scripts use sudo with NOPASSWD, so no TTY needed.
        if self.is_windows:
            # Windows: Execute PowerShell script directly
            win_script = init_script.replace("/", "\\")
            if win_script.startswith("\\"):
                win_script = "C:" + win_script
            self.exec(f'powershell -ExecutionPolicy Bypass -Command "{win_script}"', use_pty=False)
        else:
            self.exec(f"bash -lc {repr(init_script)}", use_pty=False)
    
    def copy_to(self, host_src: str, container_dst: str) -> None:
        """Copy file/directory from host to VM via SCP/SFTP or ADB push."""
        # Android: Use ADB push
        if self.is_android:
            result = self._adb_command(["push", host_src, container_dst], timeout=120)
            if result.returncode != 0:
                print(f"[QemuApptainer] ADB push failed: {result.stderr.decode()[:200] if result.stderr else 'unknown error'}")
            return

        if not self.ssh_port:
            return

        # Windows: Go directly to SFTP (no SSH key configured)
        if self.is_windows:
            self._sftp_copy_to(host_src, container_dst)
            return

        ssh_key = Path.home() / ".ssh" / "ga_qemu_key"

        # Linux: Try SCP with key first
        if ssh_key.exists():
            cmd = [
                "scp", "-r",
                "-i", str(ssh_key),
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-P", str(self.ssh_port),
                host_src, f"ga@localhost:{container_dst}"
            ]
            result = subprocess.run(cmd, capture_output=True)
            if result.returncode == 0:
                return
            err_msg = result.stderr.decode()[:200] if result.stderr else "unknown error"
            print(f"[QemuApptainer] SCP copy_to failed ({err_msg}), trying SFTP...")

        # Fallback to SFTP via paramiko
        self._sftp_copy_to(host_src, container_dst)

    def _sftp_copy_to(self, host_src: str, container_dst: str) -> None:
        """Copy file/directory to VM using paramiko SFTP with password auth."""
        try:
            client = self._sftp_connect()

            if self.is_windows:
                # Convert Windows path to SFTP format (forward slashes, no drive letter)
                sftp_dst = container_dst.replace("\\", "/")
                if len(sftp_dst) >= 2 and sftp_dst[1] == ':':
                    sftp_dst = sftp_dst[2:]  # Remove "C:" prefix for SFTP
            else:
                sftp_dst = container_dst

            sftp = client.open_sftp()
            src_path = Path(host_src)

            if src_path.is_dir():
                # Recursive directory copy
                self._sftp_put_dir(sftp, src_path, sftp_dst)
            else:
                # Single file copy - use explicit file handle to avoid size mismatch issues
                with open(src_path, 'rb') as local_file:
                    with sftp.file(sftp_dst, 'wb') as remote_file:
                        remote_file.write(local_file.read())

            sftp.close()
            client.close()
        except Exception as e:
            print(f"[QemuApptainer] SFTP copy_to failed: {e}")

    def _sftp_put_dir(self, sftp, local_dir: Path, remote_dir: str) -> None:
        """Recursively copy a directory via SFTP."""
        try:
            sftp.mkdir(remote_dir)
        except:
            pass  # Directory may already exist

        for item in local_dir.iterdir():
            remote_path = f"{remote_dir}/{item.name}"
            if item.is_dir():
                self._sftp_put_dir(sftp, item, remote_path)
            else:
                # Use explicit file handle to avoid size mismatch issues
                with open(item, 'rb') as local_file:
                    with sftp.file(remote_path, 'wb') as remote_file:
                        remote_file.write(local_file.read())

    def copy_from(self, container_src: str, host_dst: str) -> None:
        """Copy file/directory from VM to host via SCP/SFTP or ADB pull."""
        Path(host_dst).parent.mkdir(parents=True, exist_ok=True)

        # Android: Use ADB pull
        if self.is_android:
            result = self._adb_command(["pull", container_src, host_dst], timeout=120)
            if result.returncode != 0:
                err_msg = result.stderr.decode()[:200] if result.stderr else "unknown error"
                print(f"[QemuApptainer] ADB pull failed: {err_msg}")
                if "does not exist" in err_msg or "No such file" in err_msg:
                    raise FileNotFoundError(f"Source not found: {container_src}")
            return

        if not self.ssh_port:
            return

        # Windows: Go directly to SFTP (no SSH key configured)
        if self.is_windows:
            self._sftp_copy_from(container_src, host_dst)
            return

        ssh_key = Path.home() / ".ssh" / "ga_qemu_key"

        # Linux: Try SCP with key first
        if ssh_key.exists():
            cmd = [
                "scp", "-r",
                "-i", str(ssh_key),
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-P", str(self.ssh_port),
                f"ga@localhost:{container_src}", host_dst
            ]
            result = subprocess.run(cmd, capture_output=True)
            if result.returncode == 0:
                return
            print(f"[QemuApptainer] SCP copy_from failed, trying SFTP with password...")

        # Fallback to SFTP via paramiko
        self._sftp_copy_from(container_src, host_dst)

    def _sftp_connect(self):
        """Open an SSH client with retries.

        Rapid successive connections (hook + screenshots + verifier copies at
        episode finalize) can trip sshd MaxStartups throttling, which
        surfaces as 'Error reading SSH protocol banner'. Retry briefly.
        """
        import paramiko
        ssh_key = Path.home() / ".ssh" / "ga_qemu_key"

        last_err = None
        for attempt in range(4):
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            try:
                # Windows: Use configured credentials directly
                if self.is_windows:
                    client.connect("localhost", port=self.ssh_port, username=self._ssh_user,
                                  password=self._ssh_password, timeout=30, look_for_keys=False)
                else:
                    # Linux: Try key first, then password
                    try:
                        client.connect("localhost", port=self.ssh_port, username="ga",
                                      key_filename=str(ssh_key), timeout=10, look_for_keys=False)
                    except Exception:
                        client.connect("localhost", port=self.ssh_port, username="ga",
                                      password="password123", timeout=10, look_for_keys=False)
                return client
            except Exception as e:
                last_err = e
                try:
                    client.close()
                except Exception:
                    pass
                if attempt < 3:
                    print(f"[QemuApptainer] SSH connect failed ({e}); retrying in {2 * (attempt + 1)}s")
                    time.sleep(2 * (attempt + 1))
        raise last_err

    def _sftp_copy_from(self, container_src: str, host_dst: str) -> None:
        """Copy file/directory from VM using paramiko SFTP with password auth."""
        try:
            client = self._sftp_connect()

            sftp = client.open_sftp()

            # Check if source is directory or file
            source_not_found = False
            try:
                sftp.stat(container_src)
                # Try to list - if it works, it's a directory
                try:
                    sftp.listdir(container_src)
                    # It's a directory, recursive copy
                    self._sftp_get_dir(sftp, container_src, host_dst)
                except:
                    # It's a file
                    sftp.get(container_src, host_dst)
            except:
                # breakpoint()
                print(f"[QemuApptainer] SFTP: source not found: {container_src}")
                source_not_found = True

            sftp.close()
            client.close()
        except Exception as e:
            print(f"[QemuApptainer] SFTP copy_from failed: {e}")
            raise e
        if source_not_found:
            raise FileNotFoundError(f"Source not found: {container_src}")

    def _sftp_get_dir(self, sftp, remote_dir: str, local_dir: str) -> None:
        """Recursively copy a directory from VM via SFTP."""
        Path(local_dir).mkdir(parents=True, exist_ok=True)

        for item in sftp.listdir(remote_dir):
            remote_path = f"{remote_dir}/{item}"
            local_path = str(Path(local_dir) / item)

            try:
                sftp.listdir(remote_path)  # Will fail if it's a file
                self._sftp_get_dir(sftp, remote_path, local_path)
            except:
                sftp.get(remote_path, local_path)
    
    def to_container_path(self, host_path):
        return str(host_path)
    
    def put_file(self, host_path) -> str:
        host_path = os.path.abspath(str(host_path))
        dest = f"/tmp/ga_{uuid.uuid4().hex[:8]}_{os.path.basename(host_path)}"
        self.copy_to(host_path, dest)
        return dest
    
    def save_state(self, save_paths: Optional[List[str]] = None) -> str:
        name = f"snap_{int(time.time())}"
        if self._process and self._process.stdin:
            self._process.stdin.write(f"savevm {name}\n".encode())
            self._process.stdin.flush()
            time.sleep(2)
        return name
    
    def load_state(self, snapshot_name: str) -> None:
        if self._process and self._process.stdin:
            self._process.stdin.write(f"loadvm {snapshot_name}\n".encode())
            self._process.stdin.flush()
            time.sleep(2)
    
    # === Checkpoint support ===

    def set_checkpoint_key(self, cache_level: str, task_id: Optional[str] = None, use_savevm: bool = False) -> None:
        """Set the checkpoint key components.

        This determines which checkpoint file to look for/create.
        Must be called before checkpoint_exists(), create_checkpoint(), or start_from_checkpoint().

        Args:
            cache_level: One of "pre_start", "post_start", "post_task"
            task_id: Task ID (only relevant for post_task level)
            use_savevm: If True, use QEMU savevm/loadvm for true VM state checkpointing.
                       This preserves memory, CPU state, and running processes.
                       When False (default), only disk state is saved (requires reboot).
        """
        self._checkpoint_cache_level = cache_level
        self._checkpoint_task_id = task_id
        self._use_savevm = use_savevm

    def _get_checkpoint_path(self) -> Path:
        """Get the checkpoint path based on current checkpoint key.

        Checkpoint naming:
        - pre_start:  checkpoint_{env_hash}_pre_start.qcow2
        - post_start: checkpoint_{env_hash}_post_start.qcow2
        - post_task:  checkpoint_{env_hash}_post_task_{task_id}.qcow2
        """
        level = self._checkpoint_cache_level
        if level == "post_task" and self._checkpoint_task_id:
            # Task-specific checkpoint
            safe_task_id = self._checkpoint_task_id.replace("/", "_").replace("@", "_")
            return QEMU_CACHE / f"checkpoint_{self.env_hash}_{level}_{safe_task_id}.qcow2"
        else:
            # Environment-level checkpoint (pre_start or post_start)
            return QEMU_CACHE / f"checkpoint_{self.env_hash}_{level}.qcow2"

    def _get_checkpoint_lock_path(self) -> Path:
        """Get the lock file path for the current checkpoint."""
        checkpoint_path = self._get_checkpoint_path()
        return checkpoint_path.with_suffix(".lock")

    @contextmanager
    def _checkpoint_lock(self, blocking: bool = True, timeout: float = 300.0) -> Generator[bool, None, None]:
        """Acquire an exclusive lock for checkpoint operations.

        This prevents race conditions when multiple processes try to create
        or load the same checkpoint simultaneously.

        Args:
            blocking: If True, wait for lock. If False, return immediately if locked.
            timeout: Maximum time to wait for lock (only used if blocking=True).

        Yields:
            True if lock was acquired, False otherwise.
        """
        lock_path = self._get_checkpoint_lock_path()
        lock_path.parent.mkdir(parents=True, exist_ok=True)

        lock_file = None
        acquired = False
        try:
            lock_file = open(lock_path, "w")

            if blocking:
                # Try to acquire with timeout using non-blocking polls
                start_time = time.time()
                while time.time() - start_time < timeout:
                    try:
                        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                        acquired = True
                        break
                    except (IOError, OSError):
                        time.sleep(0.5)  # Poll every 500ms
                if not acquired:
                    print(f"[QemuApptainer] Timeout waiting for checkpoint lock: {lock_path}")
            else:
                # Non-blocking attempt
                try:
                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                    acquired = True
                except (IOError, OSError):
                    pass  # Lock held by another process

            yield acquired

        finally:
            if lock_file:
                if acquired:
                    try:
                        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                    except:
                        pass
                lock_file.close()

    def checkpoint_exists(self) -> bool:
        """Check if a checkpoint exists for current checkpoint key."""
        checkpoint_path = self._get_checkpoint_path()
        exists = checkpoint_path.exists()
        if exists:
            print(f"[QemuApptainer] Checkpoint found: {checkpoint_path}")
        return exists

    def create_checkpoint(self) -> bool:
        """Create checkpoint by converting current instance disk to standalone image.

        This saves the current VM state (after hooks have run) so future runs
        can skip the hook execution. Called by env.py, not internally.

        The checkpoint path is determined by the current checkpoint key
        (set via set_checkpoint_key).

        If use_savevm=True (set via set_checkpoint_key):
            Uses QEMU savevm to capture full VM state (memory, CPU, devices).
            On restore, loadvm instantly brings back running processes and GUI state.

        If use_savevm=False (default):
            Only saves disk state. On restore, VM must fully reboot.

        Uses file locking to prevent race conditions when multiple processes
        try to create the same checkpoint simultaneously.
        """
        if not self._running or not self._instance_qcow2:
            print("[QemuApptainer] Cannot create checkpoint: VM not running")
            return False

        checkpoint_path = self._get_checkpoint_path()
        print(f"[QemuApptainer] Creating checkpoint: {checkpoint_path}")
        print(f"[QemuApptainer]   cache_level={self._checkpoint_cache_level}, task_id={self._checkpoint_task_id}, use_savevm={self._use_savevm}")

        # Acquire exclusive lock before checkpoint creation
        with self._checkpoint_lock(blocking=True, timeout=600.0) as acquired:
            if not acquired:
                print(f"[QemuApptainer] Could not acquire checkpoint lock, aborting creation")
                return False

            # Double-check: another process may have created it while we waited
            if checkpoint_path.exists():
                print(f"[QemuApptainer] Checkpoint already exists (created by another process): {checkpoint_path}")
                # Still need to restart from checkpoint
                self._running = False
                if self._process and self._process.stdin:
                    self._process.stdin.write(b"quit\n")
                    self._process.stdin.flush()
                    try:
                        self._process.wait(timeout=30)
                    except:
                        self._process.kill()
                self._start_from_image(checkpoint_path, use_loadvm=self._use_savevm)
                return True

            try:
                # If use_savevm, create internal snapshot BEFORE shutting down
                # This captures memory, CPU state, and running processes
                if self._use_savevm:
                    print(f"[QemuApptainer] Creating savevm snapshot '{SAVEVM_SNAPSHOT_NAME}'...")
                    print(f"[QemuApptainer]   (this may take a while for VMs with large memory)")
                    if self._process and self._process.stdin:
                        # First, let's query current snapshots to see monitor is working
                        log_file = self._work_dir / "qemu.log"
                        initial_log_size = log_file.stat().st_size if log_file.exists() else 0

                        self._process.stdin.write(b"info snapshots\n")
                        self._process.stdin.flush()
                        time.sleep(1)

                        # Now send savevm command
                        self._process.stdin.write(f"savevm {SAVEVM_SNAPSHOT_NAME}\n".encode())
                        self._process.stdin.flush()

                        # Wait for savevm to complete by monitoring disk size growth
                        # savevm writes VM memory to disk, so we can detect completion
                        # when the disk size stops growing
                        print(f"[QemuApptainer]   Waiting for savevm to complete (monitoring disk size)...")
                        max_wait = 180  # Maximum 3 minutes for very large VMs
                        stable_count = 0
                        stable_threshold = 3  # Need 3 consecutive stable readings
                        check_interval = 5  # Check every 5 seconds
                        prev_size = self._instance_qcow2.stat().st_size

                        for i in range(max_wait // check_interval):
                            time.sleep(check_interval)
                            current_size = self._instance_qcow2.stat().st_size
                            delta_mb = (current_size - prev_size) / (1024 * 1024)

                            if delta_mb < 10:  # Less than 10MB growth = stable
                                stable_count += 1
                                if stable_count >= stable_threshold:
                                    print(f"[QemuApptainer]   savevm complete (disk size stable for {stable_threshold * check_interval}s)")
                                    break
                            else:
                                stable_count = 0
                                print(f"[QemuApptainer]   {(i+1)*check_interval}s: +{delta_mb:.0f}MB")

                            prev_size = current_size
                        else:
                            print(f"[QemuApptainer]   WARNING: savevm may still be in progress after {max_wait}s")

                        # Query snapshots to see if it worked
                        self._process.stdin.write(b"info snapshots\n")
                        self._process.stdin.flush()
                        time.sleep(2)

                        # Read the QEMU log to see what happened
                        if log_file.exists():
                            with open(log_file, 'r') as f:
                                f.seek(initial_log_size)
                                monitor_output = f.read()
                                if monitor_output.strip():
                                    print(f"[QemuApptainer] QEMU monitor output:")
                                    for line in monitor_output.strip().split('\n')[-20:]:  # Last 20 lines
                                        print(f"[QemuApptainer]   {line}")

                        # Check if snapshot was created by looking for it in the log
                        if SAVEVM_SNAPSHOT_NAME in monitor_output:
                            print(f"[QemuApptainer] savevm appears successful!")
                        else:
                            print(f"[QemuApptainer] WARNING: savevm may have failed - snapshot not found in info output")

                # Shutdown VM gracefully to flush disk
                if self._process and self._process.stdin:
                    self.exec("sync")
                    time.sleep(1)
                    self._process.stdin.write(b"quit\n")
                    self._process.stdin.flush()
                    try:
                        self._process.wait(timeout=30)
                    except:
                        self._process.kill()

                # Create checkpoint file
                # IMPORTANT: qemu-img convert does NOT preserve internal snapshots!
                # When use_savevm=True, we must use direct copy to preserve the savevm snapshot.
                # The copied qcow2 will retain its backing chain to the base image.
                if self._use_savevm:
                    # First, verify the snapshot exists in the original overlay
                    print(f"[QemuApptainer] Checking for snapshot in original overlay: {self._instance_qcow2}")
                    pre_copy_result = self._run_qemu_img([
                        "snapshot", "-l", str(self._instance_qcow2)
                    ])
                    print(f"[QemuApptainer] Original overlay snapshots: {pre_copy_result.stdout.strip() or '(none)'}")
                    if pre_copy_result.stderr:
                        print(f"[QemuApptainer] stderr: {pre_copy_result.stderr}")

                    # Direct copy preserves the internal savevm snapshot
                    # IMPORTANT: qemu-img convert would lose the snapshot!
                    print(f"[QemuApptainer] Copying overlay with savevm snapshot (not converting)...")
                    shutil.copy2(str(self._instance_qcow2), str(checkpoint_path))

                    # Verify the snapshot was preserved
                    verify_result = self._run_qemu_img([
                        "snapshot", "-l", str(checkpoint_path)
                    ])
                    if SAVEVM_SNAPSHOT_NAME in verify_result.stdout:
                        print(f"[QemuApptainer] Checkpoint saved with savevm snapshot: {checkpoint_path}")
                        print(f"[QemuApptainer]   Verified: snapshot '{SAVEVM_SNAPSHOT_NAME}' present")
                    else:
                        print(f"[QemuApptainer] WARNING: savevm snapshot may not have been preserved!")
                        print(f"[QemuApptainer]   qemu-img snapshot -l output: {verify_result.stdout}")
                    print(f"[QemuApptainer]   Note: checkpoint references base image via backing chain")
                else:
                    # Convert to standalone qcow2 (flattens backing chain, loses any snapshots)
                    result = self._run_qemu_img([
                        "convert", "-O", "qcow2",
                        str(self._instance_qcow2), str(checkpoint_path)
                    ])
                    if result.returncode != 0:
                        print(f"[QemuApptainer] Checkpoint creation failed: {result.stderr}")
                        return False
                    print(f"[QemuApptainer] Checkpoint saved: {checkpoint_path}")

                # Restart VM from the new checkpoint
                self._running = False
                self._start_from_image(checkpoint_path, use_loadvm=self._use_savevm)
                return True
            except Exception as e:
                print(f"[QemuApptainer] Checkpoint creation failed: {e}")
                return False

    def start_from_checkpoint(self, seed: Optional[int] = None) -> bool:
        """Start VM from existing checkpoint (skips hooks up to checkpoint level).

        The checkpoint path is determined by the current checkpoint key
        (set via set_checkpoint_key).

        If use_savevm=True (set via set_checkpoint_key):
            After booting, uses QEMU loadvm to instantly restore full VM state.
            This is much faster as it skips waiting for SSH, desktop, etc.

        If use_savevm=False (default):
            Standard boot - must wait for SSH, desktop, and reinitialize everything.

        Uses a shared lock to ensure the checkpoint isn't being written while
        we create the COW overlay. The lock is released before VM boot starts.

        Returns False if no checkpoint exists, True if started successfully.
        """
        checkpoint_path = self._get_checkpoint_path()
        print(f"[QemuApptainer] Starting from checkpoint: {checkpoint_path}")
        print(f"[QemuApptainer]   cache_level={self._checkpoint_cache_level}, task_id={self._checkpoint_task_id}, use_savevm={self._use_savevm}")

        # Create instance disk from checkpoint
        # For savevm mode: copy file directly (slower but preserves internal snapshots for loadvm)
        # For non-savevm: COW overlay (fast, multiple instances can share checkpoint)
        self._create_cow_overlay(checkpoint_path, copy_for_savevm=self._use_savevm)

        # Boot VM and optionally restore state with loadvm
        if self._use_savevm:
            self._boot_vm_with_loadvm(seed)
        else:
            self._boot_vm_from_overlay(seed)
        return True

    def _create_cow_overlay(self, base_image: Path, copy_for_savevm: bool = False) -> None:
        """Create COW overlay from base image, or copy for savevm mode.

        Args:
            base_image: The checkpoint/base image to use
            copy_for_savevm: If True, copy the file instead of creating COW overlay.
                           This is needed for savevm mode because QEMU's -loadvm requires
                           the snapshot to be in the topmost file, not a backing file.
                           COW overlays would put the snapshot in the backing file.
        """
        print(f"[QemuApptainer] Instance: {self.instance_name}")
        print(f"[QemuApptainer] KVM: {'enabled' if self.enable_kvm else 'DISABLED (slow!)'}")
        if self.enable_gpu:
            gpu_type = "NVIDIA" if self._has_nvidia else ("DRI/Mesa" if self._has_dri else "none found")
            print(f"[QemuApptainer] GPU: enabled ({gpu_type})")

        # Create work directory
        work_base = self._get_work_base()
        work_base.mkdir(parents=True, exist_ok=True)
        self._work_dir = Path(tempfile.mkdtemp(prefix=f"ga_qemu_{self.instance_id}_", dir=work_base))
        self._instance_qcow2 = self._work_dir / "disk.qcow2"

        if copy_for_savevm:
            # Copy the file directly to preserve internal snapshots for loadvm
            # This is slower than COW but required for savevm/loadvm to work
            print(f"[QemuApptainer] Copying checkpoint for savevm mode (preserves internal snapshots)...")
            print(f'[QemuApptainer] base_image: {base_image}')
            print(f'[QemuApptainer] self._instance_qcow2: {self._instance_qcow2}')
            shutil.copy2(str(base_image), str(self._instance_qcow2))
            size_gb = self._instance_qcow2.stat().st_size / (1024**3)
            print(f"[QemuApptainer] Checkpoint copied ({size_gb:.2f} GB) from {base_image.name}")
        else:
            # Create COW overlay (fast, but snapshots stay in backing file)
            result = self._run_qemu_img([
                "create", "-f", "qcow2",
                "-b", str(base_image.absolute()),
                "-F", "qcow2",
                str(self._instance_qcow2)
            ])
            if result.returncode != 0:
                raise RuntimeError(f"qemu-img failed: {result.stderr}")
            print(f"[QemuApptainer] COW overlay created from {base_image.name}")

    def _boot_vm_from_overlay(self, seed: Optional[int] = None) -> None:
        """Boot VM from already-created COW overlay. Slow operation, no lock needed."""
        # Find ports
        with self._lock:
            self.vnc_port = _find_free_port(5900)
            if self.is_android:
                self.adb_port = _find_free_port(15555)  # ADB instead of SSH
            else:
                self.ssh_port = _find_free_port(2222)
            if self.is_windows:
                self.pyautogui_port = _find_free_port(5555)
            self._assign_fast_input_port()
        if self.is_android:
            print(f"[QemuApptainer] VNC: {self.vnc_port}, ADB: {self.adb_port}")
        elif self.is_windows:
            print(f"[QemuApptainer] VNC: {self.vnc_port}, SSH: {self.ssh_port}, PyAutoGUI: {self.pyautogui_port}")
        else:
            print(f"[QemuApptainer] VNC: {self.vnc_port}, SSH: {self.ssh_port}")
            if self._fast_input_host_port:
                print(f"[QemuApptainer] Fast input: {self._fast_input_host_port}->{self._fast_input_guest_port}")

        # Start VM
        self._start_vm()

        # Wait for VNC
        if not self._wait_for_vnc(timeout=120):
            self._dump_log()
            self.stop()
            raise RuntimeError("VM boot failed")

        # Platform-specific connectivity wait
        if self.is_android:
            # Android: Wait for ADB to be available
            if not self._wait_for_adb(timeout=self._adb_timeout):
                self._dump_log()
                self.stop()
                raise RuntimeError("ADB not available")
            # Handle first-boot setup (dismiss launcher dialog, etc.)
            self._android_first_boot_setup()
            # Setup mounts via ADB (push files to device)
            self._setup_mounts_adb()
        else:
            # Wait for SSH to be available (needed for mounts and exec)
            # Windows needs more time to boot than Linux
            ssh_timeout = 600 if self.is_windows else int(os.environ.get("GYM_ANYTHING_SSH_TIMEOUT", "300"))
            if not self._wait_for_ssh(self.ssh_port, timeout=ssh_timeout):
                self._dump_log()
                self.stop()
                raise RuntimeError("SSH not available")

            # Setup mounts (copy hook scripts and other files to VM)
            # This is needed even when loading from checkpoint because mounts
            # contain hook scripts that may need to run after checkpoint load
            self._setup_mounts(self.ssh_port)

            # Wait for desktop to be ready (polls wmctrl until window manager responds)
            desktop_timeout = int(os.environ.get("GYM_ANYTHING_DESKTOP_TIMEOUT", "120"))
            if not self._wait_for_desktop(timeout=desktop_timeout):
                print("[QemuApptainer] Warning: Desktop may not be fully ready, continuing anyway...")
                # For Windows: Try to connect to PyAutoGUI server anyway (it may be running via scheduled task)
                if self.is_windows and not self._pyautogui_client:
                    print("[QemuApptainer] Attempting to connect to PyAutoGUI server...")
                    self._try_connect_pyautogui_client()
            self._ensure_fast_input_agent()

        # Connect VNC
        self._vnc_pool = VNCConnectionPool(
            host="localhost",
            port=self.vnc_port,
            password=self.vnc_password
        )

        conn = self._vnc_pool.get_connection(retry_count=10, retry_delay=2.0)
        if not conn:
            self.stop()
            raise RuntimeError("VNC connection failed")

        self._running = True
        print(f"[QemuApptainer] VM ready! Resolution: {conn.resolution}")

        settle = self._post_boot_settle_seconds()
        if settle > 0:
            print(f"[QemuApptainer] Waiting {settle}s for compositor to render...")
            time.sleep(settle)

    def _boot_vm_with_loadvm(self, seed: Optional[int] = None) -> None:
        """Boot VM and restore state using QEMU's -loadvm command-line option.

        This is the fast path when use_savevm=True. Using -loadvm on the command line
        is the correct way to restore a savevm snapshot - QEMU handles everything
        automatically before starting the VM.

        After loadvm:
        - All processes are instantly restored (SSH, PyAutoGUI server, etc.)
        - GUI state is preserved (open windows, cursor position, etc.)
        - We only need to reconnect VNC/PyAutoGUI client to new ports
        """
        # Find ports (these will be different from when snapshot was created)
        with self._lock:
            self.vnc_port = _find_free_port(5900)
            if self.is_android:
                self.adb_port = _find_free_port(15555)
            else:
                self.ssh_port = _find_free_port(2222)
            if self.is_windows:
                self.pyautogui_port = _find_free_port(5555)
            self._assign_fast_input_port()

        if self.is_windows:
            print(f"[QemuApptainer] VNC: {self.vnc_port}, SSH: {self.ssh_port}, PyAutoGUI: {self.pyautogui_port}")
        else:
            print(f"[QemuApptainer] VNC: {self.vnc_port}, SSH: {self.ssh_port}")
            if self._fast_input_host_port:
                print(f"[QemuApptainer] Fast input: {self._fast_input_host_port}->{self._fast_input_guest_port}")

        # Start VM with -loadvm option - QEMU automatically restores state before running
        print(f"[QemuApptainer] Starting QEMU with -loadvm {SAVEVM_SNAPSHOT_NAME}...")
        self._start_vm(loadvm_snapshot=SAVEVM_SNAPSHOT_NAME)

        # Wait for VNC - loadvm must read the full snapshot (7+ GB) from disk before
        # VNC becomes responsive. Under shared filesystem I/O contention (many parallel
        # workers), this can take well over 60 seconds, so use a generous timeout.
        print(f"[QemuApptainer] Waiting for VNC...")
        if not self._wait_for_vnc(timeout=300):
            self._dump_log()
            self.stop()
            raise RuntimeError("VM did not respond after loadvm")

        # After loadvm + cont, the VM is running with restored state.
        # The guest's network stack should be intact. However, port forwarding
        # is on the QEMU side (SLIRP), which is newly configured.
        # Wait for services to be reachable via new port forwards.
        if not self.is_android:
            print(f"[QemuApptainer] Waiting for SSH after loadvm...")
            # Give the network a moment to settle
            # Now wait for SSH to be actually reachable
            ssh_timeout = 60 if self.is_windows else 30  # Shorter timeout since VM is already running
            if not self._wait_for_ssh(self.ssh_port, timeout=ssh_timeout):
                if self._fast_uinput_keyboard_enabled():
                    self._dump_log()
                    self.stop()
                    raise RuntimeError("SSH not responding after loadvm; cannot start required fast input agent")
                print(f"[QemuApptainer] Warning: SSH not responding after loadvm, continuing anyway...")
            else:
                print(f"[QemuApptainer] SSH is ready after loadvm")

            # Setup mounts - still needed because host paths may have changed
            # But this is fast since files are likely already there
            self._setup_mounts(self.ssh_port)
            self._ensure_fast_input_agent()

        # Connect VNC pool to new port
        self._vnc_pool = VNCConnectionPool(
            host="localhost",
            port=self.vnc_port,
            password=self.vnc_password
        )

        conn = self._vnc_pool.get_connection(retry_count=10, retry_delay=2.0)
        if not conn:
            self.stop()
            raise RuntimeError("VNC connection failed after loadvm")

        # For Windows: The restored PyAutoGUI server has corrupted socket state
        # from the savevm snapshot (zombie TCP connections, broken threads).
        # We need to kill it and start a fresh server.
        if self.is_windows:
            print(f"[QemuApptainer] Restarting PyAutoGUI server after loadvm...")
            self._kill_existing_pyautogui_server()
            if not self._start_windows_pyautogui_server():
                print(f"[QemuApptainer] Warning: PyAutoGUI server failed to start after loadvm")

        self._running = True
        print(f"[QemuApptainer] VM ready via loadvm! Resolution: {conn.resolution}")

    def _start_from_image(self, base_image: Path, seed: Optional[int] = None, use_loadvm: bool = False) -> None:
        """Internal: Start VM from specified base image.

        This is used by create_checkpoint() to restart from a newly-created checkpoint.
        It does NOT use locking - the caller is responsible for any needed synchronization.

        Args:
            base_image: Path to the checkpoint qcow2 file
            seed: Random seed (unused currently)
            use_loadvm: If True, use loadvm for fast state restore after boot
        """
        # For loadvm, copy file to preserve internal snapshots
        self._create_cow_overlay(base_image, copy_for_savevm=use_loadvm)
        if use_loadvm:
            self._boot_vm_with_loadvm(seed)
        else:
            self._boot_vm_from_overlay(seed)

    def delete_checkpoint(self) -> bool:
        """Delete the checkpoint for current checkpoint key."""
        checkpoint_path = self._get_checkpoint_path()
        if checkpoint_path.exists():
            checkpoint_path.unlink()
            print(f"[QemuApptainer] Checkpoint deleted: {checkpoint_path}")
            return True
        return False
