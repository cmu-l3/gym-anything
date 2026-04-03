"""
QEMU Native Runner -- runs QEMU directly without Apptainer.

Designed for macOS and bare-metal Linux where QEMU is installed via
Homebrew or system package manager. Uses the same env.json files
as QemuApptainerRunner -- zero changes to benchmark environments.

On Apple Silicon Macs, uses qemu-system-aarch64 with HVF acceleration
and arm64 Ubuntu base images for near-native performance.

Acceleration:
    - Linux x86_64: KVM (/dev/kvm) with qemu-system-x86_64
    - macOS Intel: HVF with qemu-system-x86_64
    - macOS Apple Silicon: HVF with qemu-system-aarch64 (arm64 guest)
    - Fallback: TCG (software emulation, very slow)

Usage:
    export GYM_ANYTHING_RUNNER=qemu_native
    # or: export GYM_ANYTHING_RUNNER=qemu  (auto-selects native if Apptainer unavailable)
"""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import List, Optional

from ...specs import EnvSpec
from .qemu_apptainer import QemuApptainerRunner, _check_kvm, QEMU_CACHE, BASE_QCOW2_URL

# UEFI firmware for aarch64 (shipped with Homebrew QEMU)
_AARCH64_FIRMWARE_PATHS = [
    Path("/opt/homebrew/share/qemu/edk2-aarch64-code.fd"),  # Homebrew ARM
    Path("/usr/local/share/qemu/edk2-aarch64-code.fd"),     # Homebrew Intel
    Path("/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"),        # Debian/Ubuntu
    Path("/usr/share/AAVMF/AAVMF_CODE.fd"),                 # Fedora
]


def _find_aarch64_firmware() -> Optional[Path]:
    for p in _AARCH64_FIRMWARE_PATHS:
        if p.exists():
            return p
    return None


class QemuNativeRunner(QemuApptainerRunner):
    """QEMU runner for macOS and bare-metal Linux (no Apptainer).

    On Apple Silicon, uses qemu-system-aarch64 with HVF and arm64 Ubuntu
    for hardware-accelerated VMs. On x86 hosts, uses qemu-system-x86_64
    with KVM or HVF.
    """

    _accel_type: str   # "kvm", "hvf", or "tcg"
    _guest_arch: str   # "x86_64" or "aarch64"

    def __init__(self, spec: EnvSpec):
        super().__init__(spec)
        # Override base image path for aarch64 guests
        if self._guest_arch == "aarch64" and not self.is_windows and not self.is_android:
            self.base_qcow2 = QEMU_CACHE / "base_ubuntu_gnome_arm64.qcow2"

    def _check_prerequisites(self) -> None:
        """Check that QEMU binaries are available on PATH."""
        # Determine which binary we'll need
        if sys.platform == "darwin" and platform.machine() == "arm64":
            qemu_bin = "qemu-system-aarch64"
        else:
            qemu_bin = "qemu-system-x86_64"

        if not shutil.which(qemu_bin):
            hint = "brew install qemu" if sys.platform == "darwin" else f"apt install qemu-system"
            raise RuntimeError(f"{qemu_bin} not found on PATH. Install QEMU: {hint}")
        if not shutil.which("qemu-img"):
            hint = "brew install qemu" if sys.platform == "darwin" else "apt install qemu-utils"
            raise RuntimeError(f"qemu-img not found on PATH. Install QEMU: {hint}")

        # Check aarch64 firmware
        if sys.platform == "darwin" and platform.machine() == "arm64":
            if not _find_aarch64_firmware():
                raise RuntimeError(
                    "UEFI firmware for aarch64 not found. "
                    "It should be included with Homebrew QEMU (brew install qemu)."
                )

    def _detect_acceleration(self) -> bool:
        """Detect hardware acceleration and guest architecture.

        Sets self._accel_type and self._guest_arch.
        Returns True if hardware acceleration is available.
        """
        if sys.platform == "linux":
            self._guest_arch = "x86_64"
            if _check_kvm():
                self._accel_type = "kvm"
                return True
            self._accel_type = "tcg"
            print("[QemuNative] WARNING: /dev/kvm not available, using software emulation (very slow)")
            return False
        elif sys.platform == "darwin":
            if platform.machine() == "arm64":
                # Apple Silicon: use aarch64 guest with HVF for native speed
                self._guest_arch = "aarch64"
                self._accel_type = "hvf"
                print("[QemuNative] Apple Silicon detected: using qemu-system-aarch64 with HVF")
                return True
            else:
                # Intel Mac: use x86_64 guest with HVF
                self._guest_arch = "x86_64"
                self._accel_type = "hvf"
                return True
        else:
            self._guest_arch = "x86_64"
            self._accel_type = "tcg"
            return False

    def _build_container_prefix(self, work_dir: Path, disk: Path) -> List[str]:
        return []

    def _get_accel_args(self) -> List[str]:
        if self._accel_type in ("kvm", "hvf"):
            return ["-accel", self._accel_type]
        return []

    def _get_cpu_model(self) -> str:
        if self._accel_type in ("kvm", "hvf"):
            return "host"
        return "qemu64" if self._guest_arch == "x86_64" else "cortex-a72"

    def _get_linux_display_device(self, width: int, height: int) -> str:
        if self._guest_arch == "aarch64":
            # virtio-vga is x86-only; aarch64 uses virtio-gpu-pci
            return "virtio-gpu-pci"
        if self._accel_type == "tcg":
            return "VGA"
        return f"virtio-vga,xres={width},yres={height}"

    def _post_boot_settle_seconds(self) -> int:
        if self._accel_type == "tcg":
            return 25
        return 0

    def _build_qemu_cmd(self, disk: Path, vnc_port: int, ssh_port: int, work_dir: Path, loadvm_snapshot: Optional[str] = None) -> List[str]:
        """Build QEMU command for the detected guest architecture."""
        if self._guest_arch == "aarch64":
            return self._build_aarch64_cmd(disk, vnc_port, ssh_port, work_dir, loadvm_snapshot)
        # x86_64: delegate to parent (which calls our overridden helpers)
        return super()._build_qemu_cmd(disk, vnc_port, ssh_port, work_dir, loadvm_snapshot)

    def _build_aarch64_cmd(self, disk: Path, vnc_port: int, ssh_port: int, work_dir: Path, loadvm_snapshot: Optional[str] = None) -> List[str]:
        """Build qemu-system-aarch64 command for ARM64 guests."""
        disk_abs = str(disk.absolute())
        vnc_display = vnc_port - 5900
        width, height = self.resolution
        firmware = _find_aarch64_firmware()

        port_forwards = f"hostfwd=tcp::{ssh_port}-:22"
        if self.is_windows:
            port_forwards += f",hostfwd=tcp::{self.pyautogui_port}-:5555"

        cmd = [
            "qemu-system-aarch64",
            "-accel", self._accel_type,
            "-machine", "virt,highmem=on",
            "-cpu", "host",
            "-m", self.memory,
            "-smp", str(self.cpus),
            # UEFI firmware (required for aarch64 virt machine)
            "-bios", str(firmware),
            # Disk
            "-drive", f"file={disk_abs},format=qcow2,if=virtio",
            # Display
            "-device", "virtio-gpu-pci",
            "-vnc", f":{vnc_display},password=on",
            "-display", "none",
            "-monitor", "stdio",
            # Network
            "-device", "virtio-net-pci,netdev=net0",
            "-netdev", f"user,id=net0,{port_forwards}",
            # USB controller + input devices (aarch64 virt has no PS/2)
            "-device", "qemu-xhci",
            "-device", "usb-kbd",
            "-device", "usb-tablet",
        ]

        if loadvm_snapshot:
            cmd.extend(["-loadvm", loadvm_snapshot])

        return cmd

    def _scp_to_vm(self, port: int, host_src: str, vm_dst: str) -> bool:
        """Copy file/directory to VM via SFTP, preserving file permissions."""
        import paramiko as _paramiko

        try:
            client = _paramiko.SSHClient()
            client.set_missing_host_key_policy(_paramiko.AutoAddPolicy())
            client.connect("localhost", port=port, username=self._ssh_user,
                          password=self._ssh_password, timeout=15, look_for_keys=False)
            sftp = client.open_sftp()

            src_path = Path(host_src.rstrip("/."))
            if src_path.is_dir():
                for root, dirs, files in os.walk(src_path):
                    rel_root = Path(root).relative_to(src_path)
                    remote_dir = f"{vm_dst}/{rel_root}" if str(rel_root) != "." else vm_dst
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
                sftp.put(str(src_path), vm_dst)
                mode = src_path.stat().st_mode & 0o7777
                sftp.chmod(vm_dst, mode)

            sftp.close()
            client.close()
            return True
        except Exception as e:
            print(f"[QemuNative] SFTP copy error: {e}")
            return False

    def _run_qemu_img(self, args: List[str], bind_paths: Optional[List[str]] = None) -> subprocess.CompletedProcess:
        cmd = ["qemu-img"] + args
        return subprocess.run(cmd, capture_output=True, text=True)

    def _create_base_qcow2(self) -> None:
        """Create or download the base QCOW2 image.

        On Apple Silicon, downloads arm64 Ubuntu cloud image and provisions
        using qemu-system-aarch64 with HVF for fast native builds.
        """
        print(f"[QemuNative] Base QCOW2 image not found at: {self.base_qcow2}")

        if BASE_QCOW2_URL:
            print(f"[QemuNative] Downloading base image from {BASE_QCOW2_URL}...")
            result = subprocess.run(
                ["wget", "-q", "--show-progress", "-O", str(self.base_qcow2), BASE_QCOW2_URL],
                capture_output=False
            )
            if result.returncode == 0 and self.base_qcow2.exists():
                return
            raise RuntimeError(f"Failed to download base image from {BASE_QCOW2_URL}")

        from .build_base_qcow2_nodocker import (
            CLOUD_INIT_USER_DATA,
            get_cloud_init_meta_data,
        )

        # Append wildcard netplan config so the image works on both QEMU and vfkit.
        # QEMU uses ens3/enp0s*, vfkit uses enp0s* or different names.
        # A renderer: NetworkManager config with a match-all rule handles both.
        NETPLAN_FIXUP = """
  - |
    cat > /etc/netplan/99-wildcard-dhcp.yaml << 'NPEOF'
    network:
      version: 2
      renderer: NetworkManager
      ethernets:
        all-en:
          match:
            name: "en*"
          dhcp4: true
          dhcp6: true
    NPEOF
  - netplan generate || true
  # Install x11vnc for AVFRunner VNC support (x0vncserver not available on arm64)
  - apt-get install -y -qq x11vnc || true
  # Enable multi-arch amd64 so x86_64 .deb packages can be installed (Rosetta handles execution)
  - dpkg --add-architecture amd64
  - sed -i 's|^deb http://ports|deb [arch=arm64] http://ports|g' /etc/apt/sources.list
  - |
    cat > /etc/apt/sources.list.d/amd64.list << 'AMDEOF'
    deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse
    deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse
    deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy-security main restricted universe multiverse
    AMDEOF
  - apt-get update -qq || true
  # Install x86_64 core runtime + common GUI libs for Rosetta binary translation
  - apt-get install -y -qq libc6:amd64 libstdc++6:amd64 libx11-6:amd64 libxext6:amd64 libxrender1:amd64 libxtst6:amd64 libxi6:amd64 libxrandr2:amd64 libxcursor1:amd64 libxfixes3:amd64 libxinerama1:amd64 libxcomposite1:amd64 libxdamage1:amd64 libfreetype6:amd64 libfontconfig1:amd64 libgl1:amd64 libglx-mesa0:amd64 libglu1-mesa:amd64 libsm6:amd64 libice6:amd64 || true
"""
        # Insert before the final_message line
        cloud_init = CLOUD_INIT_USER_DATA.replace(
            "\nfinal_message:",
            NETPLAN_FIXUP + "\nfinal_message:",
        )

        QEMU_CACHE.mkdir(parents=True, exist_ok=True)

        # Select cloud image based on guest architecture
        if self._guest_arch == "aarch64":
            cloud_img = QEMU_CACHE / "ubuntu-cloud-arm64.img"
            cloud_url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-arm64.img"
        else:
            cloud_img = QEMU_CACHE / "ubuntu-cloud.img"
            cloud_url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"

        # Download cloud image
        if not cloud_img.exists():
            print(f"[QemuNative] Downloading Ubuntu cloud image ({self._guest_arch})...")
            result = subprocess.run(
                ["wget", "-q", "--show-progress", "-O", str(cloud_img), cloud_url],
                capture_output=False
            )
            if result.returncode != 0:
                raise RuntimeError(f"Failed to download cloud image from {cloud_url}")
        else:
            print(f"[QemuNative] Cloud image cached: {cloud_img}")

        work_base = QEMU_CACHE / "work"
        work_base.mkdir(parents=True, exist_ok=True)
        work_dir = Path(tempfile.mkdtemp(prefix="ga_build_base_", dir=work_base))

        try:
            # Create cloud-init ISO
            ci_dir = work_dir / "cloud-init"
            ci_dir.mkdir(exist_ok=True)
            (ci_dir / "user-data").write_text(cloud_init)
            (ci_dir / "meta-data").write_text(get_cloud_init_meta_data())

            iso_path = work_dir / "cloud-init.iso"
            iso_created = False
            for tool, args in [
                ("mkisofs", ["-o", str(iso_path), "-V", "cidata", "-J", "-r"]),
                ("genisoimage", ["-output", str(iso_path), "-volid", "cidata", "-joliet", "-rock"]),
                ("xorriso", ["-as", "mkisofs", "-o", str(iso_path), "-V", "cidata", "-J", "-r"]),
            ]:
                if shutil.which(tool):
                    result = subprocess.run(
                        [tool] + args + [str(ci_dir / "user-data"), str(ci_dir / "meta-data")],
                        capture_output=True
                    )
                    if result.returncode == 0:
                        iso_created = True
                        break
            if not iso_created:
                raise RuntimeError("No ISO tool found. Install: brew install cdrtools")

            # Create COW overlay
            overlay = work_dir / "disk.qcow2"
            result = subprocess.run(
                ["qemu-img", "create", "-f", "qcow2",
                 "-b", str(cloud_img.absolute()), "-F", "qcow2",
                 str(overlay), "50G"],
                capture_output=True, text=True,
            )
            if result.returncode != 0:
                raise RuntimeError(f"qemu-img create failed: {result.stderr}")

            # Build provisioning QEMU command
            qemu_binary = "qemu-system-aarch64" if self._guest_arch == "aarch64" else "qemu-system-x86_64"
            print(f"[QemuNative] Provisioning with {qemu_binary} ({self._accel_type})...")

            qemu_cmd = [qemu_binary]
            qemu_cmd.extend(self._get_accel_args())

            if self._guest_arch == "aarch64":
                firmware = _find_aarch64_firmware()
                qemu_cmd.extend([
                    "-machine", "virt,highmem=on",
                    "-cpu", "host",
                    "-m", "8G",
                    "-smp", "4",
                    "-bios", str(firmware),
                    "-drive", f"file={overlay},format=qcow2,if=virtio",
                    "-cdrom", str(iso_path),
                    "-device", "virtio-gpu-pci",
                    "-display", "none",
                    "-serial", "mon:stdio",
                    "-device", "virtio-net-pci,netdev=net0",
                    "-netdev", "user,id=net0",
                ])
            else:
                qemu_cmd.extend([
                    "-m", "8G",
                    "-smp", "4",
                    "-cpu", self._get_cpu_model(),
                    "-drive", f"file={overlay},format=qcow2,if=virtio",
                    "-cdrom", str(iso_path),
                    "-vga", "virtio",
                    "-display", "none",
                    "-serial", "mon:stdio",
                    "-device", "virtio-net-pci,netdev=net0",
                    "-netdev", "user,id=net0",
                    "-boot", "c",
                ])

            log_file = work_dir / "provision.log"
            start_time = time.time()
            timeout = 7200

            with open(log_file, "w") as lf:
                proc = subprocess.Popen(
                    qemu_cmd, stdin=subprocess.PIPE,
                    stdout=lf, stderr=subprocess.STDOUT,
                    cwd=str(work_dir),
                )
                print(f"[QemuNative] VM started (PID: {proc.pid}), log: {log_file}")
                try:
                    proc.wait(timeout=timeout)
                    elapsed = time.time() - start_time
                    print(f"[QemuNative] VM exited after {elapsed:.0f}s (code: {proc.returncode})")
                except subprocess.TimeoutExpired:
                    proc.terminate()
                    try:
                        proc.wait(timeout=30)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                    raise RuntimeError(f"Provisioning timed out after {timeout}s")

            backup_log = QEMU_CACHE / "last_provision.log"
            if log_file.exists():
                shutil.copy(log_file, backup_log)

            # Convert overlay to standalone
            print(f"[QemuNative] Converting to standalone image...")
            result = subprocess.run(
                ["qemu-img", "convert", "-O", "qcow2",
                 str(overlay), str(self.base_qcow2)],
                capture_output=True, text=True,
            )
            if result.returncode != 0:
                raise RuntimeError(f"qemu-img convert failed: {result.stderr}")

            size_mb = self.base_qcow2.stat().st_size / (1024 * 1024)
            print(f"[QemuNative] Base image created: {self.base_qcow2} ({size_mb:.0f} MB)")

        finally:
            shutil.rmtree(work_dir, ignore_errors=True)
