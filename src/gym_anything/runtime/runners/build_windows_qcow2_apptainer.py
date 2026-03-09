#!/usr/bin/env python3
"""
Build Windows base QCOW2 image using Apptainer (no Docker required).

This script creates a Windows 11 QCOW2 image with:
- Windows 11 Pro (or configurable version)
- OpenSSH Server enabled (for SSH access like Ubuntu)
- Python + pyautogui installed (for GUI automation)
- Auto-login configured

Unlike build_windows_qcow2.py, this version:
- Uses Apptainer instead of Docker
- Runs QEMU directly (bypassing root requirements)
- Downloads Windows ISO from Microsoft directly

Usage:
    python -m gym_anything.runners.build_windows_qcow2_apptainer
    python -m gym_anything.runners.build_windows_qcow2_apptainer --interactive

Requirements:
    - Apptainer (for QEMU container)
    - KVM acceleration (/dev/kvm)
    - ~80GB disk space (ISO + QCOW2)
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
WINDOWS_CONTAINER = "docker://ghcr.io/dockur/windows:latest"
VIRTIO_WIN_URL = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

# Autounattend.xml for unattended Windows 11 installation with virtio drivers
AUTOUNATTEND_XML = '''<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <SetupUILanguage>
                <UILanguage>en-US</UILanguage>
            </SetupUILanguage>
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-PnpCustomizationsWinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <DriverPaths>
                <!-- Drive E: (typical for second CD-ROM in WinPE) -->
                <PathAndCredentials wcm:action="add" wcm:keyValue="1">
                    <Path>E:\\viostor\\w11\\amd64</Path>
                </PathAndCredentials>
                <PathAndCredentials wcm:action="add" wcm:keyValue="2">
                    <Path>E:\\vioscsi\\w11\\amd64</Path>
                </PathAndCredentials>
                <PathAndCredentials wcm:action="add" wcm:keyValue="3">
                    <Path>E:\\NetKVM\\w11\\amd64</Path>
                </PathAndCredentials>
                <!-- Drive F: (if autounattend ISO takes E:) -->
                <PathAndCredentials wcm:action="add" wcm:keyValue="4">
                    <Path>F:\\viostor\\w11\\amd64</Path>
                </PathAndCredentials>
                <PathAndCredentials wcm:action="add" wcm:keyValue="5">
                    <Path>F:\\vioscsi\\w11\\amd64</Path>
                </PathAndCredentials>
                <PathAndCredentials wcm:action="add" wcm:keyValue="6">
                    <Path>F:\\NetKVM\\w11\\amd64</Path>
                </PathAndCredentials>
                <!-- Drive D: fallback -->
                <PathAndCredentials wcm:action="add" wcm:keyValue="7">
                    <Path>D:\\viostor\\w11\\amd64</Path>
                </PathAndCredentials>
                <PathAndCredentials wcm:action="add" wcm:keyValue="8">
                    <Path>D:\\vioscsi\\w11\\amd64</Path>
                </PathAndCredentials>
            </DriverPaths>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <DiskConfiguration>
                <Disk>
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <CreatePartition>
                            <Order>1</Order>
                            <Type>EFI</Type>
                            <Size>300</Size>
                        </CreatePartition>
                        <CreatePartition>
                            <Order>2</Order>
                            <Type>MSR</Type>
                            <Size>16</Size>
                        </CreatePartition>
                        <CreatePartition>
                            <Order>3</Order>
                            <Type>Primary</Type>
                            <Extend>true</Extend>
                        </CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition>
                            <Order>1</Order>
                            <PartitionID>1</PartitionID>
                            <Format>FAT32</Format>
                            <Label>EFI</Label>
                        </ModifyPartition>
                        <ModifyPartition>
                            <Order>2</Order>
                            <PartitionID>3</PartitionID>
                            <Format>NTFS</Format>
                            <Label>Windows</Label>
                            <Letter>C</Letter>
                        </ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>3</PartitionID>
                    </InstallTo>
                </OSImage>
            </ImageInstall>
            <UserData>
                <AcceptEula>true</AcceptEula>
                <ProductKey>
                    <WillShowUI>OnError</WillShowUI>
                </ProductKey>
            </UserData>
        </component>
    </settings>
    <settings pass="specialize">
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <RunSynchronous>
                <RunSynchronousCommand>
                    <Order>1</Order>
                    <Path>cmd /c reg add "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <ComputerName>WIN11-GA</ComputerName>
            <TimeZone>UTC</TimeZone>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount>
                        <Name>ga</Name>
                        <Group>Administrators</Group>
                        <Password>
                            <Value>password123</Value>
                            <PlainText>true</PlainText>
                        </Password>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
            <AutoLogon>
                <Enabled>true</Enabled>
                <Username>ga</Username>
                <Password>
                    <Value>password123</Value>
                    <PlainText>true</PlainText>
                </Password>
                <LogonCount>9999</LogonCount>
            </AutoLogon>
            <FirstLogonCommands>
                <SynchronousCommand>
                    <Order>1</Order>
                    <CommandLine>powershell -ExecutionPolicy Bypass -Command "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"</CommandLine>
                    <Description>Install OpenSSH Server</Description>
                </SynchronousCommand>
                <SynchronousCommand>
                    <Order>2</Order>
                    <CommandLine>powershell -ExecutionPolicy Bypass -Command "Start-Service sshd; Set-Service -Name sshd -StartupType Automatic"</CommandLine>
                    <Description>Start OpenSSH Server</Description>
                </SynchronousCommand>
                <SynchronousCommand>
                    <Order>3</Order>
                    <CommandLine>powershell -ExecutionPolicy Bypass -Command "New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22"</CommandLine>
                    <Description>Firewall rule for SSH</Description>
                </SynchronousCommand>
                <SynchronousCommand>
                    <Order>4</Order>
                    <CommandLine>powershell -ExecutionPolicy Bypass -Command "New-NetFirewallRule -Name pyautogui -DisplayName 'PyAutoGUI Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 5555"</CommandLine>
                    <Description>Firewall rule for PyAutoGUI</Description>
                </SynchronousCommand>
                <SynchronousCommand>
                    <Order>5</Order>
                    <CommandLine>powershell -ExecutionPolicy Bypass -Command "powercfg /change monitor-timeout-ac 0; powercfg /change standby-timeout-ac 0"</CommandLine>
                    <Description>Disable screen sleep</Description>
                </SynchronousCommand>
                <SynchronousCommand>
                    <Order>6</Order>
                    <CommandLine>reg add "HKCU\\Control Panel\\Desktop" /v ScreenSaveActive /t REG_SZ /d 0 /f</CommandLine>
                    <Description>Disable screensaver</Description>
                </SynchronousCommand>
                <SynchronousCommand>
                    <Order>7</Order>
                    <CommandLine>powershell -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.11.7/python-3.11.7-amd64.exe' -OutFile 'C:\\python_installer.exe'; Start-Process -FilePath 'C:\\python_installer.exe' -ArgumentList '/quiet','InstallAllUsers=1','PrependPath=1' -Wait; Remove-Item 'C:\\python_installer.exe' -Force"</CommandLine>
                    <Description>Install Python 3.11</Description>
                </SynchronousCommand>
                <SynchronousCommand>
                    <Order>8</Order>
                    <CommandLine>cmd /c "C:\\Program Files\\Python311\\python.exe" -m pip install pyautogui pillow</CommandLine>
                    <Description>Install pyautogui</Description>
                </SynchronousCommand>
                <SynchronousCommand>
                    <Order>9</Order>
                    <CommandLine>powershell -ExecutionPolicy Bypass -Command "New-Item -ItemType Directory -Force -Path 'C:\\workspace'"</CommandLine>
                    <Description>Create workspace directory</Description>
                </SynchronousCommand>
            </FirstLogonCommands>
        </component>
    </settings>
</unattend>
'''

# PowerShell script to complete setup after Windows boots
SETUP_SCRIPT_PS1 = '''
# Gym-Anything Windows Setup Script
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\\setup_log.txt"

Write-Host "=== Gym-Anything Windows Setup ==="

# Ensure SSH is running
Write-Host "Configuring SSH..."
try {
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
} catch {}

# Download and install Python
Write-Host "Installing Python..."
$pythonUrl = "https://www.python.org/ftp/python/3.11.7/python-3.11.7-amd64.exe"
$installer = "$env:TEMP\\python_installer.exe"

try {
    Invoke-WebRequest -Uri $pythonUrl -OutFile $installer -UseBasicParsing
    Start-Process -FilePath $installer -ArgumentList "/quiet", "InstallAllUsers=1", "PrependPath=1" -Wait
    Remove-Item $installer -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "Python download failed: $_"
}

# Wait for Python
Start-Sleep -Seconds 10

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Install pyautogui
Write-Host "Installing pyautogui..."
try {
    & python -m pip install --upgrade pip 2>&1 | Out-Null
    & python -m pip install pyautogui pillow 2>&1 | Out-Null
} catch {
    Write-Host "pyautogui install failed: $_"
}

# Create workspace
New-Item -ItemType Directory -Force -Path "C:\\workspace" | Out-Null

# Create completion marker
"Setup complete at $(Get-Date)" | Out-File "C:\\setup_complete.txt"

Write-Host "=== Setup Complete ==="
Stop-Transcript
'''


def check_apptainer():
    """Check if Apptainer is available."""
    try:
        result = subprocess.run(["apptainer", "--version"], capture_output=True, timeout=5)
        return result.returncode == 0
    except:
        return False


def check_kvm():
    """Check if KVM is available and accessible."""
    if not os.path.exists("/dev/kvm"):
        return False
    return os.access("/dev/kvm", os.R_OK | os.W_OK)


def ensure_sif(cache_dir: Path) -> Path:
    """Ensure the dockur/windows SIF file exists."""
    sif_path = cache_dir / "windows_dockur.sif"

    if sif_path.exists():
        print(f"[build] Using cached SIF: {sif_path}")
        return sif_path

    print(f"[build] Pulling {WINDOWS_CONTAINER}...")
    print("[build] This may take several minutes...")

    result = subprocess.run(
        ["apptainer", "pull", str(sif_path), WINDOWS_CONTAINER],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"[build] Failed to pull container: {result.stderr}")
        sys.exit(1)

    return sif_path


def download_windows_iso(sif_path: Path, storage_dir: Path, version: str = "win11") -> Path:
    """Download Windows ISO using dockur scripts."""
    iso_path = storage_dir / "windows.iso"

    if iso_path.exists():
        print(f"[build] Using cached ISO: {iso_path}")
        return iso_path

    print(f"[build] Downloading Windows {version} ISO...")
    print("[build] This may take 10-30 minutes depending on connection speed...")

    # Create a download script that uses the dockur/windows scripts
    download_script = storage_dir / "download.sh"
    download_script.write_text(f'''#!/bin/bash
set -e
cd /run
export STORAGE=/storage
export VERSION={version}
export LANGUAGE=English
export DEBUG=N

# Source the utilities
source utils.sh
source define.sh

# Get version info
getVersion

echo "Download URL: $MIDO"

if [ -n "$MIDO" ]; then
    echo "Downloading..."
    wget -q --show-progress -O /storage/windows.iso "$MIDO" || \\
    curl -L -# -o /storage/windows.iso "$MIDO"
    echo "Download complete"
else
    echo "ERROR: Could not determine download URL"
    exit 1
fi
''')
    download_script.chmod(0o755)

    # Run download inside container
    result = subprocess.run(
        [
            "apptainer", "exec",
            "--bind", f"{storage_dir}:/storage",
            "--bind", f"{download_script}:/download.sh",
            str(sif_path),
            "bash", "/download.sh"
        ],
        timeout=3600,  # 1 hour timeout for download
        capture_output=True,
        text=True
    )

    if result.returncode != 0 or not iso_path.exists():
        print(f"[build] Dockur download failed, trying direct URL...")
        print(f"[build] stderr: {result.stderr[:500] if result.stderr else 'None'}")

        # Fallback: Use known Windows 11 evaluation URL
        # Note: This URL may change, but it's a common fallback
        fallback_urls = [
            "https://software.download.prss.microsoft.com/dbazure/Win11_23H2_English_x64v2.iso?t=...",
        ]

        print("[build] Please download Windows 11 ISO manually:")
        print("  1. Visit: https://www.microsoft.com/software-download/windows11")
        print("  2. Download the ISO")
        print(f"  3. Save as: {iso_path}")
        print()
        print("Or provide your own ISO and continue with --iso-path <path>")
        return None

    return iso_path


def download_virtio_win(storage_dir: Path) -> Optional[Path]:
    """Download virtio-win drivers ISO from Fedora.

    Required for Windows to see virtio devices during installation.
    """
    virtio_path = storage_dir / "virtio-win.iso"

    if virtio_path.exists():
        print(f"[build] Using cached virtio-win.iso: {virtio_path}")
        return virtio_path

    print(f"[build] Downloading virtio-win drivers...")
    print(f"[build] URL: {VIRTIO_WIN_URL}")

    try:
        result = subprocess.run(
            ["wget", "-q", "--show-progress", "-O", str(virtio_path), VIRTIO_WIN_URL],
            timeout=600,  # 10 minute timeout
        )
        if result.returncode == 0 and virtio_path.exists():
            print(f"[build] Downloaded virtio-win.iso ({virtio_path.stat().st_size / 1024 / 1024:.1f} MB)")
            return virtio_path
    except Exception as e:
        print(f"[build] wget failed: {e}")

    # Fallback to curl
    try:
        result = subprocess.run(
            ["curl", "-L", "-#", "-o", str(virtio_path), VIRTIO_WIN_URL],
            timeout=600,
        )
        if result.returncode == 0 and virtio_path.exists():
            print(f"[build] Downloaded virtio-win.iso ({virtio_path.stat().st_size / 1024 / 1024:.1f} MB)")
            return virtio_path
    except Exception as e:
        print(f"[build] curl failed: {e}")

    print("[build] ERROR: Failed to download virtio-win.iso")
    print("[build] Please download manually from:")
    print(f"  {VIRTIO_WIN_URL}")
    print(f"  Save to: {virtio_path}")
    return None


def create_qcow2_disk(sif_path: Path, disk_path: Path, size: str = "64G"):
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


def create_autounattend_iso(sif_path: Path, work_dir: Path) -> Path:
    """Create an ISO with autounattend.xml for UEFI-compatible delivery.

    UEFI firmware does NOT support floppy drives. We create a small ISO
    that Windows installer will scan for autounattend.xml.
    """
    unattend_dir = work_dir / "unattend"
    unattend_dir.mkdir(exist_ok=True)

    # Write autounattend.xml
    (unattend_dir / "autounattend.xml").write_text(AUTOUNATTEND_XML)

    # Also write the setup script
    (unattend_dir / "setup.ps1").write_text(SETUP_SCRIPT_PS1)

    # Create ISO from directory
    iso_path = work_dir / "autounattend.iso"

    # Use genisoimage/mkisofs to create the ISO
    result = subprocess.run(
        [
            "apptainer", "exec",
            "--bind", f"{work_dir}:{work_dir}",
            str(sif_path),
            "genisoimage", "-o", str(iso_path),
            "-J", "-r", "-V", "OEMDRV",  # OEMDRV label is auto-scanned by Windows
            str(unattend_dir)
        ],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        # Fallback: try mkisofs
        result = subprocess.run(
            [
                "apptainer", "exec",
                "--bind", f"{work_dir}:{work_dir}",
                str(sif_path),
                "mkisofs", "-o", str(iso_path),
                "-J", "-r", "-V", "OEMDRV",
                str(unattend_dir)
            ],
            capture_output=True,
            text=True
        )

    if result.returncode != 0 or not iso_path.exists():
        print(f"[build] Warning: Could not create autounattend ISO: {result.stderr}")
        print("[build] Falling back to fat: virtual drive method")
        # Return the directory for fat: method as fallback
        return unattend_dir

    print(f"[build] Created autounattend ISO: {iso_path}")
    return iso_path


def send_qemu_monitor_keys(monitor_port: int, num_keys: int = 10, delay: float = 0.3):
    """Send key presses via QEMU monitor to trigger 'Press any key to boot from CD'.

    This is much more reliable than VNC key sending as it uses QEMU's internal
    keyboard emulation via the monitor's 'sendkey' command.
    """
    import socket

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect(("localhost", monitor_port))

        # Read initial prompt
        try:
            sock.recv(4096)
        except:
            pass

        # Send multiple key presses
        for i in range(num_keys):
            sock.send(b"sendkey spc\n")
            time.sleep(delay)

        # Read any response
        try:
            sock.recv(4096)
        except:
            pass

        sock.close()
        print(f"[build] Sent {num_keys} key presses via QEMU monitor")
        return True
    except Exception as e:
        print(f"[build] Warning: Could not send keys via monitor: {e}")
        return False


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


def run_windows_install(
    sif_path: Path,
    iso_path: Path,
    disk_path: Path,
    autounattend_path: Path,
    virtio_win_path: Optional[Path] = None,
    memory: str = "8G",
    cpus: int = 4,
    interactive: bool = False
) -> bool:
    """Run QEMU to install Windows.

    Uses UEFI boot with virtio drivers for best performance.
    Autounattend is delivered via a secondary ISO (UEFI doesn't support floppy).
    Virtio-win ISO provides drivers so Windows can see virtio disk during install.
    """

    vnc_port = find_free_port(5950)
    vnc_display = vnc_port - 5900

    print()
    print("=" * 60)
    print("Starting Windows Installation (UEFI + virtio)")
    print("=" * 60)
    print(f"VNC Port: {vnc_port}")
    print(f"Connect with: vncviewer localhost:{vnc_port}")
    print()
    print("Installation should be FULLY AUTOMATED (no manual intervention).")
    print("If you see the installation wizard, something is wrong.")
    print("Installation will take 20-40 minutes.")
    if interactive:
        print("Running in interactive mode - watch VNC for progress.")
    else:
        print("Running in background mode.")
    print("=" * 60)
    print()

    # Get OVMF paths from container
    ovmf_code = "/usr/share/OVMF/OVMF_CODE_4M.fd"
    ovmf_vars = "/usr/share/OVMF/OVMF_VARS_4M.fd"

    # Create a copy of OVMF_VARS for this VM (it's writeable)
    # This will be modified during installation with boot entries
    local_vars = disk_path.parent / "OVMF_VARS.fd"
    if not local_vars.exists():
        subprocess.run([
            "apptainer", "exec",
            "--bind", f"{disk_path.parent}:{disk_path.parent}",
            str(sif_path),
            "cp", ovmf_vars, str(local_vars)
        ], capture_output=True)

    # Determine if autounattend is ISO or directory
    is_iso = autounattend_path.suffix == ".iso"

    # Build QEMU command
    qemu_cmd = [
        "qemu-system-x86_64",
        "-accel", "kvm",
        "-m", memory,
        "-smp", str(cpus),
        "-cpu", "host",
        # UEFI boot (pflash for firmware)
        "-drive", f"if=pflash,format=raw,readonly=on,file={ovmf_code}",
        "-drive", f"if=pflash,format=raw,file={local_vars}",
        # Main disk with virtio (best performance)
        "-drive", f"file={disk_path},format=qcow2,if=virtio",
        # Windows installation ISO (primary CD-ROM)
        "-drive", f"file={iso_path},media=cdrom,index=0",
    ]

    # Add virtio-win drivers ISO FIRST (so it gets drive E:)
    # Required for Windows to see virtio disk during installation
    cd_index = 1
    if virtio_win_path and virtio_win_path.exists():
        qemu_cmd.extend([
            "-drive", f"file={virtio_win_path},media=cdrom,index={cd_index}",
        ])
        print(f"[build] Virtio drivers attached at index {cd_index} (drive E:)")
        cd_index += 1

    # Add autounattend delivery mechanism
    # Autounattend is found by OEMDRV label, not by drive letter, so it can be at any index
    if is_iso:
        # CD-ROM with autounattend ISO (UEFI compatible)
        qemu_cmd.extend([
            "-drive", f"file={autounattend_path},media=cdrom,index={cd_index}",
        ])
        print(f"[build] Autounattend ISO at index {cd_index} (found by OEMDRV label)")
        cd_index += 1
    else:
        # Fallback: USB drive with fat: filesystem
        qemu_cmd.extend([
            "-drive", f"file=fat:rw:{autounattend_path},format=raw,if=none,id=usbdisk",
            "-device", "usb-ehci,id=ehci",
            "-device", "usb-storage,bus=ehci.0,drive=usbdisk",
        ])

    qemu_cmd.extend([
        # Display with virtio-vga (best performance)
        "-device", "virtio-vga",
        "-vnc", f":{vnc_display}",
        "-display", "none",
        # Network with virtio (best performance, needed for Windows Update bypass)
        "-device", "virtio-net-pci,netdev=net0",
        "-netdev", "user,id=net0",
        # Boot from CD (menu=off to avoid "Press any key" prompt)
        "-boot", "order=d,menu=off,strict=off",
        # QEMU monitor for diagnostics (telnet to this port)
        "-monitor", f"tcp:127.0.0.1:{vnc_port + 1000},server,nowait",
    ])

    # Build bind mounts for Apptainer
    bind_mounts = [
        "--bind", "/dev/kvm",
        "--bind", f"{disk_path.parent}:{disk_path.parent}",
        "--bind", f"{iso_path.parent}:{iso_path.parent}",
    ]
    if is_iso:
        bind_mounts.extend(["--bind", f"{autounattend_path.parent}:{autounattend_path.parent}"])
    else:
        bind_mounts.extend(["--bind", f"{autounattend_path}:{autounattend_path}"])

    if virtio_win_path and virtio_win_path.exists():
        bind_mounts.extend(["--bind", f"{virtio_win_path.parent}:{virtio_win_path.parent}"])

    # Run QEMU inside container
    # IMPORTANT: --contain --writable-tmpfs are REQUIRED for KVM to work in Apptainer
    full_cmd = [
        "apptainer", "exec",
        "--contain", "--writable-tmpfs",
    ] + bind_mounts + [
        str(sif_path)
    ] + qemu_cmd

    print(f"[build] Starting QEMU...")
    print(f"[build] Command: {' '.join(str(x) for x in full_cmd[:10])}...")

    # Always run in background so we can send key presses
    process = subprocess.Popen(
        full_cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

    print("[build] QEMU running in background (PID: {})".format(process.pid))
    print("[build] Connect via VNC to monitor: vncviewer localhost:{}".format(vnc_port))

    # Monitor port is VNC port + 1000
    monitor_port = vnc_port + 1000

    # Wait for QEMU to start - keep it short, the "Press any key" prompt times out quickly!
    print("[build] Waiting for QEMU monitor to become available...")
    time.sleep(2)

    # Send key presses AGGRESSIVELY to trigger "Press any key to boot from CD"
    # The prompt appears quickly and times out in ~5 seconds, so we need to be fast
    # We send keys multiple times over 15 seconds to ensure we catch the window
    print("[build] Sending boot key presses via QEMU monitor (this takes ~15 seconds)...")
    for attempt in range(5):
        print(f"[build] Sending keys batch {attempt + 1}/5...")
        send_qemu_monitor_keys(monitor_port, num_keys=5, delay=0.2)
        time.sleep(2)

    print()
    print("[build] Waiting for installation to complete...")
    print("[build] This typically takes 20-40 minutes.")
    if interactive:
        print("[build] Press Ctrl+C to abort.")
    print()

    try:
        # Wait for process to complete (Windows shuts down after install)
        process.wait(timeout=5400)  # 90 minutes timeout
        return process.returncode == 0
    except subprocess.TimeoutExpired:
        print("[build] Timeout - killing QEMU")
        process.kill()
        return False
    except KeyboardInterrupt:
        print("[build] Interrupted - killing QEMU")
        process.kill()
        return False


def run_post_install_setup(
    sif_path: Path,
    disk_path: Path,
    memory: str = "8G",
    cpus: int = 4
) -> bool:
    """Boot Windows and run post-installation setup."""

    vnc_port = find_free_port(5950)
    vnc_display = vnc_port - 5900
    ssh_port = find_free_port(2222)

    print()
    print("=" * 60)
    print("Running Post-Installation Setup")
    print("=" * 60)
    print(f"VNC Port: {vnc_port}")
    print(f"SSH Port: {ssh_port} (mapped to VM port 22)")
    print("=" * 60)

    local_vars = disk_path.parent / "OVMF_VARS.fd"
    ovmf_code = "/usr/share/OVMF/OVMF_CODE_4M.fd"

    qemu_cmd = [
        "qemu-system-x86_64",
        "-accel", "kvm",
        "-m", memory,
        "-smp", str(cpus),
        "-cpu", "host",
        "-drive", f"if=pflash,format=raw,readonly=on,file={ovmf_code}",
        "-drive", f"if=pflash,format=raw,file={local_vars}",
        "-drive", f"file={disk_path},format=qcow2,if=virtio",
        "-device", "virtio-vga",
        "-vnc", f":{vnc_display}",
        "-display", "none",
        "-device", "virtio-net-pci,netdev=net0",
        "-netdev", f"user,id=net0,hostfwd=tcp::{ssh_port}-:22",
        "-boot", "c",
    ]

    # IMPORTANT: --contain --writable-tmpfs are REQUIRED for KVM to work in Apptainer
    full_cmd = [
        "apptainer", "exec",
        "--contain", "--writable-tmpfs",
        "--bind", "/dev/kvm",
        "--bind", f"{disk_path.parent}:{disk_path.parent}",
        str(sif_path)
    ] + qemu_cmd

    print("[build] Booting Windows for post-install setup...")
    print("[build] Connect via VNC: vncviewer localhost:{}".format(vnc_port))
    print("[build] SSH (once ready): ssh -p {} Docker@localhost".format(ssh_port))
    print()
    print("[build] Let Windows boot and complete first-login setup.")
    print("[build] The autounattend should configure SSH automatically.")
    print("[build] Press Ctrl+C when setup is complete to save the image.")

    process = subprocess.Popen(full_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    try:
        process.wait()
    except KeyboardInterrupt:
        print("[build] Shutting down...")
        # Send ACPI shutdown
        process.terminate()
        time.sleep(5)
        process.kill()

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Build Windows QCOW2 for gym-anything using Apptainer"
    )
    parser.add_argument(
        "--output", "-o",
        default=str(QEMU_CACHE / "base_windows_11.qcow2"),
        help="Output path for Windows QCOW2"
    )
    parser.add_argument(
        "--version", default="win11",
        help="Windows version (win11, win10, etc.)"
    )
    parser.add_argument(
        "--memory", default="8G",
        help="VM memory"
    )
    parser.add_argument(
        "--cpus", type=int, default=4,
        help="VM CPUs"
    )
    parser.add_argument(
        "--disk-size", default="64G",
        help="Disk size"
    )
    parser.add_argument(
        "--iso-path",
        help="Path to existing Windows ISO (skip download)"
    )
    parser.add_argument(
        "--interactive", action="store_true",
        help="Run QEMU in foreground (for debugging)"
    )
    parser.add_argument(
        "--skip-install", action="store_true",
        help="Skip installation (for post-install setup only)"
    )

    args = parser.parse_args()
    output = Path(args.output)

    print("=" * 60)
    print("GYM-ANYTHING: Build Windows QCOW2 (Apptainer)")
    print("=" * 60)

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
    work_dir = QEMU_CACHE / "work" / "windows_build"
    work_dir.mkdir(parents=True, exist_ok=True)

    storage_dir = work_dir / "storage"
    storage_dir.mkdir(exist_ok=True)

    # Get or pull container
    sif_path = ensure_sif(QEMU_CACHE)

    # Get or download ISO
    if args.iso_path:
        iso_path = Path(args.iso_path).resolve()  # Must be absolute for Apptainer
        if not iso_path.exists():
            print(f"ERROR: ISO not found: {iso_path}")
            sys.exit(1)
    else:
        iso_path = download_windows_iso(sif_path, storage_dir, args.version)
        if not iso_path or not iso_path.exists():
            print("ERROR: Failed to obtain Windows ISO")
            print()
            print("To proceed, manually download Windows 11 ISO:")
            print("  1. Visit: https://www.microsoft.com/software-download/windows11")
            print("  2. Download 'Windows 11 (multi-edition ISO)'")
            print(f"  3. Run again with: --iso-path /path/to/downloaded.iso")
            sys.exit(1)

    print(f"[build] ISO: {iso_path}")

    # Download virtio-win drivers (required for Windows to see virtio disk)
    virtio_win_path = download_virtio_win(storage_dir)
    if virtio_win_path:
        virtio_win_path = virtio_win_path.resolve()  # Ensure absolute path
    else:
        print("WARNING: Proceeding without virtio drivers - installation may fail!")

    # Create disk
    disk_path = storage_dir / "windows.qcow2"
    create_qcow2_disk(sif_path, disk_path, args.disk_size)

    # Create autounattend ISO (UEFI compatible)
    autounattend_path = create_autounattend_iso(sif_path, work_dir)
    if autounattend_path:
        autounattend_path = autounattend_path.resolve()  # Ensure absolute path

    if not args.skip_install:
        # Run installation
        success = run_windows_install(
            sif_path,
            iso_path,
            disk_path,
            autounattend_path,
            virtio_win_path=virtio_win_path,
            memory=args.memory,
            cpus=args.cpus,
            interactive=args.interactive
        )

        if not success:
            print("[build] Installation FAILED")
            print("[build] Check the error output above")
            sys.exit(1)

    # Verify disk has content before continuing
    disk_size = disk_path.stat().st_size
    if disk_size < 1_000_000_000:  # Less than 1GB means installation didn't happen
        print(f"[build] ERROR: Disk is only {disk_size / 1024 / 1024:.1f} MB - installation failed")
        sys.exit(1)

    print(f"[build] Installation complete, disk size: {disk_size / 1024 / 1024 / 1024:.1f} GB")

    # Run post-install setup
    print()
    print("[build] Running post-install boot...")
    run_post_install_setup(sif_path, disk_path, args.memory, args.cpus)

    # Copy to final location (both disk and OVMF_VARS)
    print()
    print(f"[build] Copying to {output}...")
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(disk_path, output)

    # CRITICAL: Also save OVMF_VARS.fd - without this, UEFI won't know how to boot
    ovmf_vars_src = storage_dir / "OVMF_VARS.fd"
    ovmf_vars_dst = output.parent / "base_windows_11_vars.fd"
    if ovmf_vars_src.exists():
        shutil.copy(ovmf_vars_src, ovmf_vars_dst)
        print(f"[build] Saved OVMF_VARS.fd to {ovmf_vars_dst}")
    else:
        print("[build] WARNING: OVMF_VARS.fd not found - image may not boot correctly!")

    # Also copy OVMF_CODE.fd from container for runtime use
    ovmf_code_dst = output.parent / "OVMF_CODE_4M.fd"
    if not ovmf_code_dst.exists():
        subprocess.run([
            "apptainer", "exec",
            "--bind", f"{output.parent}:{output.parent}",
            str(sif_path),
            "cp", "/usr/share/OVMF/OVMF_CODE_4M.fd", str(ovmf_code_dst)
        ], capture_output=True)
        print(f"[build] Copied OVMF_CODE_4M.fd to {ovmf_code_dst}")

    print()
    print("=" * 60)
    print("BUILD COMPLETE")
    print("=" * 60)
    print(f"Output files:")
    print(f"  Disk:      {output}")
    print(f"  OVMF_VARS: {ovmf_vars_dst}")
    print(f"  OVMF_CODE: {ovmf_code_dst}")
    print()
    print("Credentials:")
    print("  User: ga")
    print("  Password: password123")
    print()
    print("Test with:")
    print("  python -m gym_anything.runners.build_windows_qcow2_apptainer --skip-install")


if __name__ == "__main__":
    main()
