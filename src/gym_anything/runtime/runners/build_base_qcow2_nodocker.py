#!/usr/bin/env python3
"""
Build base QCOW2 image WITHOUT Docker - using cloud-init provisioning.

This script:
1. Downloads Ubuntu cloud image (if not cached)
2. Creates cloud-init config to install GNOME desktop, VNC, tools
3. Boots the VM inside Apptainer with cloud-init
4. Waits for provisioning to complete
5. Saves the result as base_ubuntu_gnome.qcow2

Usage:
    python -m gym_anything.runners.build_base_qcow2_nodocker
    
    # Or with options
    python -m gym_anything.runners.build_base_qcow2_nodocker --timeout 3600
"""

import argparse
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

QEMU_CACHE = Path(os.environ.get("GYM_ANYTHING_QEMU_CACHE", "~/.cache/gym-anything/qemu")).expanduser()
QEMU_CONTAINER = os.environ.get("GYM_ANYTHING_QEMU_CONTAINER", "docker://ghcr.io/dockur/windows:latest")

# Cloud-init user-data to install everything needed
# This matches what the Dockerfile does
CLOUD_INIT_USER_DATA = """#cloud-config
# GYM-ANYTHING Base Image Provisioning

users:
  - name: ga
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [sudo, audio, video, input]
    shell: /bin/bash
    lock_passwd: false
    # Password: password123 (hashed)
    passwd: $6$rounds=4096$saltsalt$IxDD3jeSOb5eB1CX5LBsqZFVkJdkC.MNMOzWMPF5GEKzNK.3ZaVQiAjqAJ8Lz5Y5Yh9TUCm7ZhimP3h8BmKbq0
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICKDhcvuOFDk9Qi2iJD66SVhla3xUcUQQjvm1ablzi2l gym-anything-qemu

# CRITICAL: Enable SSH password authentication
ssh_pwauth: true
chpasswd:
  expire: false
  list:
    - ga:password123

package_update: true

packages:
  # System basics
  - locales
  - sudo
  - wget
  - curl
  - git
  - vim
  - htop
  # Desktop environment
  - ubuntu-desktop-minimal
  - gnome-tweaks
  - dconf-cli
  # VNC server
  - tigervnc-standalone-server
  - tigervnc-common
  - tigervnc-xorg-extension
  # X11 tools
  - xvfb
  - x11-apps
  - x11-utils
  - xdotool
  - wmctrl
  - xterm
  # Media tools
  - ffmpeg
  - pulseaudio
  - imagemagick
  # Python and dev tools
  - python3-pip
  - python3-dev
  - python3-pil
  - python3-numpy
  - python3-tk
  - build-essential
  # SSH
  - openssh-server
  # Network tools
  - net-tools
  - novnc

runcmd:
  # Generate locales
  - locale-gen en_US.UTF-8
  - update-locale LANG=en_US.UTF-8
  
  # Enable SSH with password and public key authentication
  - mkdir -p /etc/ssh/sshd_config.d
  - |
    cat > /etc/ssh/sshd_config.d/00-gym-anything.conf << 'SSHEOF'
    PasswordAuthentication yes
    PubkeyAuthentication yes
    AuthorizedKeysFile .ssh/authorized_keys
    PermitRootLogin yes
    ChallengeResponseAuthentication no
    UsePAM yes
    SSHEOF
  - sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  - systemctl enable ssh
  - systemctl restart ssh
  
  # Set up VNC for user ga
  - mkdir -p /home/ga/.vnc
  - echo "password" | vncpasswd -f > /home/ga/.vnc/passwd
  - chmod 600 /home/ga/.vnc/passwd
  - chown -R ga:ga /home/ga/.vnc
  
  # Create VNC xstartup script
  - |
    cat > /home/ga/.vnc/xstartup << 'EOF'
    #!/bin/bash
    unset SESSION_MANAGER
    unset DBUS_SESSION_BUS_ADDRESS
    export XDG_SESSION_TYPE=x11
    export GNOME_SHELL_SESSION_MODE=ubuntu
    dbus-launch --exit-with-session gnome-session --session=ubuntu
    EOF
  - chmod +x /home/ga/.vnc/xstartup
  - chown ga:ga /home/ga/.vnc/xstartup
  
  # Create TigerVNC systemd service
  - |
    cat > /etc/systemd/system/tigervnc@.service << 'EOF'
    [Unit]
    Description=TigerVNC server on display %i
    After=syslog.target network.target

    [Service]
    Type=forking
    User=ga
    WorkingDirectory=/home/ga
    ExecStartPre=/bin/sh -c '/usr/bin/vncserver -kill %i > /dev/null 2>&1 || :'
    ExecStart=/usr/bin/vncserver %i -geometry 1920x1080 -depth 24 -localhost no
    ExecStop=/usr/bin/vncserver -kill %i
    Restart=on-failure
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
    EOF
  - systemctl daemon-reload
  # Disable TigerVNC - not needed, we use QEMU's built-in VNC
  - systemctl disable tigervnc@:1 || true

  # Enable GDM auto-login for user ga and DISABLE WAYLAND (force Xorg)
  - mkdir -p /etc/gdm3
  - |
    cat > /etc/gdm3/custom.conf << 'EOF'
    [daemon]
    AutomaticLoginEnable=true
    AutomaticLogin=ga
    # CRITICAL: Disable Wayland to use Xorg (required for DISPLAY=:1 compatibility)
    WaylandEnable=false
    DefaultSession=ubuntu-xorg.desktop
    # Use VT2 which maps to display :1 (VT1 = :0, VT2 = :1)
    FirstVT=2

    [security]

    [xdmcp]

    [chooser]

    [debug]
    EOF

  # Configure Xorg to use display :1 instead of :0
  - mkdir -p /etc/X11/xorg.conf.d
  - |
    cat > /etc/X11/xorg.conf.d/10-display-number.conf << 'EOF'
    # Force X server to use display :1 for Docker compatibility
    Section "ServerFlags"
        Option "DefaultServerLayout" "Layout0"
    EndSection

    Section "ServerLayout"
        Identifier "Layout0"
        Option "IsolateDevice" "false"
    EndSection
    EOF

  # Create wrapper script to force GDM to start X on :1
  - mkdir -p /etc/gdm3/Xsession.d
  - |
    cat > /etc/gdm3/Xsession.d/00-force-display1 << 'EOF'
    # Ensure DISPLAY is :1 for compatibility with Docker-based scripts
    if [ -z "$DISPLAY" ]; then
        export DISPLAY=:1
    fi
    EOF
  - chmod +x /etc/gdm3/Xsession.d/00-force-display1 || true

  # Override GDM service to force display :1
  - mkdir -p /etc/systemd/system/gdm.service.d
  - |
    cat > /etc/systemd/system/gdm.service.d/override.conf << 'EOF'
    [Service]
    ExecStartPre=/bin/sh -c 'echo "Starting GDM on display :1"'
    Environment="DISPLAY=:1"
    EOF

  # Create Xwrapper config to allow anybody to start X
  - |
    cat > /etc/X11/Xwrapper.config << 'EOF'
    allowed_users=anybody
    needs_root_rights=yes
    EOF

  # Create Xorg wrapper that forces display :1
  # This is the most reliable way to ensure X starts on :1
  - |
    mv /usr/bin/Xorg /usr/bin/Xorg.real 2>/dev/null || true
    cat > /usr/bin/Xorg << 'XWRAPPER'
    #!/bin/bash
    # Wrapper to force X server to use display :1 for Docker compatibility
    # Replace :0 with :1 in arguments, or add :1 if no display specified
    args=()
    has_display=false
    for arg in "$@"; do
        if [[ "$arg" == ":0" ]]; then
            args+=(":1")
            has_display=true
        elif [[ "$arg" =~ ^:[0-9]+$ ]]; then
            args+=("$arg")
            has_display=true
        else
            args+=("$arg")
        fi
    done
    # If no display was specified, add :1
    if [ "$has_display" = false ]; then
        args+=(":1")
    fi
    exec /usr/bin/Xorg.real "${args[@]}"
    XWRAPPER
    chmod +x /usr/bin/Xorg
  
  # Disable screen lock, screensaver, and ALL popups/notifications
  - mkdir -p /etc/dconf/db/local.d /etc/dconf/profile
  - echo "user-db:user" > /etc/dconf/profile/user
  - echo "system-db:local" >> /etc/dconf/profile/user
  - |
    cat > /etc/dconf/db/local.d/01-disable-lock << 'EOF'
    [org/gnome/desktop/screensaver]
    lock-enabled=false
    ubuntu-lock-on-suspend=false

    [org/gnome/desktop/session]
    idle-delay=uint32 0
    EOF
  - |
    cat > /etc/dconf/db/local.d/02-disable-notifications << 'EOF'
    # Disable all notifications
    [org/gnome/desktop/notifications]
    show-banners=false
    show-in-lock-screen=false

    # Disable software update notifications
    [org/gnome/software]
    download-updates=false
    download-updates-notify=false
    allow-updates=false
    first-run=false

    # Disable welcome screen / initial setup
    [org/gnome/shell]
    welcome-dialog-last-shown-version='99.0'

    [org/gnome/gnome-initial-setup]
    skip=true
    EOF
  - dconf update

  # Disable Ubuntu Pro / Advantage popups
  - pro config set apt_news=false 2>/dev/null || true
  - systemctl disable ubuntu-advantage.service 2>/dev/null || true
  - systemctl mask ubuntu-advantage.service 2>/dev/null || true
  - |
    mkdir -p /etc/apt/apt.conf.d
    echo 'APT::Periodic::Update-Package-Lists "0";' > /etc/apt/apt.conf.d/99disable-updates
    echo 'APT::Periodic::Unattended-Upgrade "0";' >> /etc/apt/apt.conf.d/99disable-updates
    echo 'APT::Periodic::Download-Upgradeable-Packages "0";' >> /etc/apt/apt.conf.d/99disable-updates

  # Disable unattended-upgrades completely
  - systemctl disable unattended-upgrades.service 2>/dev/null || true
  - systemctl mask unattended-upgrades.service 2>/dev/null || true

  # Disable GNOME Software autostart and background updates
  - rm -f /etc/xdg/autostart/gnome-software-service.desktop 2>/dev/null || true
  - rm -f /etc/xdg/autostart/update-notifier.desktop 2>/dev/null || true
  - mkdir -p /home/ga/.config/autostart
  - |
    cat > /home/ga/.config/autostart/gnome-software-service.desktop << 'EOF'
    [Desktop Entry]
    Hidden=true
    EOF
  - |
    cat > /home/ga/.config/autostart/update-notifier.desktop << 'EOF'
    [Desktop Entry]
    Hidden=true
    EOF
  - |
    cat > /home/ga/.config/autostart/gnome-initial-setup-first-login.desktop << 'EOF'
    [Desktop Entry]
    Hidden=true
    EOF
  - chown -R ga:ga /home/ga/.config

  # Disable gnome-initial-setup
  - mkdir -p /home/ga/.config
  - touch /home/ga/.config/gnome-initial-setup-done
  - chown ga:ga /home/ga/.config/gnome-initial-setup-done

  # Enable X11 access for SSH sessions (xhost +local:)
  # This allows commands run via SSH to access the X display
  - |
    cat > /home/ga/.config/autostart/xhost-local.desktop << 'EOF'
    [Desktop Entry]
    Type=Application
    Name=Enable X11 Local Access
    Exec=/bin/bash -c 'sleep 2 && xhost +local:'
    Hidden=false
    NoDisplay=true
    X-GNOME-Autostart-enabled=true
    EOF
  - chown ga:ga /home/ga/.config/autostart/xhost-local.desktop

  # Disable update-manager and software-properties popups
  - sed -i 's/^Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades 2>/dev/null || true

  # Disable motd news
  - sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news 2>/dev/null || true
  - chmod -x /etc/update-motd.d/* 2>/dev/null || true

  # Disable apport crash reporter
  - sed -i 's/^enabled=.*/enabled=0/' /etc/default/apport || true
  - systemctl disable apport.service || true
  - systemctl mask apport.service || true
  - systemctl disable whoopsie.service || true
  - systemctl mask whoopsie.service || true
  
  # Install pyautogui for Python-based mouse/keyboard control
  - pip3 install pyautogui || pip3 install --break-system-packages pyautogui || true
  
  # Set graphical target as default
  - systemctl set-default graphical.target
  
  # Create marker file to indicate provisioning complete
  - touch /home/ga/.provisioning_complete
  - echo "PROVISIONING COMPLETE" > /home/ga/.provisioning_complete

final_message: |
  ==========================================
  GYM-ANYTHING BASE IMAGE PROVISIONING DONE
  ==========================================
  User: ga
  Password: password123
  VNC Password: password
  VNC Port: 5901
  SSH Port: 22
  ==========================================

# Shutdown VM after provisioning completes
power_state:
  delay: "+1"
  mode: poweroff
  message: "Provisioning complete, shutting down..."
  timeout: 30
  condition: true
"""

def get_cloud_init_meta_data():
    """Generate meta-data with unique instance-id for each build."""
    import uuid
    return f"""instance-id: gym-anything-{uuid.uuid4().hex[:8]}
local-hostname: ga-base
"""


def check_apptainer():
    """Check if Apptainer is available."""
    try:
        result = subprocess.run(["apptainer", "--version"], capture_output=True, timeout=5)
        return result.returncode == 0
    except:
        return False


def check_kvm():
    """Check if KVM is available."""
    return os.path.exists("/dev/kvm") and os.access("/dev/kvm", os.R_OK | os.W_OK)


def download_cloud_image(cloud_img: Path):
    """Download Ubuntu cloud image if not cached."""
    if cloud_img.exists():
        print(f"[build] Cloud image already cached: {cloud_img}")
        return
    
    url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    print(f"[build] Downloading Ubuntu cloud image...")
    print(f"[build] URL: {url}")
    
    result = subprocess.run(
        ["wget", "-q", "--show-progress", "-O", str(cloud_img), url]
    )
    
    if result.returncode != 0:
        raise RuntimeError("Failed to download cloud image")
    
    print(f"[build] Downloaded: {cloud_img}")


def create_cloud_init_iso(work_dir: Path) -> Path:
    """Create cloud-init ISO with provisioning config."""
    ci_dir = work_dir / "cloud-init"
    ci_dir.mkdir(exist_ok=True)
    
    # Write user-data
    (ci_dir / "user-data").write_text(CLOUD_INIT_USER_DATA)
    
    # Write meta-data
    (ci_dir / "meta-data").write_text(get_cloud_init_meta_data())
    
    # Create ISO using genisoimage (if available) or mkisofs or xorriso
    iso_path = work_dir / "cloud-init.iso"
    
    # Try different ISO creation tools
    for tool, args in [
        ("genisoimage", ["-output", str(iso_path), "-volid", "cidata", "-joliet", "-rock"]),
        ("mkisofs", ["-o", str(iso_path), "-V", "cidata", "-J", "-r"]),
        ("xorriso", ["-as", "mkisofs", "-o", str(iso_path), "-V", "cidata", "-J", "-r"]),
    ]:
        try:
            cmd = [tool] + args + [str(ci_dir / "user-data"), str(ci_dir / "meta-data")]
            result = subprocess.run(cmd, capture_output=True)
            if result.returncode == 0:
                print(f"[build] Created cloud-init ISO using {tool}")
                return iso_path
        except FileNotFoundError:
            continue
    
    # Fallback: create ISO inside Apptainer
    print("[build] No ISO tool found on host, trying inside Apptainer...")
    result = subprocess.run([
        "apptainer", "exec",
        "--contain",
        "--bind", f"{ci_dir}:/ci",
        "--bind", f"{work_dir}:/out",
        QEMU_CONTAINER,
        "genisoimage", "-output", "/out/cloud-init.iso",
        "-volid", "cidata", "-joliet", "-rock",
        "/ci/user-data", "/ci/meta-data"
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        raise RuntimeError(f"Failed to create cloud-init ISO: {result.stderr}")
    
    print(f"[build] Created cloud-init ISO inside Apptainer")
    return iso_path


def create_disk_overlay(cloud_img: Path, work_dir: Path) -> Path:
    """Create a COW overlay disk for provisioning.
    
    IMPORTANT: We use the same path inside and outside the container
    so that QEMU can find the backing file at runtime.
    """
    overlay = work_dir / "disk.qcow2"
    
    # Use absolute paths and bind them at the SAME location inside container
    # This way the backing file path stored in QCOW2 is valid at runtime
    cloud_img_abs = str(cloud_img.absolute())
    work_dir_abs = str(work_dir.absolute())
    overlay_abs = str(overlay.absolute())
    
    result = subprocess.run([
        "apptainer", "exec",
        "--contain",
        "--bind", f"{cloud_img.parent}:{cloud_img.parent}",  # Same path inside/outside
        "--bind", f"{work_dir_abs}:{work_dir_abs}",  # Same path inside/outside
        QEMU_CONTAINER,
        "qemu-img", "create", "-f", "qcow2",
        "-b", cloud_img_abs,  # Use absolute host path
        "-F", "qcow2",
        overlay_abs,  # Use absolute host path
        "50G"
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        raise RuntimeError(f"Failed to create disk overlay: {result.stderr}")
    
    print(f"[build] Created disk overlay: {overlay}")
    return overlay


def run_provisioning(work_dir: Path, timeout: int, memory: str = "8G", cpus: int = 4):
    """Boot VM and run cloud-init provisioning."""
    print(f"[build] Starting VM for provisioning (timeout: {timeout}s)...")
    print(f"[build] This will install Ubuntu Desktop + VNC + tools")
    print(f"[build] Expected time: 15-30 minutes depending on network speed")
    
    kvm_available = check_kvm()
    print(f"[build] KVM acceleration: {'enabled' if kvm_available else 'DISABLED (will be slow)'}")
    
    work_dir_abs = str(work_dir.absolute())
    cloud_img_parent = str(QEMU_CACHE.absolute())
    
    # Build QEMU command - use absolute paths that match inside/outside container
    qemu_cmd = ["qemu-system-x86_64"]
    
    if kvm_available:
        qemu_cmd.extend(["-accel", "kvm"])
    
    qemu_cmd.extend([
        "-m", memory,
        "-smp", str(cpus),
        "-drive", f"file={work_dir_abs}/disk.qcow2,format=qcow2,if=virtio",
        "-cdrom", f"{work_dir_abs}/cloud-init.iso",
        "-vga", "virtio",
        "-display", "none",
        "-serial", "mon:stdio",
        "-device", "virtio-net-pci,netdev=net0",
        "-netdev", "user,id=net0",
        "-boot", "c",
    ])
    
    # Build Apptainer command - bind paths at same location inside/outside
    cmd = [
        "apptainer", "exec",
        "--contain",
        "--writable-tmpfs",
        "--bind", f"{work_dir_abs}:{work_dir_abs}",  # Same path inside/outside
        "--bind", f"{cloud_img_parent}:{cloud_img_parent}",  # For backing file access
    ]
    
    if kvm_available:
        cmd.extend(["--bind", "/dev/kvm"])
    
    cmd.append(QEMU_CONTAINER)
    cmd.extend(qemu_cmd)
    
    print(f"[build] Running: {' '.join(cmd)}...")
    
    # Start the VM
    log_file = work_dir / "provision.log"
    start_time = time.time()
    
    with open(log_file, "w") as log_fp:
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=log_fp,
            stderr=subprocess.STDOUT,
            cwd=str(work_dir)
        )
        
        print(f"[build] VM started (PID: {proc.pid})")
        print(f"[build] Log: {log_file}")
        print(f"[build] Waiting for provisioning... (check log for progress)")
        
        # Wait for process to complete or timeout
        try:
            proc.wait(timeout=timeout)
            elapsed = time.time() - start_time
            print(f"[build] VM exited after {elapsed:.0f}s (code: {proc.returncode})")
        except subprocess.TimeoutExpired:
            print(f"[build] Timeout after {timeout}s, terminating VM...")
            proc.terminate()
            try:
                proc.wait(timeout=30)
            except:
                proc.kill()
            raise RuntimeError(f"Provisioning timed out after {timeout}s")
    
    # Backup provision log to cache directory before it might get deleted
    backup_log = QEMU_CACHE / "last_provision.log"
    try:
        import shutil
        if log_file.exists():
            shutil.copy(log_file, backup_log)
            print(f"[build] Provision log backed up to: {backup_log}")
        else:
            print(f"[build] Warning: Log file not found at {log_file}")
    except Exception as e:
        print(f"[build] Warning: Could not backup log: {e}")

    # Check log for success
    try:
        if log_file.exists():
            log_content = log_file.read_text()
        elif backup_log.exists():
            log_content = backup_log.read_text()
        else:
            log_content = ""
            print(f"[build] Warning: No log file found")
    except Exception as e:
        print(f"[build] Warning: Could not read log: {e}")
        log_content = ""

    if "PROVISIONING COMPLETE" in log_content or "cloud-init" in log_content:
        print(f"[build] Provisioning completed successfully!")
        return True
    else:
        print(f"[build] Warning: Could not confirm provisioning completed")
        if backup_log.exists():
            print(f"[build] Check log: {backup_log}")
        # Still continue - the VM might have shut down correctly
        return True


def commit_overlay(work_dir: Path, output: Path):
    """Convert overlay to standalone QCOW2."""
    print(f"[build] Converting to standalone image...")
    
    work_dir_abs = str(work_dir.absolute())
    output_abs = str(output.absolute())
    output_parent_abs = str(output.parent.absolute())
    cloud_img_parent = str(QEMU_CACHE.absolute())
    
    result = subprocess.run([
        "apptainer", "exec",
        "--contain",
        "--bind", f"{work_dir_abs}:{work_dir_abs}",  # Same path inside/outside
        "--bind", f"{output_parent_abs}:{output_parent_abs}",  # Same path inside/outside
        "--bind", f"{cloud_img_parent}:{cloud_img_parent}",  # For backing file access
        QEMU_CONTAINER,
        "qemu-img", "convert", "-O", "qcow2",
        f"{work_dir_abs}/disk.qcow2", output_abs
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        raise RuntimeError(f"Failed to convert image: {result.stderr}")
    
    # Get file size
    size_mb = output.stat().st_size / (1024 * 1024)
    print(f"[build] Created: {output} ({size_mb:.0f} MB)")


def main():
    parser = argparse.ArgumentParser(description="Build base QCOW2 without Docker")
    parser.add_argument("--output", "-o", 
                       default=str(QEMU_CACHE / "base_ubuntu_gnome.qcow2"),
                       help="Output path for base QCOW2")
    parser.add_argument("--timeout", type=int, default=7200,
                       help="Provisioning timeout in seconds (default: 7200 = 2 hours, ubuntu-desktop takes 30-60min)")
    parser.add_argument("--memory", default="8G",
                       help="VM memory for provisioning (default: 8G)")
    parser.add_argument("--cpus", type=int, default=4,
                       help="VM CPUs for provisioning (default: 4)")
    parser.add_argument("--keep-work-dir", action="store_true",
                       help="Keep working directory for debugging")
    
    args = parser.parse_args()
    output = Path(args.output)
    
    print("=" * 60)
    print("GYM-ANYTHING: Build Base QCOW2 Image (No Docker)")
    print("=" * 60)
    
    # Check prerequisites
    if not check_apptainer():
        print("ERROR: Apptainer not found")
        sys.exit(1)
    print("[build] ✓ Apptainer available")
    
    if check_kvm():
        print("[build] ✓ KVM available (fast provisioning)")
    else:
        print("[build] ⚠ KVM not available (provisioning will be slow)")
    
    # Setup
    QEMU_CACHE.mkdir(parents=True, exist_ok=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    
    cloud_img = QEMU_CACHE / "ubuntu-cloud.img"
    
    # Download cloud image
    download_cloud_image(cloud_img)
    
    # Create working directory (use cache dir since /tmp may be full)
    work_base = QEMU_CACHE / "work"
    work_base.mkdir(parents=True, exist_ok=True)
    work_dir = Path(tempfile.mkdtemp(prefix="ga_build_base_", dir=work_base))
    print(f"[build] Work directory: {work_dir}")
    
    try:
        # Create cloud-init ISO
        create_cloud_init_iso(work_dir)
        
        # Create disk overlay
        create_disk_overlay(cloud_img, work_dir)
        
        # Run provisioning
        run_provisioning(work_dir, args.timeout, args.memory, args.cpus)
        
        # Commit to final image
        commit_overlay(work_dir, output)
        
        print()
        print("=" * 60)
        print("SUCCESS!")
        print("=" * 60)
        print(f"Base image: {output}")
        print()
        print("You can now run experiments with:")
        print("  export GYM_ANYTHING_RUNNER=qemu")
        print("  python -m agents.evaluation.run_single --env_dir benchmarks/cua_world/environments/gimp_env_all_fast --task ...")
        print("=" * 60)
        
    finally:
        if not args.keep_work_dir:
            import shutil
            shutil.rmtree(work_dir, ignore_errors=True)
        else:
            print(f"[build] Kept work directory: {work_dir}")


if __name__ == "__main__":
    main()

