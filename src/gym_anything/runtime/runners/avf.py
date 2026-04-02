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
        self.ssh_port: int = 22  # Direct SSH to guest IP (NAT mode)
        self._guest_ip: Optional[str] = None
        self._mac_address: Optional[str] = None

        # Base image (raw, converted from arm64 QCOW2)
        AVF_CACHE.mkdir(parents=True, exist_ok=True)
        self._base_raw = AVF_CACHE / "base_ubuntu_gnome_arm64.raw"

        # State
        self._running = False
        self._vfkit_process: Optional[subprocess.Popen] = None
        self._work_dir: Optional[Path] = None
        self._instance_raw: Optional[Path] = None
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._consecutive_ssh_failures = 0
        self._max_consecutive_ssh_failures = 5

        # Env hash for checkpoints
        from ...config.presets import is_windows_preset, is_android_preset
        self.is_windows = False
        self.is_android = False
        self.env_hash = _get_env_hash(spec)

        # Recording dir
        self._artifacts_root = os.path.abspath(spec.recording.output_dir)

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

    def start(self, seed: Optional[int] = None) -> None:
        print(f"[AVF] Instance: {self.instance_name}")

        # Ensure base image
        self._ensure_base_raw()

        # Create work directory
        work_base = AVF_CACHE / "work"
        work_base.mkdir(parents=True, exist_ok=True)
        self._work_dir = Path(tempfile.mkdtemp(prefix=f"ga_avf_{self.instance_id}_", dir=work_base))

        # Create COW overlay using APFS clonefile (instant, no extra disk space)
        self._instance_raw = self._work_dir / "disk.raw"
        subprocess.run(["cp", "-c", str(self._base_raw), str(self._instance_raw)],
                       check=True, capture_output=True)
        print(f"[AVF] APFS COW overlay created")

        # Generate a unique MAC address for this instance
        h = uuid.uuid4().hex
        self._mac_address = f"52:54:00:{h[:2]}:{h[2:4]}:{h[4:6]}"

        # EFI variable store
        efi_store = self._work_dir / "efi-variable-store"

        # Build vfkit command — using NAT networking (macOS handles DHCP)
        vfkit_cmd = [
            "vfkit",
            "--cpus", str(self.cpus),
            "--memory", str(self.memory),
            "--bootloader", f"efi,variable-store={efi_store},create",
            "--device", f"virtio-blk,path={self._instance_raw}",
            "--device", f"virtio-net,nat,mac={self._mac_address}",
            "--device", "virtio-rng",
            # Rosetta for x86_64 binary translation
            "--device", "rosetta,mountTag=rosetta-share",
        ]

        # Start vfkit
        vfkit_log = self._work_dir / "vfkit.log"
        print(f"[AVF] Starting vfkit VM (NAT mode)...")
        with open(vfkit_log, "w") as lf:
            self._vfkit_process = subprocess.Popen(
                vfkit_cmd,
                stdout=lf, stderr=subprocess.STDOUT,
                preexec_fn=os.setsid,
            )

        # Discover guest IP from macOS DHCP leases
        self._guest_ip = self._discover_guest_ip(timeout=180)
        if not self._guest_ip:
            self._dump_logs()
            self.stop()
            raise RuntimeError("VM failed to get network (no DHCP lease found)")

        print(f"[AVF] Guest IP: {self._guest_ip}")

        # Wait for SSH to be responsive
        if not self._wait_for_ssh(timeout=120):
            self._dump_logs()
            self.stop()
            raise RuntimeError("VM failed to boot (SSH not available)")

        print(f"[AVF] SSH available at {self._guest_ip}:22")

        # Set up Rosetta in the guest
        self._setup_rosetta()

        # Wait for desktop
        self._wait_for_desktop(timeout=120)

        # Set up mounts
        mounts = getattr(self.spec, "mounts", [])
        if mounts:
            self._setup_mounts()

        self._running = True
        print(f"[AVF] VM ready!")

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

    def _wait_for_ssh(self, timeout: float = 120) -> bool:
        """Poll until SSH is actually responsive at the guest IP."""
        import paramiko
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                client = paramiko.SSHClient()
                client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                client.connect(self._guest_ip, port=22, username=self._ssh_user,
                              password=self._ssh_password, timeout=10, look_for_keys=False)
                client.close()
                return True
            except Exception:
                time.sleep(3)
        return False

    def _setup_rosetta(self) -> None:
        """Mount Rosetta and register binfmt_misc in the guest."""
        print("[AVF] Setting up Rosetta for x86_64 translation...")
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

            # Verify
            result = self._ssh_exec("file /mnt/rosetta/rosetta 2>&1", timeout=10, capture=True)
            if "Mach-O" in result or "executable" in result:
                print("[AVF] Rosetta mounted and registered for x86_64 translation")
            else:
                print(f"[AVF] WARNING: Rosetta may not be available: {result[:100]}")
        except Exception as e:
            print(f"[AVF] WARNING: Rosetta setup failed: {e}")
            print("[AVF] x86_64 binaries will not be translated (arm64-native packages still work)")

    def _wait_for_desktop(self, timeout: float = 120) -> bool:
        """Wait for GNOME desktop to be ready."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                result = self._ssh_exec(
                    "DISPLAY=:1 xdotool getdisplaygeometry 2>&1",
                    timeout=10, capture=True
                )
                if result and any(c.isdigit() for c in result):
                    print(f"[AVF] Desktop ready: {result.strip()}")
                    return True
            except Exception:
                pass
            time.sleep(3)
        print("[AVF] WARNING: Desktop not detected within timeout")
        return False

    def stop(self) -> None:
        self._stop_event.set()
        # Kill vfkit
        if self._vfkit_process:
            try:
                os.killpg(os.getpgid(self._vfkit_process.pid), signal.SIGTERM)
                self._vfkit_process.wait(timeout=10)
            except Exception:
                try:
                    os.killpg(os.getpgid(self._vfkit_process.pid), signal.SIGKILL)
                except Exception:
                    pass
            self._vfkit_process = None

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
        """Execute command in VM via SSH."""
        import paramiko
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(self._guest_ip, port=22, username=self._ssh_user,
                      password=self._ssh_password, timeout=15, look_for_keys=False)
        _, stdout, stderr = client.exec_command(cmd, timeout=timeout)
        out = stdout.read().decode()
        err = stderr.read().decode()
        exit_code = stdout.channel.recv_exit_status()
        client.close()
        if capture:
            return out
        if exit_code != 0:
            print(f"[AVF] SSH cmd failed (exit {exit_code}): {err[:200]}")
        return out

    # ---- BaseRunner interface ----

    def exec(self, cmd: str, env: Optional[Dict[str, str]] = None,
             user: Optional[str] = None, use_pty: bool = True, timeout: int = 600) -> int:
        """Execute a command in the VM."""
        full_cmd = f"sudo -E {cmd}" if user is None or user == "root" else cmd
        try:
            import paramiko
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect("localhost", port=self.ssh_port, username=self._ssh_user,
                          password=self._ssh_password, timeout=15, look_for_keys=False)
            _, stdout, stderr = client.exec_command(full_cmd, timeout=timeout, get_pty=use_pty)
            exit_code = stdout.channel.recv_exit_status()
            client.close()
            return exit_code
        except Exception as e:
            print(f"[AVF] exec failed: {e}")
            return 1

    def exec_capture(self, cmd: str) -> str:
        return self._ssh_exec(f"sudo -E {cmd}", capture=True)

    def run_reset(self, reset_script: str, seed: Optional[int] = None) -> None:
        self.exec(f"bash -lc {reset_script}")

    def run_task_init(self, init_script: str) -> None:
        self.exec(f"bash -lc {init_script}")

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
        """Capture screenshot via ffmpeg x11grab over SSH."""
        host_path = Path(host_path)
        host_path.parent.mkdir(parents=True, exist_ok=True)

        remote_tmp = f"/tmp/ga_screenshot_{uuid.uuid4().hex[:8]}.png"
        width, height = self.resolution
        cmd = (
            f"DISPLAY=:1 ffmpeg -nostdin -y -loglevel error -f x11grab -draw_mouse 1 "
            f"-video_size {width}x{height} -i :1 -vframes 1 {remote_tmp}"
        )
        try:
            result = self._ssh_exec(f"bash -lc '{cmd}'", timeout=30, capture=True)
            # Copy file from VM
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
        client.connect(self._guest_ip, port=22, username=self._ssh_user,
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
        client.connect(self._guest_ip, port=22, username=self._ssh_user,
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
        print(f"[AVF] Setting up {len(mounts)} mounts...")
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
                print(f"[AVF] Mount source not found: {source_path}")
                continue
            self._ssh_exec(f"sudo mkdir -p {target}", timeout=10)
            self._ssh_exec(f"sudo chown ga:ga {target}", timeout=10)
            print(f"[AVF] Copying {source_path} -> {target}")
            self.copy_to(str(source_path), target)
