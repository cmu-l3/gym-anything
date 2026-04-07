# Windows Notepad Environment

A Windows 11 environment demonstrating Gym-Anything's Windows support using the QEMU/Apptainer runner with SSH + pyautogui for automation.

## Overview

This environment runs Windows 11 inside QEMU (via Apptainer on HPC systems) with:
- Full Windows 11 desktop experience
- SSH access for command execution (via OpenSSH for Windows)
- pyautogui for keyboard/mouse automation (via Python on Windows)
- VNC for screen capture (QEMU's built-in VNC)
- SCP/SFTP for file transfer

## Requirements

### For Building the Windows QCOW2 Image
- **Docker** (for initial Windows installation using dockur/windows)
- **KVM acceleration** (`/dev/kvm`) - Required for reasonable performance
- **64GB+ disk space** for Windows installation

### For Running Environments
- **Apptainer** (for HPC/SLURM compatibility)
- **KVM acceleration** (`/dev/kvm`)
- **8GB+ RAM** available for the Windows VM
- Pre-built Windows QCOW2 image

## Building the Windows QCOW2 Image

Before running Windows environments, you must build the base Windows QCOW2 image:

```bash
# Build Windows 11 image (takes 30-60 minutes)
python -m gym_anything.runners.build_windows_qcow2

# Or specify a different Windows version
python -m gym_anything.runners.build_windows_qcow2 --version win10

# The image will be saved to:
# ~/.cache/gym-anything/qemu/base_windows_11.qcow2
```

### What the Build Process Does

1. Pulls the `ghcr.io/dockur/windows` Docker image
2. Downloads Windows 11 ISO automatically
3. Performs unattended installation
4. Configures OpenSSH Server for remote access
5. Installs Python and pyautogui
6. Exports the disk as QCOW2

## Quick Start

```bash
# Set runner to QEMU/Apptainer
export GYM_ANYTHING_RUNNER=qemu

# Run a task
python loop_all_modular.py --env windows_notepad_env --task hello_world
```

## Tasks

| Task | Difficulty | Description | Steps |
|------|------------|-------------|-------|
| `hello_world` | Easy | Type "Hello, World!" in Notepad and save | ~15 |
| `save_file` | Easy | Open, edit, and save existing file | ~12 |
| `find_replace` | Medium | Use Find & Replace dialog | ~20 |

## Interactive Testing Guide

### 1. Start Environment for Testing

```python
from gym_anything.api import from_config

# Create environment (no task for basic testing)
env = from_config("examples/windows_notepad_env")

# Reset starts the VM
obs = env.reset(seed=42, use_cache=False)

# Get SSH connection info
ssh_port = env._runner.ssh_port
vnc_port = env._runner.vnc_port
print(f"SSH Port: {ssh_port}")
print(f"VNC Port: {vnc_port}")
```

### 2. Connect via SSH (Paramiko)

```python
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('localhost', port=ssh_port, username='Docker', password='admin', timeout=10)

# Run PowerShell command
stdin, stdout, stderr = ssh.exec_command('powershell -Command "Get-Process"')
print(stdout.read().decode())

ssh.close()
```

### 3. Test pyautogui (Keyboard/Mouse)

```python
# Via SSH, run pyautogui commands
stdin, stdout, stderr = ssh.exec_command('''
python -c "
import pyautogui
pyautogui.FAILSAFE = False
# Click at center of screen
pyautogui.click(960, 540)
# Type text
pyautogui.write('Hello from pyautogui!')
# Press Enter
pyautogui.press('enter')
"
''')
print(stdout.read().decode())
```

### 4. Take Screenshot

```python
# Method 1: Via PowerShell (saves to file)
stdin, stdout, stderr = ssh.exec_command('''
powershell -Command "
Add-Type -AssemblyName System.Windows.Forms
$bitmap = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
$bitmap.Save('C:\\workspace\\screenshot.png')
"
''')

# Download via SFTP
sftp = ssh.open_sftp()
sftp.get('/workspace/screenshot.png', 'local_screenshot.png')
sftp.close()
```

### 5. Launch Applications

```python
# Start Notepad
stdin, stdout, stderr = ssh.exec_command('start notepad.exe')

# List running processes
stdin, stdout, stderr = ssh.exec_command('powershell -Command "Get-Process notepad"')
print(stdout.read().decode())
```

### 6. Cleanup

```python
env.close()
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Host System                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Apptainer Container                        │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │                  QEMU/KVM VM                        │ │ │
│  │  │  ┌─────────────────────────────────────────────────┐ │ │ │
│  │  │  │             Windows 11 Desktop                  │ │ │ │
│  │  │  │                                                 │ │ │ │
│  │  │  │   ┌────────────┐    ┌────────────┐             │ │ │ │
│  │  │  │   │  OpenSSH   │    │  Python +  │             │ │ │ │
│  │  │  │   │  Server    │    │ pyautogui  │             │ │ │ │
│  │  │  │   └────────────┘    └────────────┘             │ │ │ │
│  │  │  │                                                 │ │ │ │
│  │  │  │   C:\workspace ←→ Host mount (SCP/SFTP)        │ │ │ │
│  │  │  └─────────────────────────────────────────────────┘ │ │ │
│  │  │           ↑ SSH (port forwarded)                     │ │ │
│  │  │           ↓ VNC (QEMU built-in)                      │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Automation Capabilities

### What Works

| Feature | Method | Notes |
|---------|--------|-------|
| **Mouse clicks** | pyautogui via SSH | `pyautogui.click(x, y)` |
| **Keyboard input** | pyautogui via SSH | `pyautogui.write()`, `pyautogui.hotkey()` |
| **Screenshots** | PowerShell or VNC | Full desktop capture |
| **File operations** | SCP/SFTP | Copy files to/from Windows |
| **Commands** | PowerShell via SSH | Full PowerShell access |
| **App launch** | `start` command | Launch any application |

### Limitations

| Limitation | Workaround |
|------------|------------|
| No X11 | Use QEMU VNC or PowerShell screenshots |
| Boot time 1-5 min | Use checkpointing (post_start cache) |
| No direct GUI inspection | File-based verification or screenshots |

## Comparison: Ubuntu vs Windows

| Aspect | Ubuntu (Linux) | Windows 11 |
|--------|---------------|------------|
| SSH User | `ga` | `Docker` |
| SSH Password | `password123` | `admin` |
| Shell | bash | PowerShell |
| pyautogui | `DISPLAY=:1 python` | `python` (no DISPLAY needed) |
| Screenshots | `ffmpeg x11grab` | PowerShell System.Drawing |
| VNC Port | 5901 (TigerVNC) | QEMU VNC (dynamic) |

## File Structure

```
windows_notepad_env/
├── env.json                         # Environment configuration
├── README.md                        # This file
├── scripts/
│   ├── setup_notepad.bat           # Legacy batch (deprecated)
│   └── setup_notepad.ps1           # PowerShell setup
└── tasks/
    ├── hello_world/
    │   ├── task.json               # Task definition
    │   ├── setup_task.ps1          # Pre-task setup
    │   ├── export_result.ps1       # Post-task export
    │   └── verifier.py             # Success verification
    ├── save_file/
    │   └── ...
    └── find_replace/
        └── ...
```

## Troubleshooting

### "Windows QCOW2 not found"
```bash
# Build the Windows image first
python -m gym_anything.runners.build_windows_qcow2
```

### "SSH connection refused"
- Windows may still be booting (takes 1-5 minutes)
- OpenSSH Server may not have started yet
- Check if firewall is blocking SSH

### "pyautogui not working"
- Python may not be in PATH
- Try: `C:\Python311\python.exe -c "import pyautogui"`

### "Screenshots are black"
- Windows may be at lock screen
- Try clicking somewhere first to wake display
- Check if auto-login is configured

### "KVM not available"
- Ensure `/dev/kvm` exists and is readable
- On HPC, request a node with KVM support
- Without KVM, Windows is too slow to use

## References

- [dockur/windows GitHub](https://github.com/dockur/windows)
- [OpenSSH for Windows](https://docs.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)
- [pyautogui Documentation](https://pyautogui.readthedocs.io/)
- [Gym-Anything Documentation](../../docs/)
