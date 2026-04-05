#!/usr/bin/env python3
"""
Build Windows base QCOW2 image for gym-anything using dockur/windows approach.

This script creates a Windows 11 QCOW2 image with:
- Windows 11 Pro (or configurable version)
- OpenSSH Server enabled (for SSH access like Ubuntu)
- Python + pyautogui installed (for GUI automation)
- RDP enabled (for remote desktop)
- VNC via QEMU (like Ubuntu)

The dockur/windows container handles:
1. Downloading Windows ISO automatically
2. Unattended installation with autounattend.xml
3. Post-installation configuration

We extract the resulting QCOW2 for use with QemuApptainerRunner.

Usage:
    python -m gym_anything.runners.build_windows_qcow2
    python -m gym_anything.runners.build_windows_qcow2 --version win10
    python -m gym_anything.runners.build_windows_qcow2 --timeout 7200

Requirements:
    - Docker (for dockur/windows bootstrapping)
    - KVM acceleration (/dev/kvm)
    - ~64GB disk space
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

QEMU_CACHE = Path(os.environ.get("GYM_ANYTHING_QEMU_CACHE", "~/.cache/gym-anything/qemu")).expanduser()
DOCKUR_IMAGE = "ghcr.io/dockur/windows:latest"

# Post-installation script to configure Windows for automation
# This is placed in /oem and runs as install.bat during Windows setup
WINDOWS_SETUP_SCRIPT = r'''@echo off
REM Gym-Anything Windows Configuration Script
REM This runs during Windows first-boot setup

echo ============================================
echo GYM-ANYTHING WINDOWS SETUP
echo ============================================

REM Enable OpenSSH Server
echo Installing OpenSSH Server...
powershell -Command "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"
powershell -Command "Start-Service sshd"
powershell -Command "Set-Service -Name sshd -StartupType Automatic"

REM Configure SSH to allow password auth
powershell -Command "$config = Get-Content 'C:\ProgramData\ssh\sshd_config'; $config = $config -replace '#PasswordAuthentication yes','PasswordAuthentication yes'; Set-Content 'C:\ProgramData\ssh\sshd_config' $config"
powershell -Command "Restart-Service sshd"

REM Create .ssh directory and set permissions
mkdir "C:\Users\Docker\.ssh" 2>nul

REM Install Python (for pyautogui)
echo Installing Python...
REM Use winget if available (Windows 11)
winget install --silent --accept-package-agreements --accept-source-agreements Python.Python.3.11 2>nul
if %ERRORLEVEL% NEQ 0 (
    REM Fallback: download Python installer
    curl -o python_installer.exe https://www.python.org/ftp/python/3.11.7/python-3.11.7-amd64.exe
    python_installer.exe /quiet InstallAllUsers=1 PrependPath=1 Include_pip=1
    del python_installer.exe
)

REM Wait for Python to be available in PATH
timeout /t 5 /nobreak

REM Install pyautogui and dependencies
echo Installing pyautogui...
python -m pip install --upgrade pip
python -m pip install pyautogui pillow opencv-python

REM Disable Windows Defender real-time protection (for performance)
powershell -Command "Set-MpPreference -DisableRealtimeMonitoring $true" 2>nul

REM Disable Windows Update (for reproducibility)
powershell -Command "Stop-Service wuauserv; Set-Service -Name wuauserv -StartupType Disabled" 2>nul

REM Disable UAC prompts
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 0 /f

REM Enable auto-logon for Docker user
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d Docker /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d admin /f

REM Disable lock screen
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v NoLockScreen /t REG_DWORD /d 1 /f

REM Disable screen saver
reg add "HKCU\Control Panel\Desktop" /v ScreenSaveActive /t REG_SZ /d 0 /f

REM Set display to never turn off
powershell -Command "powercfg /change monitor-timeout-ac 0; powercfg /change monitor-timeout-dc 0"

REM Create marker file
echo PROVISIONING COMPLETE > C:\Users\Docker\Desktop\provisioning_complete.txt

echo ============================================
echo GYM-ANYTHING WINDOWS SETUP COMPLETE
echo ============================================
echo User: Docker
echo Password: admin
echo SSH: Port 22
echo RDP: Port 3389
echo ============================================
'''

# SSH key setup script (runs after first boot)
SSH_KEY_SETUP = r'''@echo off
REM Add SSH key for passwordless auth
mkdir "C:\Users\Docker\.ssh" 2>nul
echo ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICKDhcvuOFDk9Qi2iJD66SVhla3xUcUQQjvm1ablzi2l gym-anything-qemu > "C:\Users\Docker\.ssh\authorized_keys"
icacls "C:\Users\Docker\.ssh\authorized_keys" /inheritance:r /grant "Docker:R" /grant "SYSTEM:F" /grant "Administrators:F"
'''


def check_docker():
    """Check if Docker is available."""
    try:
        result = subprocess.run(["docker", "--version"], capture_output=True, timeout=5)
        return result.returncode == 0
    except:
        return False


def check_kvm():
    """Check if KVM is available."""
    return os.path.exists("/dev/kvm") and os.access("/dev/kvm", os.R_OK | os.W_OK)


def create_oem_scripts(work_dir: Path) -> Path:
    """Create OEM scripts directory for Windows setup."""
    oem_dir = work_dir / "oem"
    oem_dir.mkdir(exist_ok=True)

    # Main install script
    (oem_dir / "install.bat").write_text(WINDOWS_SETUP_SCRIPT)

    # SSH key setup (optional, for later use)
    (oem_dir / "setup_ssh_key.bat").write_text(SSH_KEY_SETUP)

    print(f"[build] Created OEM scripts in {oem_dir}")
    return oem_dir


def run_windows_installation(
    work_dir: Path,
    version: str = "win11",
    timeout: int = 7200,
    memory: str = "8G",
    cpus: int = 4
):
    """Run Windows installation using dockur/windows container."""
    print(f"[build] Starting Windows {version} installation...")
    print(f"[build] This will download Windows ISO and perform unattended install")
    print(f"[build] Expected time: 30-60 minutes")

    storage_dir = work_dir / "storage"
    storage_dir.mkdir(exist_ok=True)

    oem_dir = create_oem_scripts(work_dir)

    # Docker command to run dockur/windows
    cmd = [
        "docker", "run", "--rm",
        "--name", "ga_windows_build",
        "--device", "/dev/kvm" if check_kvm() else "/dev/null",
        "-e", f"VERSION={version}",
        "-e", f"RAM_SIZE={memory}",
        "-e", f"CPU_CORES={cpus}",
        "-e", "DISK_SIZE=64G",
        "-e", "USERNAME=Docker",
        "-e", "PASSWORD=admin",
        "-v", f"{storage_dir}:/storage",
        "-v", f"{oem_dir}:/oem",
        "-p", "8006:8006",  # VNC web interface
        "-p", "3389:3389",  # RDP
        "--privileged" if check_kvm() else "",
        DOCKUR_IMAGE,
    ]

    # Remove empty strings
    cmd = [c for c in cmd if c]

    print(f"[build] Running: {' '.join(cmd)}")
    print(f"[build] Monitor progress at: http://localhost:8006")

    # Run with timeout
    try:
        result = subprocess.run(
            cmd,
            timeout=timeout,
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            print(f"[build] Docker container failed: {result.stderr[:500]}")
            return False

        print(f"[build] Windows installation completed!")
        return True

    except subprocess.TimeoutExpired:
        print(f"[build] Timeout after {timeout}s")
        # Stop the container
        subprocess.run(["docker", "stop", "ga_windows_build"], capture_output=True)
        return False


def extract_qcow2(work_dir: Path, output: Path):
    """Extract/convert the Windows disk to QCOW2 format."""
    storage_dir = work_dir / "storage"

    # dockur/windows creates data.img in storage directory
    source_disk = storage_dir / "data.img"

    if not source_disk.exists():
        # Try alternative names
        for name in ["windows.img", "disk.img", "data.qcow2"]:
            alt = storage_dir / name
            if alt.exists():
                source_disk = alt
                break

    if not source_disk.exists():
        print(f"[build] ERROR: No disk image found in {storage_dir}")
        print(f"[build] Contents: {list(storage_dir.iterdir())}")
        return False

    print(f"[build] Found disk image: {source_disk}")
    print(f"[build] Converting to QCOW2...")

    # Convert to QCOW2 format
    result = subprocess.run([
        "qemu-img", "convert", "-O", "qcow2",
        str(source_disk), str(output)
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print(f"[build] qemu-img convert failed: {result.stderr}")

        # Try copying directly if already qcow2
        if source_disk.suffix == ".qcow2":
            shutil.copy(source_disk, output)
            print(f"[build] Copied existing QCOW2")
            return True
        return False

    size_mb = output.stat().st_size / (1024 * 1024)
    print(f"[build] Created: {output} ({size_mb:.0f} MB)")
    return True


def main():
    parser = argparse.ArgumentParser(description="Build Windows QCOW2 for gym-anything")
    parser.add_argument("--output", "-o",
                       default=str(QEMU_CACHE / "base_windows_11.qcow2"),
                       help="Output path for Windows QCOW2")
    parser.add_argument("--version", default="win11",
                       choices=["win11", "win10", "ltsc10", "2022", "2019", "win7"],
                       help="Windows version (default: win11)")
    parser.add_argument("--timeout", type=int, default=7200,
                       help="Installation timeout in seconds (default: 7200 = 2 hours)")
    parser.add_argument("--memory", default="8G",
                       help="VM memory for installation (default: 8G)")
    parser.add_argument("--cpus", type=int, default=4,
                       help="VM CPUs for installation (default: 4)")
    parser.add_argument("--keep-work-dir", action="store_true",
                       help="Keep working directory for debugging")

    args = parser.parse_args()
    output = Path(args.output)

    print("=" * 60)
    print("GYM-ANYTHING: Build Windows QCOW2 Image")
    print("=" * 60)

    # Check prerequisites
    if not check_docker():
        print("ERROR: Docker not found")
        print("Docker is required to bootstrap Windows installation")
        sys.exit(1)
    print("[build] ✓ Docker available")

    if check_kvm():
        print("[build] ✓ KVM available (fast installation)")
    else:
        print("[build] ⚠ KVM not available (installation will be slow)")

    # Pull dockur/windows image
    print(f"[build] Pulling {DOCKUR_IMAGE}...")
    subprocess.run(["docker", "pull", DOCKUR_IMAGE], capture_output=True)

    # Setup
    QEMU_CACHE.mkdir(parents=True, exist_ok=True)
    output.parent.mkdir(parents=True, exist_ok=True)

    # Create working directory
    work_base = QEMU_CACHE / "work"
    work_base.mkdir(parents=True, exist_ok=True)
    work_dir = Path(tempfile.mkdtemp(prefix="ga_build_windows_", dir=work_base))
    print(f"[build] Work directory: {work_dir}")

    try:
        # Run Windows installation
        if not run_windows_installation(
            work_dir,
            version=args.version,
            timeout=args.timeout,
            memory=args.memory,
            cpus=args.cpus
        ):
            print("[build] Windows installation failed")
            sys.exit(1)

        # Extract QCOW2
        if not extract_qcow2(work_dir, output):
            print("[build] Failed to extract QCOW2")
            sys.exit(1)

        print()
        print("=" * 60)
        print("SUCCESS!")
        print("=" * 60)
        print(f"Windows image: {output}")
        print()
        print("Default credentials:")
        print("  User: Docker")
        print("  Password: admin")
        print("  SSH: Port 22 (after OpenSSH setup)")
        print("  RDP: Port 3389")
        print()
        print("You can now run Windows environments with:")
        print("  export GYM_ANYTHING_RUNNER=qemu")
        print("  python -m agents.evaluation.run_single --env_dir benchmarks/cua_world/environments/windows_notepad_env --task ...")
        print("=" * 60)

    finally:
        if not args.keep_work_dir:
            shutil.rmtree(work_dir, ignore_errors=True)
        else:
            print(f"[build] Kept work directory: {work_dir}")


if __name__ == "__main__":
    main()
