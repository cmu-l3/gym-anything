#!/usr/bin/env python3
"""
Build Android (BlissOS) base QCOW2 image using Apptainer (no Docker required).

This script creates an Android QCOW2 image with:
- BlissOS (Android-x86) - currently Android 14 (BlissOS 17)
- ADB over TCP enabled (port 5555)
- VNC fallback for display

Usage:
    python -m gym_anything.runners.build_android_qcow2_apptainer
    python -m gym_anything.runners.build_android_qcow2_apptainer --interactive
    python -m gym_anything.runners.build_android_qcow2_apptainer --iso-path /path/to/blissos.iso

Requirements:
    - Apptainer (for QEMU container)
    - KVM acceleration (/dev/kvm)
    - ~20GB disk space (ISO + QCOW2)
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Optional

QEMU_CACHE = Path(os.environ.get("GYM_ANYTHING_QEMU_CACHE", "~/.cache/gym-anything/qemu")).expanduser()
QEMU_CONTAINER = "docker://ghcr.io/dockur/windows:latest"

# BlissOS download URLs (Android-x86 based)
# BlissOS 17 = Android 14, BlissOS 16 = Android 13
BLISSOS_URLS = {
    "17": "https://sourceforge.net/projects/blissos-dev/files/Official/bleeding_edge/Bliss-v17.1.3-x86_64-OFFICIAL-gapps-20250114.iso/download",
    "16": "https://sourceforge.net/projects/blissos-dev/files/Official/bleeding_edge/Bliss-v16.9.7-x86_64-OFFICIAL-gapps-20240820.iso/download",
}


def check_apptainer() -> bool:
    """Check if Apptainer is available."""
    try:
        result = subprocess.run(["apptainer", "--version"], capture_output=True, timeout=5)
        return result.returncode == 0
    except:
        return False


def check_kvm() -> bool:
    """Check if KVM is available and accessible."""
    if not os.path.exists("/dev/kvm"):
        return False
    return os.access("/dev/kvm", os.R_OK | os.W_OK)


def ensure_sif(cache_dir: Path) -> Path:
    """Ensure the dockur/windows SIF file exists (contains QEMU)."""
    sif_path = cache_dir / "windows_dockur.sif"

    if sif_path.exists():
        print(f"[build] Using cached SIF: {sif_path}")
        return sif_path

    print(f"[build] Pulling {QEMU_CONTAINER}...")
    print("[build] This may take several minutes...")

    result = subprocess.run(
        ["apptainer", "pull", str(sif_path), QEMU_CONTAINER],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"[build] Failed to pull container: {result.stderr}")
        sys.exit(1)

    return sif_path


def download_blissos_iso(storage_dir: Path, version: str = "16") -> Optional[Path]:
    """Download BlissOS ISO."""
    iso_path = storage_dir / f"blissos-{version}.iso"

    if iso_path.exists():
        print(f"[build] Using cached ISO: {iso_path}")
        return iso_path

    if version not in BLISSOS_URLS:
        print(f"[build] Unknown BlissOS version: {version}")
        print(f"[build] Available versions: {', '.join(BLISSOS_URLS.keys())}")
        return None

    url = BLISSOS_URLS[version]
    print(f"[build] Downloading BlissOS {version} ISO...")
    print(f"[build] URL: {url}")
    print("[build] This may take 10-30 minutes depending on connection speed...")

    # Try wget first (handles SourceForge redirects better)
    try:
        result = subprocess.run(
            ["wget", "-q", "--show-progress", "-O", str(iso_path), url],
            timeout=3600,  # 1 hour timeout
        )
        if result.returncode == 0 and iso_path.exists() and iso_path.stat().st_size > 1_000_000_000:
            print(f"[build] Downloaded BlissOS ISO ({iso_path.stat().st_size / 1024 / 1024 / 1024:.1f} GB)")
            return iso_path
    except Exception as e:
        print(f"[build] wget failed: {e}")

    # Fallback to curl
    try:
        result = subprocess.run(
            ["curl", "-L", "-#", "-o", str(iso_path), url],
            timeout=3600,
        )
        if result.returncode == 0 and iso_path.exists() and iso_path.stat().st_size > 1_000_000_000:
            print(f"[build] Downloaded BlissOS ISO ({iso_path.stat().st_size / 1024 / 1024 / 1024:.1f} GB)")
            return iso_path
    except Exception as e:
        print(f"[build] curl failed: {e}")

    # Clean up failed download
    if iso_path.exists():
        iso_path.unlink()

    print("[build] ERROR: Failed to download BlissOS ISO")
    print("[build] Please download manually from:")
    print(f"  https://blissos.org/")
    print(f"  Save to: {iso_path}")
    return None


def create_qcow2_disk(sif_path: Path, disk_path: Path, size: str = "32G") -> None:
    """Create a new QCOW2 disk."""
    if disk_path.exists():
        print(f"[build] Disk already exists: {disk_path}")
        return

    print(f"[build] Creating QCOW2 disk ({size})...")
    result = subprocess.run(
        [
            "apptainer", "exec",
            "--contain",
            "--bind", f"{disk_path.parent}:{disk_path.parent}",
            str(sif_path),
            "qemu-img", "create", "-f", "qcow2", str(disk_path), size
        ],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"[build] Failed to create disk: {result.stderr}")
        sys.exit(1)


def find_free_port(start: int = 5950) -> int:
    """Find a free port starting from the given port."""
    import socket
    for port in range(start, start + 100):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('localhost', port))
                return port
        except OSError:
            continue
    return start


def run_android_install(
    sif_path: Path,
    iso_path: Path,
    disk_path: Path,
    memory: str = "4G",
    cpus: int = 4,
    interactive: bool = False
) -> bool:
    """Run QEMU to install BlissOS.

    BlissOS uses a GRUB-based installer that requires user interaction.
    This function boots the live ISO and lets the user complete installation.
    """
    vnc_port = find_free_port(5950)
    vnc_display = vnc_port - 5900

    print()
    print("=" * 60)
    print("Starting BlissOS Installation")
    print("=" * 60)
    print(f"VNC Port: {vnc_port}")
    print(f"Connect with: vncviewer localhost:{vnc_port}")
    print()
    print("INSTALLATION STEPS:")
    print("1. Connect via VNC to see the BlissOS boot menu")
    print("2. Select 'Installation - Install BlissOS to harddisk'")
    print("3. Choose 'Create/Modify partitions' -> Select GPT")
    print("4. Create partition: New -> (enter size) -> Write -> Quit")
    print("5. Select the partition (vda1) -> ext4 -> Yes (format)")
    print("6. Install GRUB bootloader -> Yes")
    print("7. Make /system read-write -> Yes")
    print("8. When complete, select 'Reboot' (remove ISO manually)")
    print()
    print("After installation, press Ctrl+C to stop the VM.")
    print("=" * 60)
    print()

    # Calculate VNC display number from port (port 5900 = display :0)
    width, height = 1280, 800

    # Build QEMU command
    qemu_cmd = [
        "qemu-system-x86_64",
        "-accel", "kvm",
        "-m", memory,
        "-smp", str(cpus),
        "-cpu", "host",
        # Disk with virtio
        "-drive", f"file={disk_path},format=qcow2,if=virtio",
        # BlissOS installation ISO
        "-cdrom", str(iso_path),
        # Display
        "-device", f"virtio-vga,xres={width},yres={height}",
        "-vnc", f":{vnc_display}",
        "-display", "none",
        "-monitor", "stdio",
        # Network with virtio
        "-device", "virtio-net-pci,netdev=net0",
        "-netdev", "user,id=net0",
        # USB for input
        "-usb",
        "-device", "usb-kbd",
        "-device", "usb-tablet",
        # Boot from CD
        "-boot", "d",
    ]

    # Build bind mounts for Apptainer
    bind_mounts = [
        "--bind", "/dev/kvm",
        "--bind", f"{disk_path.parent}:{disk_path.parent}",
        "--bind", f"{iso_path.parent}:{iso_path.parent}",
    ]

    # Run QEMU inside container
    full_cmd = [
        "apptainer", "exec",
        "--contain", "--writable-tmpfs",
    ] + bind_mounts + [
        str(sif_path)
    ] + qemu_cmd

    print(f"[build] Starting QEMU...")

    process = subprocess.Popen(
        full_cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

    print(f"[build] QEMU running (PID: {process.pid})")
    print(f"[build] Connect via VNC: vncviewer localhost:{vnc_port}")
    print()
    print("[build] Follow the installation steps above.")
    print("[build] Press Ctrl+C when installation is complete.")

    try:
        process.wait()
    except KeyboardInterrupt:
        print("\n[build] Stopping QEMU...")
        process.terminate()
        time.sleep(2)
        process.kill()

    return True


def run_post_install_boot(
    sif_path: Path,
    disk_path: Path,
    memory: str = "4G",
    cpus: int = 4,
    adb_port: int = 5555
) -> bool:
    """Boot the installed BlissOS and configure ADB over TCP."""
    vnc_port = find_free_port(5950)
    vnc_display = vnc_port - 5900
    host_adb_port = find_free_port(15555)

    print()
    print("=" * 60)
    print("Post-Installation Boot")
    print("=" * 60)
    print(f"VNC Port: {vnc_port}")
    print(f"ADB Port: {host_adb_port} (forwarded to guest port {adb_port})")
    print()
    print("SETUP STEPS:")
    print("1. Wait for Android to boot fully")
    print("2. Complete any first-boot wizard")
    print("3. Enable Developer Options:")
    print("   Settings -> About -> Tap 'Build number' 7 times")
    print("4. Enable ADB over network:")
    print("   Settings -> Developer options -> ADB over network -> ON")
    print("5. Test ADB connection:")
    print(f"   adb connect localhost:{host_adb_port}")
    print()
    print("Press Ctrl+C when setup is complete.")
    print("=" * 60)
    print()

    width, height = 1280, 800

    qemu_cmd = [
        "qemu-system-x86_64",
        "-accel", "kvm",
        "-m", memory,
        "-smp", str(cpus),
        "-cpu", "host",
        "-drive", f"file={disk_path},format=qcow2,if=virtio",
        "-device", f"virtio-vga,xres={width},yres={height}",
        "-vnc", f":{vnc_display}",
        "-display", "none",
        "-monitor", "stdio",
        "-device", "virtio-net-pci,netdev=net0",
        "-netdev", f"user,id=net0,hostfwd=tcp::{host_adb_port}-:{adb_port}",
        "-usb",
        "-device", "usb-kbd",
        "-device", "usb-tablet",
        "-boot", "c",
    ]

    bind_mounts = [
        "--bind", "/dev/kvm",
        "--bind", f"{disk_path.parent}:{disk_path.parent}",
    ]

    full_cmd = [
        "apptainer", "exec",
        "--contain", "--writable-tmpfs",
    ] + bind_mounts + [
        str(sif_path)
    ] + qemu_cmd

    print(f"[build] Starting QEMU...")

    process = subprocess.Popen(
        full_cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

    print(f"[build] QEMU running (PID: {process.pid})")
    print(f"[build] Connect via VNC: vncviewer localhost:{vnc_port}")
    print(f"[build] Test ADB: adb connect localhost:{host_adb_port}")

    try:
        process.wait()
    except KeyboardInterrupt:
        print("\n[build] Stopping QEMU...")
        process.terminate()
        time.sleep(2)
        process.kill()

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Build Android (BlissOS) QCOW2 for gym-anything using Apptainer"
    )
    parser.add_argument(
        "--output", "-o",
        default=str(QEMU_CACHE / "base_android_14.qcow2"),
        help="Output path for Android QCOW2"
    )
    parser.add_argument(
        "--version", default="16",
        choices=["16", "17"],
        help="BlissOS version (16=Android 13, 17=Android 14)"
    )
    parser.add_argument(
        "--memory", default="4G",
        help="VM memory"
    )
    parser.add_argument(
        "--cpus", type=int, default=4,
        help="VM CPUs"
    )
    parser.add_argument(
        "--disk-size", default="32G",
        help="Disk size"
    )
    parser.add_argument(
        "--iso-path",
        help="Path to existing BlissOS ISO (skip download)"
    )
    parser.add_argument(
        "--skip-install", action="store_true",
        help="Skip installation (for post-install setup only)"
    )
    parser.add_argument(
        "--interactive", action="store_true",
        help="Interactive mode (for debugging)"
    )

    args = parser.parse_args()
    output = Path(args.output)

    # Map version to Android version for output filename
    android_version = "14" if args.version == "17" else "13"
    if "android_14" in str(output) and args.version == "16":
        output = output.parent / "base_android_13.qcow2"

    print("=" * 60)
    print("GYM-ANYTHING: Build Android QCOW2 (Apptainer)")
    print("=" * 60)
    print(f"BlissOS version: {args.version} (Android {android_version})")

    # Check prerequisites
    if not check_apptainer():
        print("ERROR: Apptainer not found")
        sys.exit(1)
    print("[build] Apptainer available")

    if not check_kvm():
        print("ERROR: KVM not available or not accessible")
        print("Ensure /dev/kvm exists and is readable/writable")
        sys.exit(1)
    print("[build] KVM available")

    # Setup directories
    QEMU_CACHE.mkdir(parents=True, exist_ok=True)
    work_dir = QEMU_CACHE / "work" / "android_build"
    work_dir.mkdir(parents=True, exist_ok=True)

    storage_dir = work_dir / "storage"
    storage_dir.mkdir(exist_ok=True)

    # Get or pull container
    sif_path = ensure_sif(QEMU_CACHE)

    # Get or download ISO
    if args.iso_path:
        iso_path = Path(args.iso_path).resolve()
        if not iso_path.exists():
            print(f"ERROR: ISO not found: {iso_path}")
            sys.exit(1)
    else:
        iso_path = download_blissos_iso(storage_dir, args.version)
        if not iso_path:
            print("ERROR: Failed to obtain BlissOS ISO")
            sys.exit(1)

    print(f"[build] ISO: {iso_path}")

    # Create disk
    disk_path = storage_dir / "android.qcow2"
    create_qcow2_disk(sif_path, disk_path, args.disk_size)

    if not args.skip_install:
        # Run installation
        print()
        print("[build] Starting installation...")
        run_android_install(
            sif_path,
            iso_path,
            disk_path,
            memory=args.memory,
            cpus=args.cpus,
            interactive=args.interactive
        )

    # Verify disk has content before continuing
    disk_size = disk_path.stat().st_size
    if disk_size < 500_000_000:  # Less than 500MB means installation didn't happen
        print(f"[build] ERROR: Disk is only {disk_size / 1024 / 1024:.1f} MB - installation may have failed")
        print("[build] Run again without --skip-install to complete installation")
        sys.exit(1)

    print(f"[build] Installation complete, disk size: {disk_size / 1024 / 1024 / 1024:.1f} GB")

    # Run post-install boot
    print()
    print("[build] Running post-install boot for ADB setup...")
    run_post_install_boot(sif_path, disk_path, args.memory, args.cpus)

    # Copy to final location
    print()
    print(f"[build] Copying to {output}...")
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(disk_path, output)

    print()
    print("=" * 60)
    print("BUILD COMPLETE")
    print("=" * 60)
    print(f"Output: {output}")
    print()
    print("ADB Connection:")
    print("  adb connect localhost:<adb_port>")
    print()
    print("Test with:")
    print("  python -m gym_anything.runners.build_android_qcow2_apptainer --skip-install")


if __name__ == "__main__":
    main()
