"""
Apple Virtualization Framework Runner -- uses vfkit + Rosetta for near-native
x86_64 binary translation on Apple Silicon.

Runs an arm64 Ubuntu VM under Apple's Hypervisor.framework (HVF) and mounts
Rosetta 2 into the guest for transparent x86_64 → arm64 binary translation.
This gives ~80% of native speed for x86 binaries (vs ~15% with QEMU TCG).

Requires:
    - macOS 13+ on Apple Silicon
    - vfkit (brew install vfkit)
    - gvproxy (from gvisor-tap-vsock, for SSH port forwarding)
    - Rosetta 2 (softwareupdate --install-rosetta)

Uses the same arm64 base QCOW2 as QemuNativeRunner (converted to raw).
Uses the same env.json files -- zero benchmark changes.

Usage:
    export GYM_ANYTHING_RUNNER=avf
"""

from __future__ import annotations

import os
import shutil
import signal
import socket
import subprocess
import tempfile
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

from ...specs import EnvSpec
from .base import BaseRunner
from .qemu_apptainer import QEMU_CACHE, _get_env_hash, _find_free_port
from .vnc_utils import VNCConnectionPool

# Cache for converted raw images
AVF_CACHE = QEMU_CACHE / "avf"

# Rosetta mount point inside the guest
ROSETTA_MOUNT = "/mnt/rosetta"

# Cloud-init setup script to configure Rosetta binfmt_misc in the guest
ROSETTA_SETUP_SCRIPT = f"""#!/bin/bash
# Mount Rosetta from host via VirtioFS
mkdir -p {ROSETTA_MOUNT}
mount -t virtiofs rosetta-share {ROSETTA_MOUNT} 2>/dev/null || true

# Register Rosetta as handler for x86_64 ELF binaries via binfmt_misc
if [ -f {ROSETTA_MOUNT}/rosetta ]; then
    # Ensure binfmt_misc is mounted
    mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true

    # Register Rosetta for x86_64 ELF
    echo ':rosetta:M::\\x7fELF\\x02\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x02\\x00\\x3e\\x00:\\xff\\xff\\xff\\xff\\xff\\xfe\\xfe\\x00\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xfe\\xff\\xff\\xff:{ROSETTA_MOUNT}/rosetta:F' > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
    echo "Rosetta registered for x86_64 binary translation"
else
    echo "WARNING: Rosetta binary not found at {ROSETTA_MOUNT}/rosetta"
fi
"""


class AVFRunner(BaseRunner):
    """Apple Virtualization Framework runner with Rosetta x86_64 translation.

    Uses vfkit (Apple Virtualization Framework CLI) for the VM and gvproxy
    for networking. Rosetta 2 is mounted into the guest for transparent
    x86_64 binary execution at near-native speed.

    Inherits SSH-based command execution from the QEMU runner codebase.
    """

    def __init__(self, spec: EnvSpec):
        super().__init__(spec)

        self._check_prerequisites()

        self.instance_id = uuid.uuid4().hex[:12]
        self.instance_name = f"ga_avf_{self.instance_id}"

        # Resources
        self.memory = int((spec.resources.mem_gb or 8) * 1024)  # vfkit uses MiB
        self.cpus = int(spec.resources.cpu or 4)

        # Screen
        screen_spec = next((o for o in spec.observation if o.type == "rgb_screen"), None)
        self.resolution = screen_spec.resolution if screen_spec else (1920, 1080)

        # SSH
        self._ssh_user = "ga"
        self._ssh_password = "password123"
        self.ssh_port: int = 22
        self._guest_ip: Optional[str] = None
        self._mac_address: Optional[str] = None

        # VNC (x0vncserver in guest, exposed via gvproxy)
        vnc_cfg = getattr(spec, "vnc", None)
        self.vnc_password = vnc_cfg.password if vnc_cfg and vnc_cfg.password else "password"
        self.vnc_port: Optional[int] = None
        self._vnc_pool: Optional[VNCConnectionPool] = None

        # Base image (raw, converted from arm64 QCOW2)
        AVF_CACHE.mkdir(parents=True, exist_ok=True)
        self._base_raw = AVF_CACHE / "base_ubuntu_gnome_arm64.raw"

        # State
        self._running = False
        self._vfkit_process: Optional[subprocess.Popen] = None
        self._gvproxy_process: Optional[subprocess.Popen] = None
        self._work_dir: Optional[Path] = None
        self._instance_raw: Optional[Path] = None
        self._ssh_tunnel_process: Optional[subprocess.Popen] = None
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._consecutive_ssh_failures = 0
        self._max_consecutive_ssh_failures = 5

        # Env hash for checkpoints
        from ...config.presets import is_windows_preset, is_android_preset
        self.is_windows = False
        self.is_android = False
        self.env_hash = _get_env_hash(spec)

        # Checkpoint caching
        self._checkpoint_cache_level: str = "pre_start"
        self._checkpoint_task_id: Optional[str] = None

        # Recording dir
        self._artifacts_root = os.path.abspath(spec.recording.output_dir)

    def _log(self, msg: str) -> None:
        """Print a log message, suppressed when TUI reporter is active."""
        if self._reporter:
            self._reporter.log(msg)
        else:
            print(msg, flush=True)

    def _check_prerequisites(self) -> None:
        if not shutil.which("vfkit"):
            raise RuntimeError("vfkit not found. Install: brew install vfkit")
        if not shutil.which("qemu-img"):
            raise RuntimeError("qemu-img not found. Install: brew install qemu")

    def _ensure_base_raw(self) -> None:
        """Ensure the raw base image exists, converting from QCOW2 if needed."""
        if self._base_raw.exists():
            return

        # Look for the arm64 QCOW2 built by QemuNativeRunner
        qcow2_path = QEMU_CACHE / "base_ubuntu_gnome_arm64.qcow2"
        if not qcow2_path.exists():
            # Build it using QemuNativeRunner's builder
            print("[AVF] arm64 base QCOW2 not found, building...")
            from .qemu_native import QemuNativeRunner
            temp_spec = EnvSpec.from_dict({
                'id': 'avf-base-build',
                'observation': [{'type': 'rgb_screen', 'resolution': [1920, 1080]}],
                'action': [{'type': 'mouse'}],
                'recording': {'enable': False, 'output_dir': '/tmp/avf-build'},
                'vnc': {'password': 'password'},
            })
            builder = QemuNativeRunner(temp_spec)
            builder._create_base_qcow2()

        print("[AVF] Converting QCOW2 to raw (one-time, may take a few minutes)...")
        result = subprocess.run(
            ["qemu-img", "convert", "-f", "qcow2", "-O", "raw",
             str(qcow2_path), str(self._base_raw)],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(f"qemu-img convert failed: {result.stderr}")
        size_gb = self._base_raw.stat().st_size / (1024**3)
        print(f"[AVF] Raw base image ready: {self._base_raw} ({size_gb:.1f} GB)")

    @staticmethod
    def _cleanup_orphans() -> None:
        """Kill orphaned vfkit/gvproxy processes from previous crashed runs."""
        work_base = AVF_CACHE / "work"
        if not work_base.exists():
            return
        for d in work_base.iterdir():
            if not d.is_dir() or not d.name.startswith("ga_avf_"):
                continue
            # Check if the owning process is still alive by looking for a pidfile
            pid_file = d / "runner.pid"
            if pid_file.exists():
                try:
                    pid = int(pid_file.read_text().strip())
                    os.kill(pid, 0)  # Check if process exists
                    continue  # Still alive, don't touch
                except (ValueError, ProcessLookupError, PermissionError):
                    pass  # Dead process, clean up
            # Kill any processes using sockets in this work dir
            for sock in d.glob("*.sock"):
                try:
                    # Find and kill processes using this socket
                    result = subprocess.run(
                        ["lsof", "-t", str(sock)],
                        capture_output=True, text=True, timeout=5,
                    )
                    for pid_str in result.stdout.strip().split():
                        try:
                            os.kill(int(pid_str), signal.SIGKILL)
                        except (ProcessLookupError, PermissionError):
                            pass
                except Exception:
                    pass
            shutil.rmtree(d, ignore_errors=True)

    def start(self, seed: Optional[int] = None) -> None:
        self._report_start("instance", self.instance_name)
        self._log(f"[AVF] Instance: {self.instance_name}")

        # Clean up orphaned processes from previous crashed runs
        self._cleanup_orphans()

        # Register atexit handler so stop() runs even on unhandled exceptions
        import atexit
        atexit.register(self.stop)

        self._report_done("instance", self.instance_name)

        # Ensure base image
        self._report_start("base_image", "checking cache")
        self._ensure_base_raw()
        self._report_done("base_image", "cached")

        # Create work directory
        work_base = AVF_CACHE / "work"
        work_base.mkdir(parents=True, exist_ok=True)
        self._work_dir = Path(tempfile.mkdtemp(prefix=f"ga_avf_{self.instance_id}_", dir=work_base))

        # Write PID file so future runs can detect orphans
        (self._work_dir / "runner.pid").write_text(str(os.getpid()))

        # Create COW overlay using APFS clonefile (instant, no extra disk space)
        self._instance_raw = self._work_dir / "disk.raw"
        subprocess.run(["cp", "-c", str(self._base_raw), str(self._instance_raw)],
                       check=True, capture_output=True)
        self._report_done("cow_overlay", "APFS clonefile")
        self._log(f"[AVF] APFS COW overlay created")

        # Allocate a unique SSH port for this instance
        with self._lock:
            self.ssh_port = _find_free_port(2222)

        # Networking: gvproxy provides isolated network per VM.
        # -ssh-port is set to a throwaway port to prevent gvproxy binding to default 2222
        # (which conflicts in parallel runs). Actual SSH forwarding is done via the HTTP API
        # to the correct guest IP (192.168.127.3), not gvproxy's hardcoded .2.
        gvproxy_vm_sock = self._work_dir / "net.sock"
        gvproxy_api_sock = self._work_dir / "api.sock"
        gvproxy_dummy_ssh = _find_free_port(10000)  # throwaway, just to avoid 2222 conflict
        gvproxy_log = self._work_dir / "gvproxy.log"
        with open(gvproxy_log, "w") as gl:
            self._gvproxy_process = subprocess.Popen(
                [
                    "gvproxy",
                    "-listen-vfkit", f"unixgram://{gvproxy_vm_sock}",
                    "-listen", f"unix://{gvproxy_api_sock}",
                    "-ssh-port", str(gvproxy_dummy_ssh),
                ],
                stdout=gl, stderr=subprocess.STDOUT,
                preexec_fn=os.setsid,
            )
        # Wait for socket — check process liveness on every iteration
        for _ in range(10):
            if gvproxy_vm_sock.exists():
                break
            if self._gvproxy_process.poll() is not None:
                err = gvproxy_log.read_text()[:500] if gvproxy_log.exists() else "no log"
                raise RuntimeError(
                    f"gvproxy exited immediately (code {self._gvproxy_process.returncode}): {err}"
                )
            time.sleep(0.5)
        if not gvproxy_vm_sock.exists():
            err = gvproxy_log.read_text()[:500] if gvproxy_log.exists() else "no log"
            raise RuntimeError(f"gvproxy failed to create socket after 5s: {err}")
        self._report_done("networking", f"SSH port {self.ssh_port}")
        self._log(f"[AVF] gvproxy started (isolated network, SSH port {self.ssh_port})")

        # Generate a unique MAC address
        h = uuid.uuid4().hex
        self._mac_address = f"52:54:00:{h[:2]}:{h[2:4]}:{h[4:6]}"

        # EFI variable store
        efi_store = self._work_dir / "efi-variable-store"

        # Build vfkit command — gvproxy networking (isolated per VM)
        vfkit_cmd = [
            "vfkit",
            "--cpus", str(self.cpus),
            "--memory", str(self.memory),
            "--bootloader", f"efi,variable-store={efi_store},create",
            "--device", f"virtio-blk,path={self._instance_raw}",
            "--device", f"virtio-net,unixSocketPath={gvproxy_vm_sock},mac={self._mac_address}",
            "--device", "virtio-rng",
            "--device", f"virtio-gpu,width={self.resolution[0]},height={self.resolution[1]}",
            "--device", "rosetta,mountTag=rosetta-share",
        ]

        # Start vfkit
        vfkit_log = self._work_dir / "vfkit.log"
        self._report_start("vm_launch", f"{self.cpus} CPU, {self.memory} MiB")
        self._log(f"[AVF] Starting vfkit VM...")
        with open(vfkit_log, "w") as lf:
            self._vfkit_process = subprocess.Popen(
                vfkit_cmd,
                stdout=lf, stderr=subprocess.STDOUT,
                preexec_fn=os.setsid,
            )

        # Wait for guest to get DHCP from gvproxy (192.168.127.x)
        # gvproxy assigns 192.168.127.3 via its built-in DHCP
        self._guest_ip = "192.168.127.3"  # gvproxy's default guest IP

        # Wait for VM to boot, then set up SSH forwarding via gvproxy HTTP API.
        # The API forwards to 192.168.127.3 (actual guest IP from DHCP),
        # unlike -ssh-port which hardcodes 192.168.127.2.
        for i in range(60):
            if self._vfkit_process.poll() is not None:
                self._dump_logs()
                self.stop()
                raise RuntimeError(
                    f"vfkit exited during boot (code {self._vfkit_process.returncode})"
                )
            if i >= 15:  # Try port forwarding after ~15s
                try:
                    self._expose_port_via_gvproxy(gvproxy_api_sock, self.ssh_port, 22)
                    self._report_done("port_forward", f"localhost:{self.ssh_port} \u2192 guest:22")
                    self._log(f"[AVF] Port forwarding: localhost:{self.ssh_port} → {self._guest_ip}:22")
                    break
                except Exception:
                    pass  # Guest not ready yet, retry
            time.sleep(1)
        else:
            self._dump_logs()
            self.stop()
            raise RuntimeError("Failed to set up port forwarding after 60s")

        # Wait for SSH — check vfkit and gvproxy liveness on every iteration
        self._report_start("ssh_wait")
        if not self._wait_for_ssh(timeout=300):
            self._dump_logs()
            self.stop()
            raise RuntimeError("VM failed to boot (SSH not available)")

        self._report_done("ssh_wait")
        self._log(f"[AVF] SSH available at localhost:{self.ssh_port}")

        # Set up Rosetta in the guest
        self._report_start("rosetta")
        self._setup_rosetta()
        self._report_done("rosetta")

        # Wait for desktop
        self._report_start("desktop_wait")
        self._wait_for_desktop(timeout=120)
        self._report_done("desktop_wait")

        # Start VNC server in guest
        self._report_start("vnc_setup")
        self._start_guest_vnc()
        if self._vnc_pool:
            self._report_done("vnc_setup", f"localhost:{self.vnc_port}")
        else:
            self._report_fail("vnc_setup", "VNC not available")

        # Set up mounts
        mounts = getattr(self.spec, "mounts", [])
        if mounts:
            self._report_start("mounts", f"{len(mounts)} mounts")
            self._setup_mounts()
            self._report_done("mounts")
        else:
            self._report_skip("mounts", "none configured")

        self._running = True
        self._report_done("ready")
        self._log(f"[AVF] VM ready!")

    def _start_guest_vnc(self) -> None:
        """Start x0vncserver in the guest and expose via gvproxy.

        x0vncserver (from TigerVNC) attaches to the running Xorg display,
        serving the same framebuffer that QEMU's built-in VNC would serve.
        """
        try:
            # Install x11vnc if not present (attaches to existing X display)
            result = self._ssh_exec("which x11vnc 2>&1", timeout=10, capture=True)
            if "x11vnc" not in result:
                self._log("[AVF] Installing x11vnc...")
                self._ssh_exec("sudo apt-get update -qq && sudo apt-get install -y -qq x11vnc", timeout=120)

            # Start x11vnc on the existing display :1
            self._ssh_exec(
                f"x11vnc -display :1 -passwd {self.vnc_password} "
                f"-rfbport 5900 -shared -forever -bg -o /tmp/x11vnc.log 2>&1",
                timeout=15
            )

            # Wait for x11vnc to bind — verify the process is alive each iteration
            vnc_bound = False
            for _ in range(10):
                proc_check = self._ssh_exec("pgrep -x x11vnc", timeout=5, capture=True)
                if not proc_check.strip():
                    log = self._ssh_exec("cat /tmp/x11vnc.log 2>&1 | tail -5", timeout=5, capture=True)
                    raise RuntimeError(f"x11vnc exited immediately: {log}")
                result = self._ssh_exec("ss -tlnp | grep 5900", timeout=5, capture=True)
                if "5900" in result:
                    vnc_bound = True
                    break
                time.sleep(1)
            if not vnc_bound:
                raise RuntimeError("x11vnc started but not listening on port 5900")

            # Tunnel VNC through SSH (more reliable than gvproxy HTTP API)
            with self._lock:
                self.vnc_port = _find_free_port(5900)
            self._start_vnc_tunnel(self.vnc_port, 5900)

            # Create VNC connection pool (same as QemuApptainerRunner)
            self._vnc_pool = VNCConnectionPool(
                host="localhost",
                port=self.vnc_port,
                password=self.vnc_password,
            )
            conn = self._vnc_pool.get_connection(retry_count=5, retry_delay=2.0)
            if not conn:
                self._vnc_pool = None
                raise RuntimeError("VNC handshake failed after 5 retries")
            self._log(f"[AVF] VNC available at localhost:{self.vnc_port} ({conn.resolution[0]}x{conn.resolution[1]})")
        except Exception as e:
            self._log(f"[AVF] VNC setup failed: {e}")
            self._vnc_pool = None

    def _expose_port_via_gvproxy(self, api_sock: Path, host_port: int, guest_port: int) -> None:
        """Expose a guest port on the host via gvproxy's HTTP API."""
        import http.client
        import json

        data = json.dumps({
            "local": f":{host_port}",
            "remote": f"{self._guest_ip}:{guest_port}",
        }).encode()

        class _UnixConn(http.client.HTTPConnection):
            def __init__(self, sock_path):
                super().__init__("localhost")
                self._sock_path = sock_path
            def connect(self):
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(self._sock_path)

        conn = _UnixConn(str(api_sock))
        conn.request("POST", "/services/forwarder/expose", body=data,
                     headers={"Content-Type": "application/json"})
        resp = conn.getresponse()
        if resp.status not in (200, 201):
            body = resp.read().decode()
            raise RuntimeError(f"gvproxy expose failed ({resp.status}): {body}")
        conn.close()

    def _start_vnc_tunnel(self, local_port: int, remote_port: int) -> None:
        """Create an SSH -L tunnel for VNC: localhost:local_port -> guest:remote_port."""
        askpass = self._work_dir / "askpass.sh"
        askpass.write_text(f"#!/bin/sh\necho '{self._ssh_password}'\n")
        askpass.chmod(0o700)
        env = {**os.environ, "SSH_ASKPASS": str(askpass), "SSH_ASKPASS_REQUIRE": "force"}

        tunnel_log = self._work_dir / "ssh_tunnel.log"
        with open(tunnel_log, "w") as tl:
            self._ssh_tunnel_process = subprocess.Popen(
                [
                    "ssh",
                    "-L", f"{local_port}:localhost:{remote_port}",
                    "-N",
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "UserKnownHostsFile=/dev/null",
                    "-o", "ControlMaster=no",
                    "-o", "ControlPath=none",
                    "-o", "LogLevel=ERROR",
                    "-p", str(self.ssh_port),
                    f"{self._ssh_user}@localhost",
                ],
                stdin=subprocess.DEVNULL,
                stdout=tl,
                stderr=subprocess.STDOUT,
                env=env,
                preexec_fn=os.setsid,
            )
        # Wait for tunnel — check it didn't exit immediately
        for _ in range(10):
            if self._ssh_tunnel_process.poll() is not None:
                err = tunnel_log.read_text()[:500] if tunnel_log.exists() else "no log"
                raise RuntimeError(
                    f"SSH tunnel exited immediately (code {self._ssh_tunnel_process.returncode}): {err}"
                )
            # Check if port is actually listening
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.settimeout(1)
                    s.connect(("localhost", local_port))
                    break
            except (ConnectionRefusedError, OSError):
                time.sleep(0.5)

    def _discover_guest_ip(self, timeout: float = 180) -> Optional[str]:
        """Find guest IP by matching MAC address in macOS DHCP leases.

        The lease file format uses "1," prefix and strips leading zeros from
        MAC octets (e.g., 52:54:00:ab:cd:ef → 1,52:54:0:ab:cd:ef).
        """
        import re
        lease_file = Path("/var/db/dhcpd_leases")

        # Normalize our MAC to match the lease format:
        # strip leading zero from each octet, e.g. "00" → "0", "0a" → "a"
        our_octets = self._mac_address.lower().split(":")
        our_normalized = ":".join(o.lstrip("0") or "0" for o in our_octets)
        # Lease format: "1,<normalized_mac>"
        target = f"1,{our_normalized}"

        deadline = time.time() + timeout
        while time.time() < deadline:
            if lease_file.exists():
                content = lease_file.read_text()
                for block in content.split("}"):
                    if target in block:
                        ip_match = re.search(r"ip_address=(\S+)", block)
                        if ip_match:
                            return ip_match.group(1)
            time.sleep(3)
        return None

    def _wait_for_ssh(self, timeout: float = 300) -> bool:
        """Poll until SSH is responsive. Checks vfkit/gvproxy liveness each iteration."""
        import paramiko
        import logging
        paramiko_logger = logging.getLogger("paramiko")
        old_level = paramiko_logger.level
        paramiko_logger.setLevel(logging.CRITICAL)

        if not self._reporter:
            print("[AVF] Waiting for VM to boot...", end="", flush=True)
        deadline = time.time() + timeout
        try:
            while time.time() < deadline:
                # Check that vfkit and gvproxy are still alive
                if self._vfkit_process and self._vfkit_process.poll() is not None:
                    self._log(f"[AVF] vfkit died (code {self._vfkit_process.returncode})")
                    return False
                if self._gvproxy_process and self._gvproxy_process.poll() is not None:
                    self._log(f"[AVF] gvproxy died (code {self._gvproxy_process.returncode})")
                    return False
                try:
                    client = paramiko.SSHClient()
                    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                    client.connect("localhost", port=self.ssh_port, username=self._ssh_user,
                                  password=self._ssh_password, timeout=10, look_for_keys=False,
                                  banner_timeout=10)
                    client.close()
                    if not self._reporter:
                        print(" ready!", flush=True)
                    return True
                except Exception:
                    elapsed = int(time.time() - (deadline - timeout))
                    self._report_update("ssh_wait", f"{elapsed}s elapsed")
                    if not self._reporter:
                        print(".", end="", flush=True)
                    time.sleep(3)
            if not self._reporter:
                print(" timeout!", flush=True)
            return False
        finally:
            paramiko_logger.setLevel(old_level)

    def _setup_rosetta(self) -> None:
        """Mount Rosetta and register binfmt_misc in the guest."""
        self._log("[AVF] Setting up Rosetta for x86_64 translation...")
        try:
            # Mount Rosetta VirtioFS share
            self._ssh_exec("sudo mkdir -p /mnt/rosetta", timeout=10)
            self._ssh_exec("sudo mount -t virtiofs rosetta-share /mnt/rosetta", timeout=10)

            # Register binfmt_misc
            self._ssh_exec("sudo mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true", timeout=10)
            binfmt_entry = (
                r':rosetta:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'
                r'\x02\x00\x3e\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff'
                r'\xff\xff\xff\xff\xfe\xff\xff\xff:/mnt/rosetta/rosetta:F'
            )
            self._ssh_exec(
                f"echo '{binfmt_entry}' | sudo tee /proc/sys/fs/binfmt_misc/register > /dev/null 2>&1 || true",
                timeout=10
            )

            # Enable multi-arch so dpkg can install x86_64 .deb packages.
            # Newer base images have this baked in; older ones need runtime setup.
            has_amd64 = self._ssh_exec("dpkg --print-foreign-architectures 2>&1", timeout=10, capture=True)
            if "amd64" not in has_amd64:
                self._ssh_exec("sudo dpkg --add-architecture amd64", timeout=10)
                self._ssh_exec(
                    r"sudo sed -i 's|^deb http://ports|deb [arch=arm64] http://ports|g' /etc/apt/sources.list",
                    timeout=10,
                )
                self._ssh_exec(
                    "sudo tee /etc/apt/sources.list.d/amd64.list > /dev/null << 'AMDEOF'\n"
                    "deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse\n"
                    "deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse\n"
                    "deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy-security main restricted universe multiverse\n"
                    "AMDEOF",
                    timeout=10,
                )
                self._ssh_exec("sudo apt-get update -qq 2>/dev/null", timeout=120)

            # Install x86_64 core runtime + common GUI libs so Rosetta can run
            # any x86_64 binary (bundled JREs, Qt apps, GTK apps, etc.)
            has_libc_amd64 = self._ssh_exec("dpkg -s libc6:amd64 2>&1", timeout=10, capture=True)
            if "Status: install ok" not in has_libc_amd64:
                self._log("[AVF] Installing x86_64 runtime + GUI libraries...")
                self._ssh_exec(
                    "sudo apt-get install -y -qq "
                    "libc6:amd64 libstdc++6:amd64 "
                    "libx11-6:amd64 libxext6:amd64 libxrender1:amd64 libxtst6:amd64 "
                    "libxi6:amd64 libxrandr2:amd64 libxcursor1:amd64 libxfixes3:amd64 "
                    "libxinerama1:amd64 libxcomposite1:amd64 libxdamage1:amd64 "
                    "libfreetype6:amd64 libfontconfig1:amd64 "
                    "libgl1:amd64 libglx-mesa0:amd64 libglu1-mesa:amd64 "
                    "libsm6:amd64 libice6:amd64 "
                    "2>/dev/null",
                    timeout=180,
                )

            # Verify
            result = self._ssh_exec("file /mnt/rosetta/rosetta 2>&1", timeout=10, capture=True)
            if "Mach-O" in result or "executable" in result:
                self._log("[AVF] Rosetta + multi-arch amd64 ready")
            else:
                self._log(f"[AVF] WARNING: Rosetta may not be available: {result[:100]}")
        except Exception as e:
            self._log(f"[AVF] WARNING: Rosetta setup failed: {e}")
            self._log("[AVF] x86_64 binaries will not be translated (arm64-native packages still work)")

    def _wait_for_desktop(self, timeout: float = 120) -> bool:
        """Wait for GNOME desktop to be ready. Checks vfkit liveness each iteration."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self._vfkit_process and self._vfkit_process.poll() is not None:
                self._log(f"[AVF] vfkit died while waiting for desktop (code {self._vfkit_process.returncode})")
                return False
            try:
                result = self._ssh_exec(
                    "DISPLAY=:1 xdotool getdisplaygeometry 2>&1",
                    timeout=10, capture=True
                )
                if result and any(c.isdigit() for c in result):
                    self._log(f"[AVF] Desktop ready: {result.strip()}")
                    return True
            except Exception:
                pass
            time.sleep(3)
        self._log("[AVF] WARNING: Desktop not detected within timeout")
        return False

    def stop(self) -> None:
        if not self._running and not self._vfkit_process and not self._gvproxy_process:
            return
        self._stop_event.set()

        # Close VNC pool
        if self._vnc_pool:
            try:
                self._vnc_pool.close()
            except Exception:
                pass
            self._vnc_pool = None

        # Kill processes in reverse dependency order: tunnel → vfkit → gvproxy
        for proc_attr in ("_ssh_tunnel_process", "_vfkit_process", "_gvproxy_process"):
            proc = getattr(self, proc_attr, None)
            if proc and proc.poll() is None:
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                    proc.wait(timeout=5)
                except Exception:
                    try:
                        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                    except Exception:
                        pass
            setattr(self, proc_attr, None)

        # Cleanup work dir
        if self._work_dir and self._work_dir.exists():
            shutil.rmtree(self._work_dir, ignore_errors=True)

        self._running = False

    def _dump_logs(self) -> None:
        if not self._work_dir:
            return
        for log_name in ["vfkit.log", "gvproxy.log", "serial.log"]:
            log_path = self._work_dir / log_name
            if log_path.exists():
                content = log_path.read_text()[-2000:]
                print(f"[AVF] === {log_name} (last 2000 chars) ===")
                print(content)

    # ---- SSH helpers (reusing paramiko pattern from QEMU runner) ----

    def _ssh_exec(self, cmd: str, timeout: int = 600, capture: bool = False) -> str:
        """Execute command in VM via SSH. Tracks consecutive failures."""
        if self._consecutive_ssh_failures >= self._max_consecutive_ssh_failures:
            raise RuntimeError(
                f"VM unresponsive: {self._consecutive_ssh_failures} consecutive SSH failures. Aborting."
            )
        import paramiko
        try:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect("localhost", port=self.ssh_port, username=self._ssh_user,
                          password=self._ssh_password, timeout=15, look_for_keys=False)
            _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
            out = stdout.read().decode()
            err = stderr.read().decode()
            exit_code = stdout.channel.recv_exit_status()
            client.close()
            self._consecutive_ssh_failures = 0
            if capture:
                return out
            if exit_code != 0:
                print(f"[AVF] SSH cmd failed (exit {exit_code}): {err[:200]}")
            return out
        except Exception as e:
            self._consecutive_ssh_failures += 1
            if capture:
                return ""
            raise

    # ---- BaseRunner interface ----

    def exec(self, cmd: str, env: Optional[Dict[str, str]] = None,
             user: Optional[str] = None, use_pty: bool = True, timeout: int = 600) -> int:
        """Execute a command in the VM. Matches QemuApptainerRunner's sudo wrapping."""
        env = self.merge_exec_env(env)
        from ...security import wrap_posix_command_with_env
        wrapped_cmd = f"sudo -E {wrap_posix_command_with_env(cmd, env)}"
        try:
            import paramiko
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect("localhost", port=self.ssh_port, username=self._ssh_user,
                          password=self._ssh_password, timeout=15, look_for_keys=False)
            _, stdout, stderr = client.exec_command(wrapped_cmd, timeout=timeout, get_pty=use_pty)
            exit_code = stdout.channel.recv_exit_status()
            err = stderr.read().decode()
            client.close()
            # SSH connected successfully — reset failure counter regardless of command exit code
            self._consecutive_ssh_failures = 0
            if exit_code != 0 and err:
                print(f"[AVF] exec failed (exit {exit_code}): {err[:200]}")
            return exit_code
        except RuntimeError:
            raise
        except Exception as e:
            # Connection-level failure (SSH unreachable, auth failed, timeout)
            self._consecutive_ssh_failures += 1
            print(f"[AVF] exec failed: {e}")
            return 1

    def exec_capture(self, cmd: str) -> str:
        env = self.default_exec_env()
        from ...security import wrap_posix_command_with_env
        return self._ssh_exec(f"sudo -E {wrap_posix_command_with_env(cmd, env)}", capture=True)

    def run_reset(self, reset_script: str, seed: Optional[int] = None) -> None:
        env_vars = {"SEED": str(seed)} if seed is not None else None
        self.exec(f"bash -lc {repr(reset_script)}", env=env_vars)

    def run_task_init(self, init_script: str) -> None:
        # use_pty=False prevents SIGHUP from killing background processes
        self.exec(f"bash -lc {repr(init_script)}", use_pty=False)

    def inject_action(self, action: Dict[str, Any]) -> None:
        """Inject mouse/keyboard action via xdotool."""
        if "mouse" in action:
            mouse = action["mouse"]
            if "left_click" in mouse:
                x, y = mouse["left_click"]
                self._ssh_exec(f"DISPLAY=:1 xdotool mousemove {x} {y} click 1", timeout=10)
            elif "right_click" in mouse:
                x, y = mouse["right_click"]
                self._ssh_exec(f"DISPLAY=:1 xdotool mousemove {x} {y} click 3", timeout=10)
            elif "move" in mouse:
                x, y = mouse["move"]
                self._ssh_exec(f"DISPLAY=:1 xdotool mousemove {x} {y}", timeout=10)
            elif "scroll" in mouse:
                clicks = mouse["scroll"]
                btn = 4 if clicks > 0 else 5
                for _ in range(abs(clicks)):
                    self._ssh_exec(f"DISPLAY=:1 xdotool click {btn}", timeout=10)
        if "keyboard" in action:
            kb = action["keyboard"]
            if "text" in kb:
                text = kb["text"]
                self._ssh_exec(f"DISPLAY=:1 xdotool type -- {repr(text)}", timeout=10)
            elif "key" in kb:
                key = kb["key"]
                self._ssh_exec(f"DISPLAY=:1 xdotool key {key}", timeout=10)

    def capture_observation(self) -> Dict[str, Any]:
        return {}

    def capture_screenshot(self, host_path) -> bool:
        """Capture screenshot via VNC (primary) or ffmpeg x11grab (fallback)."""
        host_path = Path(host_path)
        host_path.parent.mkdir(parents=True, exist_ok=True)

        # Primary: VNC capture (same as QemuApptainerRunner)
        if self._vnc_pool:
            conn = self._vnc_pool.get_connection()
            if conn:
                try:
                    result = conn.capture_screenshot(save_path=host_path)
                    if result is not None:
                        return True
                except Exception:
                    pass

        # Fallback: ffmpeg x11grab via SSH
        remote_tmp = f"/tmp/ga_screenshot_{uuid.uuid4().hex[:8]}.png"
        width, height = self.resolution
        cmd = (
            f"DISPLAY=:1 ffmpeg -nostdin -y -loglevel error -f x11grab -draw_mouse 1 "
            f"-video_size {width}x{height} -i :1 -vframes 1 {remote_tmp}"
        )
        try:
            self._ssh_exec(f"bash -lc '{cmd}'", timeout=30)
            self.copy_from(remote_tmp, str(host_path))
            self._ssh_exec(f"rm -f {remote_tmp}", timeout=10)
            return host_path.exists() and host_path.stat().st_size > 0
        except Exception as e:
            print(f"[AVF] Screenshot failed: {e}")
            return False

    def copy_to(self, host_src: str, container_dst: str) -> None:
        """Copy file to VM via SFTP, preserving permissions."""
        import paramiko
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect("localhost", port=self.ssh_port, username=self._ssh_user,
                      password=self._ssh_password, timeout=15, look_for_keys=False)
        sftp = client.open_sftp()

        src_path = Path(host_src)
        if src_path.is_dir():
            for root, dirs, files in os.walk(src_path):
                rel_root = Path(root).relative_to(src_path)
                remote_dir = f"{container_dst}/{rel_root}" if str(rel_root) != "." else container_dst
                try:
                    sftp.mkdir(remote_dir)
                except OSError:
                    pass
                for f in files:
                    local_file = Path(root) / f
                    remote_file = f"{remote_dir}/{f}"
                    sftp.put(str(local_file), remote_file)
                    mode = local_file.stat().st_mode & 0o7777
                    sftp.chmod(remote_file, mode)
        else:
            sftp.put(str(src_path), container_dst)
            mode = src_path.stat().st_mode & 0o7777
            sftp.chmod(container_dst, mode)

        sftp.close()
        client.close()

    def copy_from(self, container_src: str, host_dst: str) -> None:
        """Copy file from VM via SFTP."""
        import paramiko
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect("localhost", port=self.ssh_port, username=self._ssh_user,
                      password=self._ssh_password, timeout=15, look_for_keys=False)
        sftp = client.open_sftp()
        sftp.get(container_src, host_dst)
        sftp.close()
        client.close()

    def _setup_mounts(self) -> None:
        """Copy mount directories to VM via SFTP."""
        mounts = getattr(self.spec, "mounts", [])
        if not mounts:
            return
        self._log(f"[AVF] Setting up {len(mounts)} mounts...")
        for mount in mounts:
            if isinstance(mount, dict):
                source = mount.get("source", "")
                target = mount.get("target", "")
            else:
                source = getattr(mount, "source", "")
                target = getattr(mount, "target", "")
            if not source or not target:
                continue
            source_path = Path(source)
            if not source_path.is_absolute():
                source_path = Path.cwd() / source_path
            if not source_path.exists():
                self._log(f"[AVF] Mount source not found: {source_path}")
                continue
            self._ssh_exec(f"sudo mkdir -p {target}", timeout=10)
            self._ssh_exec(f"sudo chown ga:ga {target}", timeout=10)
            self._log(f"[AVF] Copying {source_path} -> {target}")
            self.copy_to(str(source_path), target)
