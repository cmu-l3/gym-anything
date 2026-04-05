"""
Direct Apptainer Runner for GPU-enabled desktop environments.

Unlike QemuApptainerRunner (which runs QEMU inside Apptainer), this runner
executes applications directly inside Apptainer containers with:
- Native GPU access via --nv flag for CUDA/OpenCL
- Fluxbox desktop (no systemd required)
- x11vnc for VNC access
- Xvfb for virtual framebuffer
- PyAutoGUI for action injection

Usage:
    export GYM_ANYTHING_RUNNER=apptainer
    python -m agents.evaluation.run_single --env benchmarks/cua_world/environments/davinci_resolve_apptainer_env/env.json
"""

from __future__ import annotations

import fcntl
import hashlib
import os
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
from typing import Any, Dict, List, Optional, Tuple

from ...specs import EnvSpec
from .base import BaseRunner
from .vnc_utils import VNCConnectionPool


# Configuration via environment variables
APPTAINER_CACHE = Path(os.environ.get(
    "GYM_ANYTHING_APPTAINER_CACHE",
    "~/.cache/gym-anything/apptainer"
)).expanduser()

# Lock file for port allocation
PORT_LOCK_FILE = APPTAINER_CACHE / ".port_lock"


def _find_free_port(start: int = 5900, max_attempts: int = 300) -> int:
    """Find a free port starting from the given port."""
    import random
    offset = random.randint(0, 100)
    for i in range(max_attempts):
        port = start + offset + i
        if port > 65535:
            port = start + (i % max_attempts)
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.bind(("0.0.0.0", port))
                return port
        except OSError:
            continue
    raise RuntimeError(f"No free port found starting from {start}")


def _find_free_display(start: int = 99, max_attempts: int = 100) -> int:
    """Find a free X11 display number."""
    for i in range(max_attempts):
        display = start + i
        lock_file = Path(f"/tmp/.X{display}-lock")
        socket_file = Path(f"/tmp/.X11-unix/X{display}")
        if not lock_file.exists() and not socket_file.exists():
            return display
    raise RuntimeError(f"No free display found starting from :{start}")


def _check_apptainer() -> bool:
    """Check if Apptainer is available."""
    try:
        result = subprocess.run(
            ["apptainer", "--version"],
            capture_output=True,
            timeout=5
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def _get_env_hash(spec: EnvSpec) -> str:
    """Generate hash for environment (for caching SIF images)."""
    key_parts = [
        spec.base or "",
        spec.image or "",
        str(getattr(spec, "apptainer", None)),
        str(getattr(spec, "hooks", {})),
    ]
    return hashlib.sha256("|".join(key_parts).encode()).hexdigest()[:16]


class ApptainerDirectRunner(BaseRunner):
    """
    Direct Apptainer runner for HPC/SLURM environments with GPU support.

    This runner executes applications directly inside Apptainer containers
    without the overhead of running a VM (unlike QemuApptainerRunner).

    Features:
    - Native GPU access via --nv flag
    - Fluxbox window manager (no systemd required)
    - x11vnc for VNC-based screen capture
    - PyAutoGUI for action injection
    - Fast startup (~5-10 seconds vs ~60 seconds for QEMU)

    Workflow:
        1. Build/pull SIF image (cached)
        2. Start Apptainer instance with GPU and display bindings
        3. Bootstrap Xvfb + x11vnc + fluxbox inside container
        4. Interact via VNC (screenshots) and `apptainer exec` (commands)
    """

    def __init__(self, spec: EnvSpec):
        super().__init__(spec)

        if not _check_apptainer():
            raise RuntimeError("Apptainer not found. Install with: apt install apptainer")

        # Instance identification
        self.instance_id = uuid.uuid4().hex[:12]
        self.instance_name = f"ga_apt_{self.instance_id}"

        # SIF image management
        APPTAINER_CACHE.mkdir(parents=True, exist_ok=True)
        self._sif_path: Optional[Path] = None
        self._env_hash = _get_env_hash(spec)

        # Display configuration
        self._display_num: Optional[int] = None
        self._vnc_port: Optional[int] = None

        # VNC config
        vnc_cfg = getattr(spec, "vnc", None)
        self._vnc_password = vnc_cfg.password if vnc_cfg and vnc_cfg.password else "password"

        # GPU support
        self._enable_gpu = bool(spec.resources.gpu and spec.resources.gpu > 0)
        self._has_nvidia = os.path.exists("/dev/nvidia0") or os.path.exists("/dev/nvidiactl")
        self._has_dri = os.path.exists("/dev/dri")

        if self._enable_gpu and not self._has_nvidia and not self._has_dri:
            print("[ApptainerDirect] WARNING: GPU requested but no /dev/nvidia* or /dev/dri found")

        # Screen resolution
        screen_spec = next((o for o in spec.observation if o.type == "rgb_screen"), None)
        self._resolution = screen_spec.resolution if screen_spec else (1920, 1080)

        # State
        self._running = False
        self._instance_started = False
        self._vnc_pool: Optional[VNCConnectionPool] = None
        self._work_dir: Optional[Path] = None

        # Artifacts
        self._artifacts_root = os.path.abspath(spec.recording.output_dir)

        # Lock for thread safety
        self._lock = threading.Lock()

        # Checkpoint support
        self._checkpoint_cache_level: str = "pre_start"
        self._checkpoint_task_id: Optional[str] = None

        # VirtualGL support for GPU OpenGL apps
        self._vgl_enabled: bool = False

    # =========================================================================
    # Lifecycle Methods
    # =========================================================================

    def start(self, seed: Optional[int] = None) -> None:
        """Start the Apptainer environment.

        Steps:
        1. Ensure SIF image exists (build or pull)
        2. Create work directory
        3. Allocate display and VNC port
        4. Start Apptainer instance
        5. Bootstrap display stack (Xvfb + x11vnc + fluxbox)
        6. Wait for desktop to be ready
        7. Connect VNC pool for screenshots
        """
        print(f"[ApptainerDirect] Instance: {self.instance_name}")

        if self._enable_gpu:
            gpu_type = "NVIDIA" if self._has_nvidia else ("DRI/Mesa" if self._has_dri else "none found")
            print(f"[ApptainerDirect] GPU: enabled ({gpu_type})")

        # Step 1: Ensure SIF exists
        self._ensure_sif_image()

        # Step 2: Create work directory
        self._work_dir = Path(tempfile.mkdtemp(prefix=f"ga_apt_{self.instance_id}_"))
        print(f"[ApptainerDirect] Work dir: {self._work_dir}")

        # Step 3: Allocate display and VNC port
        with self._lock:
            self._display_num = _find_free_display(99)
            self._vnc_port = _find_free_port(5900)
        print(f"[ApptainerDirect] Display: :{self._display_num}, VNC port: {self._vnc_port}")

        # Step 4: Start Apptainer instance
        self._start_instance()

        # Step 5: Bootstrap display
        self._bootstrap_display()

        # Step 6: Wait for desktop
        if not self._wait_for_desktop(timeout=60):
            self._dump_logs()
            self.stop()
            raise RuntimeError("Desktop failed to start within timeout")

        # Step 7: Connect VNC
        try:
            self._vnc_pool = VNCConnectionPool(
                host="localhost",
                port=self._vnc_port,
                password=self._vnc_password
            )
            conn = self._vnc_pool.get_connection(retry_count=10, retry_delay=1.0)
            if conn:
                w, h = conn.resolution
                print(f"[ApptainerDirect] VNC connected, resolution: {w}x{h}")
            else:
                print("[ApptainerDirect] WARNING: VNC connection failed, screenshots may not work")
        except Exception as e:
            print(f"[ApptainerDirect] WARNING: VNC pool setup failed: {e}")
            self._vnc_pool = None

        # Step 8: Run hooks
        self._run_hooks()

        self._running = True
        print(f"[ApptainerDirect] Ready!")

    def stop(self) -> None:
        """Stop the Apptainer environment and clean up."""
        if not self._running and not self._instance_started:
            return

        print(f"[ApptainerDirect] Stopping {self.instance_name}...")

        # Close VNC connection
        if self._vnc_pool:
            try:
                self._vnc_pool.close()
            except:
                pass
            self._vnc_pool = None

        # Stop Apptainer instance
        if self._instance_started:
            try:
                subprocess.run(
                    ["apptainer", "instance", "stop", self.instance_name],
                    capture_output=True,
                    timeout=30
                )
            except Exception as e:
                print(f"[ApptainerDirect] Instance stop error: {e}")
            self._instance_started = False

        # Cleanup work directory
        if self._work_dir and self._work_dir.exists():
            try:
                shutil.rmtree(self._work_dir, ignore_errors=True)
            except:
                pass

        self._running = False
        print(f"[ApptainerDirect] Stopped")

    # =========================================================================
    # SIF Image Management
    # =========================================================================

    def _ensure_sif_image(self) -> None:
        """Ensure the SIF image exists, building or pulling if necessary."""
        apptainer_cfg = getattr(self.spec, "apptainer", None)

        # Option 1: Pre-built SIF specified directly
        if apptainer_cfg and getattr(apptainer_cfg, "sif", None):
            self._sif_path = Path(apptainer_cfg.sif).expanduser()
            if self._sif_path.exists():
                print(f"[ApptainerDirect] Using SIF: {self._sif_path}")
                return
            raise FileNotFoundError(f"SIF not found: {self._sif_path}")

        # Option 2: Build from definition file
        if apptainer_cfg and getattr(apptainer_cfg, "definition", None):
            def_path = Path(apptainer_cfg.definition)
            if not def_path.is_absolute():
                # Relative to repo root
                def_path = Path(__file__).parent.parent.parent / def_path

            if not def_path.exists():
                raise FileNotFoundError(f"Apptainer definition not found: {def_path}")

            sif_name = f"{self._env_hash}.sif"
            self._sif_path = APPTAINER_CACHE / sif_name

            if not self._sif_path.exists():
                print(f"[ApptainerDirect] Building SIF from {def_path}...")
                self._build_sif(def_path, self._sif_path)
            else:
                print(f"[ApptainerDirect] Using cached SIF: {self._sif_path}")
            return

        # Option 3: Pull from Docker/remote image
        image_ref = None
        if apptainer_cfg and getattr(apptainer_cfg, "image", None):
            image_ref = apptainer_cfg.image
        elif self.spec.image:
            image_ref = self.spec.image

        if image_ref:
            sif_name = self._image_to_sif_name(image_ref)
            self._sif_path = APPTAINER_CACHE / sif_name

            if not self._sif_path.exists():
                print(f"[ApptainerDirect] Pulling image: {image_ref}")
                self._pull_image(image_ref, self._sif_path)
            else:
                print(f"[ApptainerDirect] Using cached SIF: {self._sif_path}")
            return

        # Option 4: Use default desktop SIF
        default_sif = APPTAINER_CACHE / "gym_anything_xfce_gpu.sif"
        if default_sif.exists():
            self._sif_path = default_sif
            print(f"[ApptainerDirect] Using default SIF: {self._sif_path}")
            return

        # Build default SIF from embedded definition
        print("[ApptainerDirect] Building default GPU desktop SIF...")
        self._build_default_sif(default_sif)
        self._sif_path = default_sif

    def _build_sif(self, def_path: Path, sif_path: Path) -> None:
        """Build SIF from definition file."""
        cmd = ["apptainer", "build", "--fakeroot", str(sif_path), str(def_path)]
        print(f"[ApptainerDirect] Running: {' '.join(cmd)}")

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
        if result.returncode != 0:
            print(f"[ApptainerDirect] Build stdout: {result.stdout[:2000]}")
            print(f"[ApptainerDirect] Build stderr: {result.stderr[:2000]}")
            raise RuntimeError(f"SIF build failed: {result.stderr[:500]}")

        print(f"[ApptainerDirect] SIF built: {sif_path}")

    def _pull_image(self, image_ref: str, sif_path: Path) -> None:
        """Pull Docker/OCI image and convert to SIF."""
        # Normalize image reference
        if not image_ref.startswith(("docker://", "library://", "oras://")):
            image_ref = f"docker://{image_ref}"

        cmd = ["apptainer", "pull", str(sif_path), image_ref]
        print(f"[ApptainerDirect] Running: {' '.join(cmd)}")

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
        if result.returncode != 0:
            raise RuntimeError(f"Image pull failed: {result.stderr[:500]}")

        print(f"[ApptainerDirect] Image pulled: {sif_path}")

    def _image_to_sif_name(self, image_ref: str) -> str:
        """Convert image reference to safe SIF filename."""
        # Remove protocol prefix
        name = image_ref
        for prefix in ["docker://", "library://", "oras://"]:
            if name.startswith(prefix):
                name = name[len(prefix):]
                break
        # Replace unsafe characters
        name = name.replace("/", "_").replace(":", "_").replace("@", "_")
        return f"{name}.sif"

    def _build_default_sif(self, sif_path: Path) -> None:
        """Build default GPU desktop SIF from inline definition."""
        def_content = '''Bootstrap: docker
From: ubuntu:22.04

%labels
    Author gym-anything
    Version 1.0
    Description GPU-enabled fluxbox desktop for Gym-Anything

%post
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y --no-install-recommends \\
        xvfb \\
        x11vnc \\
        fluxbox \\
        xterm \\
        wmctrl \\
        xdotool \\
        ffmpeg \\
        python3 \\
        python3-pip \\
        python3-tk \\
        python3-dev \\
        scrot \\
        imagemagick \\
        fonts-dejavu \\
        fonts-liberation \\
        dbus-x11 \\
        libgl1-mesa-dri \\
        libgl1-mesa-glx \\
        libegl1-mesa \\
        libglu1-mesa \\
        mesa-utils \\
        libxv1 \\
        libxrender1 \\
        libxrandr2 \\
        wget \\
        curl \\
        ca-certificates \\
        sudo \\
        && rm -rf /var/lib/apt/lists/*

    pip3 install --no-cache-dir pyautogui Pillow pyscreeze python-xlib

    useradd -m -s /bin/bash -u 1000 ga || true
    echo "ga ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    mkdir -p /workspace /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix

    mkdir -p /home/ga/.fluxbox
    echo "session.screen0.toolbar.visible: false" > /home/ga/.fluxbox/init
    chown -R 1000:1000 /home/ga

%environment
    export HOME=/home/ga
    export USER=ga
    export XDG_RUNTIME_DIR=/tmp/runtime-ga

%runscript
    exec "$@"
'''
        # Write temp definition file
        def_file = self._work_dir / "default.def" if self._work_dir else Path(tempfile.mktemp(suffix=".def"))
        def_file.parent.mkdir(parents=True, exist_ok=True)
        def_file.write_text(def_content)

        try:
            self._build_sif(def_file, sif_path)
        finally:
            if def_file.exists() and not self._work_dir:
                def_file.unlink()

    # =========================================================================
    # Instance Management
    # =========================================================================

    def _start_instance(self) -> None:
        """Start an Apptainer instance with proper bindings.

        Note: For environments that require package installation (apt-get),
        a custom SIF should be built with the software pre-installed.
        The --fakeroot mode has compatibility issues with GPU passthrough.
        """
        cmd = [
            "apptainer", "instance", "start",
            "--contain",
            "--cleanenv",
            "--writable-tmpfs",  # Ephemeral writes (limited space but GPU-compatible)
        ]
        image_path = str(self._sif_path)

        # GPU support
        if self._enable_gpu:
            if self._has_nvidia:
                cmd.append("--nv")
                # Explicitly bind NVIDIA devices
                for dev in ["/dev/nvidia0", "/dev/nvidiactl", "/dev/nvidia-uvm", "/dev/nvidia-modeset"]:
                    if os.path.exists(dev):
                        cmd.extend(["--bind", dev])
                # Bind OpenCL vendor files for GPU applications (DaVinci Resolve, etc.)
                if os.path.exists("/etc/OpenCL/vendors"):
                    cmd.extend(["--bind", "/etc/OpenCL/vendors"])

            if self._has_dri:
                cmd.extend(["--bind", "/dev/dri"])

        # Bind input devices for synthetic input injection (ydotool, evemu)
        if os.path.exists("/dev/uinput"):
            cmd.extend(["--bind", "/dev/uinput"])
        if os.path.exists("/dev/input"):
            cmd.extend(["--bind", "/dev/input"])

        # Bind work directory
        cmd.extend(["--bind", f"{self._work_dir}:{self._work_dir}"])

        # Create a shadow /home directory to isolate from host autofs/NFS mounts
        # This ensures /home/ga is writable and not shadowed by host /home
        home_shadow = self._work_dir / "home_shadow" / "ga"
        home_shadow.mkdir(parents=True, exist_ok=True)
        # Create necessary subdirectories for common apps (DaVinci Resolve, etc.)
        (home_shadow / ".local/share/DaVinciResolve/configs").mkdir(parents=True, exist_ok=True)
        (home_shadow / ".local/share/DaVinciResolve/Fusion").mkdir(parents=True, exist_ok=True)
        (home_shadow / ".local/share/DaVinciResolve/Resolve/Disk Databases").mkdir(parents=True, exist_ok=True)
        (home_shadow / ".config").mkdir(parents=True, exist_ok=True)
        (home_shadow / ".fluxbox").mkdir(parents=True, exist_ok=True)
        (home_shadow / "Documents/DaVinciResolve/Projects").mkdir(parents=True, exist_ok=True)
        (home_shadow / "Videos/footage").mkdir(parents=True, exist_ok=True)
        (home_shadow / "Videos/exports").mkdir(parents=True, exist_ok=True)
        (home_shadow / ".fluxbox/init").write_text("session.screen0.toolbar.visible: false\n")
        # Bind the entire home_shadow directory over /home to shadow host autofs
        cmd.extend(["--bind", f"{self._work_dir / 'home_shadow'}:/home"])

        # Bind artifacts directory
        Path(self._artifacts_root).mkdir(parents=True, exist_ok=True)
        cmd.extend(["--bind", f"{self._artifacts_root}:{self._artifacts_root}"])

        # Bind mounts from spec
        for mount in self.spec.mounts:
            source = os.path.abspath(mount.source)
            target = mount.target
            if os.path.exists(source):
                mode = "ro" if mount.mode == "ro" else ""
                bind_spec = f"{source}:{target}" + (f":{mode}" if mode else "")
                cmd.extend(["--bind", bind_spec])
            else:
                print(f"[ApptainerDirect] WARNING: Mount source not found: {source}")

        # Bind /tmp/.X11-unix for X11 sockets
        x11_dir = Path("/tmp/.X11-unix")
        x11_dir.mkdir(exist_ok=True)
        cmd.extend(["--bind", "/tmp/.X11-unix"])

        # Environment variables
        env_vars = {
            "DISPLAY": f":{self._display_num}",
            "HOME": "/home/ga",
            "USER": "ga",
            "XDG_RUNTIME_DIR": "/tmp/runtime-ga",
        }
        env_vars.update(self.spec.apptainer.env if self.spec.apptainer else {})
        env_vars.update(self.default_exec_env())
        for k, v in env_vars.items():
            cmd.extend(["--env", f"{k}={v}"])

        # Image (sandbox or SIF) and instance name
        cmd.extend([image_path, self.instance_name])

        print(f"[ApptainerDirect] Starting instance...")
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)

        if result.returncode != 0:
            print(f"[ApptainerDirect] Instance start stderr: {result.stderr}")
            raise RuntimeError(f"Failed to start Apptainer instance: {result.stderr[:500]}")

        self._instance_started = True
        print(f"[ApptainerDirect] Instance started")

    # =========================================================================
    # Display Stack Bootstrap
    # =========================================================================

    def _bootstrap_display(self) -> None:
        """Start display server + x11vnc + fluxbox inside the container.

        For GPU-enabled environments:
        - Uses VirtualGL with Xvfb for hardware-accelerated OpenGL
        - Sets VGL_DISPLAY for redirecting OpenGL to NVIDIA EGL

        For non-GPU environments:
        - Uses standard Xvfb with software rendering
        """
        width, height = self._resolution
        depth = 24
        display = f":{self._display_num}"

        # Create runtime directory
        self._exec_instance("mkdir -p /tmp/runtime-ga && chmod 700 /tmp/runtime-ga")

        # Create home directory structure (needed because --contain doesn't preserve SIF /home)
        self._exec_instance(
            "mkdir -p /home/ga && "
            "mkdir -p /home/ga/.fluxbox && "
            "echo 'session.screen0.toolbar.visible: false' > /home/ga/.fluxbox/init && "
            "mkdir -p /home/ga/.local/share/DaVinciResolve/configs && "
            "mkdir -p /home/ga/.local/share/DaVinciResolve/Fusion && "
            "mkdir -p '/home/ga/.local/share/DaVinciResolve/Resolve/Disk Databases' && "
            "mkdir -p /home/ga/Documents/DaVinciResolve/Projects && "
            "mkdir -p /home/ga/Videos/footage && "
            "mkdir -p /home/ga/Videos/exports && "
            "mkdir -p /home/ga/.config && "
            "chmod -R 777 /home/ga 2>/dev/null || true"
        )

        # Check if VirtualGL is available for GPU rendering
        vgl_available = False
        if self._enable_gpu and self._has_nvidia:
            result = self._exec_instance("which vglrun 2>/dev/null || test -f /opt/VirtualGL/bin/vglrun && echo /opt/VirtualGL/bin/vglrun")
            if result.stdout.strip():
                vgl_available = True
                print(f"[ApptainerDirect] VirtualGL detected: {result.stdout.strip()}")

        # Start Xvfb (use nohup and redirect to ensure it backgrounds properly)
        xvfb_cmd = (
            f"nohup Xvfb {display} -screen 0 {width}x{height}x{depth} "
            f"-ac +extension GLX +render -noreset > /tmp/xvfb.log 2>&1 &"
        )
        self._exec_instance_bg(xvfb_cmd)
        print(f"[ApptainerDirect] Xvfb started on {display}")
        time.sleep(3)

        # If VirtualGL is available, configure environment for EGL-based GPU rendering
        if vgl_available:
            # VirtualGL can use EGL backend for headless GPU rendering
            # This allows OpenGL apps to render on GPU without a physical display
            self._vgl_enabled = True
            # Configure VirtualGL to use EGL (works with NVIDIA headless)
            self._exec_instance(
                "echo 'export VGL_DISPLAY=egl' >> /home/ga/.bashrc && "
                "echo 'export __GLX_VENDOR_LIBRARY_NAME=nvidia' >> /home/ga/.bashrc && "
                "echo 'export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json' >> /home/ga/.bashrc"
            )
            print(f"[ApptainerDirect] VirtualGL EGL mode configured")
        else:
            self._vgl_enabled = False

        # Start x11vnc (use nohup for background)
        vnc_cmd = (
            f"nohup x11vnc -display {display} -forever -shared "
            f"-rfbport {self._vnc_port} -passwd {self._vnc_password} "
            f"-noxdamage -noxfixes -o /tmp/x11vnc.log > /dev/null 2>&1 &"
        )
        self._exec_instance_bg(vnc_cmd)
        print(f"[ApptainerDirect] x11vnc started on port {self._vnc_port}")
        time.sleep(2)

        # Start fluxbox window manager (use nohup for background)
        fluxbox_cmd = f"nohup fluxbox > /tmp/fluxbox.log 2>&1 &"
        self._exec_instance_bg(fluxbox_cmd, env={"DISPLAY": display})
        print(f"[ApptainerDirect] fluxbox started")
        time.sleep(2)

    def _wait_for_desktop(self, timeout: float = 60) -> bool:
        """Wait for the desktop to be ready by checking window manager."""
        print(f"[ApptainerDirect] Waiting for desktop...")
        start = time.time()
        display = f":{self._display_num}"

        while time.time() - start < timeout:
            try:
                # Check if fluxbox is responding via wmctrl
                result = self._exec_capture_result(f"DISPLAY={display} wmctrl -m 2>&1")
                if result.returncode == 0 and "fluxbox" in result.stdout.lower():
                    print(f"[ApptainerDirect] Desktop ready (fluxbox detected)")
                    return True

                # Alternative check: xdpyinfo
                result = self._exec_capture_result(f"DISPLAY={display} xdpyinfo 2>&1 | head -5")
                if result.returncode == 0 and "dimensions" in result.stdout.lower():
                    print(f"[ApptainerDirect] Desktop ready (X11 responding)")
                    return True

            except Exception as e:
                pass

            time.sleep(2)

        return False

    def _dump_logs(self) -> None:
        """Dump logs for debugging."""
        try:
            vnc_log = self._exec_capture("cat /tmp/x11vnc.log 2>/dev/null || true")
            if vnc_log.strip():
                print(f"[ApptainerDirect] x11vnc log:\n{vnc_log[:1000]}")
        except:
            pass

    def _run_hooks(self) -> None:
        """Run pre_start and post_start hooks if defined."""
        hooks = getattr(self.spec, "hooks", None)
        if not hooks:
            print(f"[ApptainerDirect] No hooks defined")
            return

        # hooks is a Dict[str, str], not an object
        if isinstance(hooks, dict):
            pre_start = hooks.get("pre_start")
            post_start = hooks.get("post_start")
        else:
            pre_start = getattr(hooks, "pre_start", None)
            post_start = getattr(hooks, "post_start", None)

        # Run pre_start hook (typically installs software)
        if pre_start:
            print(f"[ApptainerDirect] Running pre_start hook: {pre_start}")
            print(f"[ApptainerDirect] This may take a while for installation scripts...")
            try:
                # Pre-start hooks often need root and longer timeout
                result = self._exec_instance(
                    f"sudo bash {shlex.quote(pre_start)} 2>&1 || bash {shlex.quote(pre_start)} 2>&1",
                    timeout=1800  # 30 minute timeout for installation
                )
                if result.returncode != 0:
                    print(f"[ApptainerDirect] pre_start hook failed (exit {result.returncode})")
                    if result.stdout:
                        print(f"[ApptainerDirect] stdout (last 1000 chars): {result.stdout[-1000:]}")
                    if result.stderr:
                        print(f"[ApptainerDirect] stderr: {result.stderr[:500]}")
                else:
                    print(f"[ApptainerDirect] pre_start hook completed successfully")
                    if result.stdout:
                        # Show last few lines of output
                        lines = result.stdout.strip().split('\n')
                        print(f"[ApptainerDirect] Output (last 5 lines):")
                        for line in lines[-5:]:
                            print(f"  {line}")
            except subprocess.TimeoutExpired:
                print(f"[ApptainerDirect] pre_start hook timed out after 30 minutes")
            except Exception as e:
                print(f"[ApptainerDirect] pre_start hook error: {e}")

        # Run post_start hook (typically configures environment)
        if post_start:
            print(f"[ApptainerDirect] Running post_start hook: {post_start}")
            try:
                result = self._exec_instance(
                    f"sudo bash {shlex.quote(post_start)} 2>&1 || bash {shlex.quote(post_start)} 2>&1",
                    timeout=600  # 10 minute timeout for setup
                )
                if result.returncode != 0:
                    print(f"[ApptainerDirect] post_start hook failed (exit {result.returncode})")
                    if result.stdout:
                        print(f"[ApptainerDirect] stdout (last 1000 chars): {result.stdout[-1000:]}")
                    if result.stderr:
                        print(f"[ApptainerDirect] stderr: {result.stderr[:500]}")
                else:
                    print(f"[ApptainerDirect] post_start hook completed successfully")
            except subprocess.TimeoutExpired:
                print(f"[ApptainerDirect] post_start hook timed out after 10 minutes")
            except Exception as e:
                print(f"[ApptainerDirect] post_start hook error: {e}")

    # =========================================================================
    # Command Execution
    # =========================================================================

    def _exec_instance(self, cmd: str, timeout: int = 300) -> subprocess.CompletedProcess:
        """Execute command inside the Apptainer instance."""
        full_cmd = [
            "apptainer", "exec",
            "--env", f"DISPLAY=:{self._display_num}",
            "--env", "HOME=/home/ga",
            "--env", "USER=ga",
            f"instance://{self.instance_name}",
            "bash", "-c", cmd
        ]
        return subprocess.run(full_cmd, capture_output=True, text=True, timeout=timeout)

    def _exec_instance_bg(self, cmd: str, env: Optional[Dict[str, str]] = None) -> None:
        """Execute a background command inside the Apptainer instance.

        Uses Popen with shell=True to properly handle backgrounded processes.
        """
        full_cmd = ["apptainer", "exec"]

        # Add environment variables
        full_cmd.extend(["--env", f"DISPLAY=:{self._display_num}"])
        full_cmd.extend(["--env", "HOME=/home/ga"])
        full_cmd.extend(["--env", "USER=ga"])

        if env:
            for k, v in env.items():
                full_cmd.extend(["--env", f"{k}={v}"])

        full_cmd.extend([f"instance://{self.instance_name}", "bash", "-c", cmd])

        # Use Popen to not wait for backgrounded command
        subprocess.Popen(
            full_cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )

    def _exec_capture_result(self, cmd: str, timeout: int = 300) -> subprocess.CompletedProcess:
        """Execute command and return CompletedProcess."""
        return self._exec_instance(cmd, timeout=timeout)

    def exec(self, cmd: str, env: Optional[Dict[str, str]] = None,
             user: Optional[str] = None, use_pty: bool = True,
             timeout: int = 600) -> int:
        """Execute command inside the Apptainer instance.

        Args:
            cmd: Command to execute
            env: Additional environment variables
            user: User to run as (ignored, runs as container user)
            use_pty: Whether to use PTY (ignored)
            timeout: Command timeout in seconds

        Returns:
            Exit code of the command
        """
        env = self.merge_exec_env(env)
        env = {**(self.spec.apptainer.env if self.spec.apptainer else {}), **env}
        full_cmd = ["apptainer", "exec"]

        # Environment variables
        full_cmd.extend(["--env", f"DISPLAY=:{self._display_num}"])
        full_cmd.extend(["--env", "HOME=/home/ga"])
        full_cmd.extend(["--env", "USER=ga"])

        if env:
            for k, v in env.items():
                full_cmd.extend(["--env", f"{k}={v}"])

        full_cmd.extend([f"instance://{self.instance_name}", "bash", "-c", cmd])

        try:
            result = subprocess.run(full_cmd, capture_output=True, timeout=timeout)
            if result.returncode != 0:
                stderr = result.stderr.decode() if isinstance(result.stderr, bytes) else result.stderr
                if stderr:
                    print(f"[ApptainerDirect] exec stderr: {stderr[:500]}")
            return result.returncode
        except subprocess.TimeoutExpired:
            print(f"[ApptainerDirect] exec timeout after {timeout}s")
            return 1

    def exec_capture(self, cmd: str) -> str:
        """Execute command and return stdout as text."""
        full_cmd = [
            "apptainer", "exec",
            "--env", f"DISPLAY=:{self._display_num}",
            "--env", "HOME=/home/ga",
            "--env", "USER=ga",
        ]
        env = dict(self.spec.apptainer.env if self.spec.apptainer else {})
        env.update(self.default_exec_env())
        for key, value in env.items():
            full_cmd.extend(["--env", f"{key}={value}"])
        full_cmd.extend([f"instance://{self.instance_name}", "bash", "-c", cmd])
        result = subprocess.run(full_cmd, capture_output=True, timeout=300)
        stdout = result.stdout or b""
        return stdout.decode() if isinstance(stdout, bytes) else stdout

    def exec_capture_bytes(self, cmd: str) -> bytes:
        """Execute command and return stdout as bytes."""
        full_cmd = [
            "apptainer", "exec",
            "--env", f"DISPLAY=:{self._display_num}",
            "--env", "HOME=/home/ga",
            "--env", "USER=ga",
        ]
        env = dict(self.spec.apptainer.env if self.spec.apptainer else {})
        env.update(self.default_exec_env())
        for key, value in env.items():
            full_cmd.extend(["--env", f"{key}={value}"])
        full_cmd.extend([f"instance://{self.instance_name}", "bash", "-c", cmd])
        result = subprocess.run(full_cmd, capture_output=True, timeout=300)
        return result.stdout if isinstance(result.stdout, bytes) else result.stdout.encode()

    # =========================================================================
    # Script Execution (Required by BaseRunner)
    # =========================================================================

    def run_reset(self, reset_script: str, seed: Optional[int] = None) -> None:
        """Execute the environment reset script."""
        env_vars = {}
        if seed is not None:
            env_vars["SEED"] = str(seed)

        cmd = f"bash -lc {shlex.quote(reset_script)}"
        exit_code = self.exec(cmd, env=env_vars)

        if exit_code != 0:
            print(f"[ApptainerDirect] Reset script failed with exit code {exit_code}")

    def run_task_init(self, init_script: str) -> None:
        """Execute the task initialization script."""
        cmd = f"bash -lc {shlex.quote(init_script)}"
        exit_code = self.exec(cmd)

        if exit_code != 0:
            print(f"[ApptainerDirect] Task init script failed with exit code {exit_code}")

    # =========================================================================
    # Action Injection
    # =========================================================================

    def inject_action(self, action: Dict[str, Any]) -> None:
        """Inject keyboard/mouse actions via VNC protocol (works with Qt6 apps).

        VNC-based input injection is preferred because Qt6 apps (like DaVinci Resolve)
        reject synthetic X11 events from xdotool/PyAutoGUI but accept VNC input.
        Falls back to xdotool if VNC is not available.
        """
        mouse = action.get("mouse", {})
        keyboard = action.get("keyboard", {})

        # Try VNC-based input first (Qt6 apps respond to VNC but not synthetic X11 events)
        if self._vnc_pool:
            conn = self._vnc_pool.get_connection(retry_count=3, retry_delay=0.5)
            if conn and conn.is_connected:
                try:
                    self._inject_action_vnc(action, conn)
                    return
                except Exception as e:
                    print(f"[ApptainerDirect] VNC input failed, falling back to xdotool: {e}")

        # Fall back to xdotool
        self._inject_action_xdotool(action)

    def _inject_action_vnc(self, action: Dict[str, Any], conn) -> None:
        """Inject actions via VNC protocol."""
        import time
        mouse = action.get("mouse", {})
        keyboard = action.get("keyboard", {})

        # Mouse actions via VNC
        if "left_click" in mouse:
            x, y = mouse["left_click"]
            conn.send_mouse_click(int(x), int(y), button=1, double=False)

        if "right_click" in mouse:
            x, y = mouse["right_click"]
            conn.send_mouse_click(int(x), int(y), button=3, double=False)

        if "double_click" in mouse:
            x, y = mouse["double_click"]
            conn.send_mouse_click(int(x), int(y), button=1, double=True)

        if "triple_click" in mouse:
            x, y = mouse["triple_click"]
            # Triple click = 3 clicks in quick succession
            for _ in range(3):
                conn.send_mouse_click(int(x), int(y), button=1, double=False)
                time.sleep(0.05)

        if "left_click_drag" in mouse:
            (x1, y1), (x2, y2) = mouse["left_click_drag"]
            conn.send_mouse_drag(int(x1), int(y1), int(x2), int(y2), button=1)

        if "right_click_drag" in mouse:
            (x1, y1), (x2, y2) = mouse["right_click_drag"]
            conn.send_mouse_drag(int(x1), int(y1), int(x2), int(y2), button=3)

        if "move" in mouse:
            x, y = mouse["move"]
            conn.send_mouse_move(int(x), int(y))

        if "scroll" in mouse:
            dy = int(mouse["scroll"])
            # Get current position or use center
            w, h = conn.resolution
            conn.send_scroll(w // 2, h // 2, dy)

        # Keyboard actions via VNC
        if "text" in keyboard:
            text = keyboard["text"]
            conn.type_text(text, delay=0.02)

        if "keys" in keyboard:
            keys = keyboard["keys"]
            if isinstance(keys, str):
                keys = [keys]
            # For key combos, press all keys down, then release in reverse order
            for key in keys:
                conn.send_key(key, down=True)
            for key in reversed(keys):
                conn.send_key(key, down=False)

    def _inject_action_xdotool(self, action: Dict[str, Any]) -> None:
        """Fallback: Inject actions via xdotool (for non-Qt apps)."""
        mouse = action.get("mouse", {})
        keyboard = action.get("keyboard", {})
        display = f":{self._display_num}"

        xdotool_cmds = []

        # Mouse actions via xdotool
        if "left_click" in mouse:
            x, y = mouse["left_click"]
            xdotool_cmds.append(f"xdotool mousemove {int(x)} {int(y)} click 1")

        if "right_click" in mouse:
            x, y = mouse["right_click"]
            xdotool_cmds.append(f"xdotool mousemove {int(x)} {int(y)} click 3")

        if "double_click" in mouse:
            x, y = mouse["double_click"]
            xdotool_cmds.append(f"xdotool mousemove {int(x)} {int(y)} click --repeat 2 --delay 100 1")

        if "triple_click" in mouse:
            x, y = mouse["triple_click"]
            xdotool_cmds.append(f"xdotool mousemove {int(x)} {int(y)} click --repeat 3 --delay 100 1")

        if "left_click_drag" in mouse:
            (x1, y1), (x2, y2) = mouse["left_click_drag"]
            xdotool_cmds.append(f"xdotool mousemove {int(x1)} {int(y1)} mousedown 1 mousemove {int(x2)} {int(y2)} mouseup 1")

        if "right_click_drag" in mouse:
            (x1, y1), (x2, y2) = mouse["right_click_drag"]
            xdotool_cmds.append(f"xdotool mousemove {int(x1)} {int(y1)} mousedown 3 mousemove {int(x2)} {int(y2)} mouseup 3")

        if "move" in mouse:
            x, y = mouse["move"]
            xdotool_cmds.append(f"xdotool mousemove {int(x)} {int(y)}")

        if "scroll" in mouse:
            dy = int(mouse["scroll"])
            if dy > 0:
                xdotool_cmds.append(f"xdotool click --repeat {abs(dy)} 5")  # scroll down
            elif dy < 0:
                xdotool_cmds.append(f"xdotool click --repeat {abs(dy)} 4")  # scroll up

        # Mouse button state
        buttons = mouse.get("buttons", {})
        if buttons.get("left_down"):
            xdotool_cmds.append("xdotool mousedown 1")
        if buttons.get("left_up"):
            xdotool_cmds.append("xdotool mouseup 1")
        if buttons.get("right_down"):
            xdotool_cmds.append("xdotool mousedown 3")
        if buttons.get("right_up"):
            xdotool_cmds.append("xdotool mouseup 3")

        # Keyboard actions via xdotool
        if "text" in keyboard:
            text = keyboard["text"]
            text_escaped = text.replace("'", "'\"'\"'")
            xdotool_cmds.append(f"xdotool type --delay 20 '{text_escaped}'")

        if "keys" in keyboard:
            keys = keyboard["keys"]
            if isinstance(keys, str):
                keys = [keys]
            xdo_keys = [self._normalize_key_xdotool(k) for k in keys]
            key_combo = "+".join(xdo_keys)
            xdotool_cmds.append(f"xdotool key {key_combo}")

        # Execute xdotool commands
        if xdotool_cmds:
            for cmd in xdotool_cmds:
                full_cmd = f"DISPLAY={display} {cmd}"
                self._exec_instance(full_cmd, timeout=30)

    def _normalize_key(self, key: str) -> str:
        """Normalize key names for PyAutoGUI."""
        key_map = {
            "enter": "enter",
            "return": "enter",
            "esc": "escape",
            "escape": "escape",
            "backspace": "backspace",
            "tab": "tab",
            "space": "space",
            "ctrl": "ctrl",
            "control": "ctrl",
            "alt": "alt",
            "shift": "shift",
            "meta": "win",
            "super": "win",
            "cmd": "win",
            "win": "win",
            "delete": "delete",
            "del": "delete",
            "home": "home",
            "end": "end",
            "pageup": "pageup",
            "pagedown": "pagedown",
            "up": "up",
            "down": "down",
            "left": "left",
            "right": "right",
            "f1": "f1", "f2": "f2", "f3": "f3", "f4": "f4",
            "f5": "f5", "f6": "f6", "f7": "f7", "f8": "f8",
            "f9": "f9", "f10": "f10", "f11": "f11", "f12": "f12",
        }
        return key_map.get(key.lower(), key)

    def _normalize_key_xdotool(self, key: str) -> str:
        """Normalize key names for xdotool."""
        key_map = {
            "enter": "Return",
            "return": "Return",
            "esc": "Escape",
            "escape": "Escape",
            "backspace": "BackSpace",
            "tab": "Tab",
            "space": "space",
            "ctrl": "ctrl",
            "control": "ctrl",
            "alt": "alt",
            "shift": "shift",
            "meta": "super",
            "super": "super",
            "cmd": "super",
            "win": "super",
            "delete": "Delete",
            "del": "Delete",
            "home": "Home",
            "end": "End",
            "pageup": "Page_Up",
            "pagedown": "Page_Down",
            "up": "Up",
            "down": "Down",
            "left": "Left",
            "right": "Right",
            "f1": "F1", "f2": "F2", "f3": "F3", "f4": "F4",
            "f5": "F5", "f6": "F6", "f7": "F7", "f8": "F8",
            "f9": "F9", "f10": "F10", "f11": "F11", "f12": "F12",
        }
        return key_map.get(key.lower(), key)

    def _run_pyautogui(self, commands: List[str]) -> None:
        """Execute PyAutoGUI commands inside the container."""
        script = (
            "import pyautogui; "
            "pyautogui.FAILSAFE = False; "
            "pyautogui.PAUSE = 0.01; " +
            "; ".join(commands)
        )
        # Escape for shell
        escaped = script.replace('"', '\\"')
        cmd = f'DISPLAY=:{self._display_num} python3 -c "{escaped}"'

        result = self._exec_instance(cmd, timeout=30)
        if result.returncode != 0:
            stderr = result.stderr[:500] if result.stderr else ""
            print(f"[ApptainerDirect] PyAutoGUI error: {stderr}")

    # =========================================================================
    # Observation Capture
    # =========================================================================

    def capture_observation(self) -> Dict[str, Any]:
        """Capture observation with metadata for configured modalities.

        Returns metadata only; actual screenshots are captured via capture_screenshot().
        """
        obs = {}

        for spec in self.spec.observation:
            if spec.type == "rgb_screen":
                obs["screen"] = {
                    "format": "png",
                    "fps": spec.fps,
                    "resolution": list(spec.resolution) if spec.resolution else list(self._resolution),
                }
            elif spec.type == "audio_waveform":
                obs["audio"] = {
                    "rate": spec.sample_rate or 16000,
                    "channels": spec.channels or 1,
                }
            elif spec.type == "ui_tree":
                obs["ui_tree"] = {"format": "text"}

        return obs

    def capture_screenshot(self, host_path) -> bool:
        """Capture screenshot to host path.

        Priority:
        1. ffmpeg x11grab (includes cursor)
        2. VNC framebuffer (fallback)
        """
        host_path = Path(host_path)
        host_path.parent.mkdir(parents=True, exist_ok=True)

        # Method 1: ffmpeg x11grab (preferred - includes cursor)
        try:
            remote_tmp = f"/tmp/screenshot_{uuid.uuid4().hex[:8]}.png"
            width, height = self._resolution
            display = f":{self._display_num}"

            ffmpeg_cmd = (
                f"ffmpeg -nostdin -y -loglevel error "
                f"-f x11grab -draw_mouse 1 "
                f"-video_size {width}x{height} "
                f"-i {display} "
                f"-vframes 1 {remote_tmp}"
            )

            result = self._exec_instance(ffmpeg_cmd, timeout=30)
            if result.returncode == 0:
                # Copy to host
                self.copy_from(remote_tmp, str(host_path))
                self._exec_instance(f"rm -f {remote_tmp}")
                return True
        except Exception as e:
            print(f"[ApptainerDirect] ffmpeg screenshot failed: {e}")

        # Method 2: VNC fallback
        if self._vnc_pool:
            try:
                conn = self._vnc_pool.get_connection()
                if conn:
                    result = conn.capture_screenshot(save_path=host_path)
                    if result is not None:
                        return True
            except Exception as e:
                print(f"[ApptainerDirect] VNC screenshot failed: {e}")

        # Method 3: scrot fallback
        try:
            remote_tmp = f"/tmp/screenshot_{uuid.uuid4().hex[:8]}.png"
            scrot_cmd = f"DISPLAY=:{self._display_num} scrot {remote_tmp}"
            result = self._exec_instance(scrot_cmd, timeout=30)
            if result.returncode == 0:
                self.copy_from(remote_tmp, str(host_path))
                self._exec_instance(f"rm -f {remote_tmp}")
                return True
        except Exception as e:
            print(f"[ApptainerDirect] scrot screenshot failed: {e}")

        return False

    def capture_audio_raw(self, duration_sec: float, rate: int, channels: int) -> bytes:
        """Capture audio as raw s16le PCM bytes.

        Note: Audio capture requires PulseAudio which may not be available
        in all Apptainer environments. Returns empty bytes if unavailable.
        """
        # Audio capture is challenging in Apptainer without PulseAudio
        # For now, return empty bytes
        print("[ApptainerDirect] Audio capture not implemented for Apptainer")
        return b""

    def capture_ui_tree(self) -> str:
        """Capture UI accessibility tree via xwininfo/xdotool."""
        try:
            result = self._exec_instance(
                f"DISPLAY=:{self._display_num} xwininfo -root -tree 2>/dev/null | head -100"
            )
            return result.stdout if result.stdout else ""
        except:
            return ""

    # =========================================================================
    # File Operations
    # =========================================================================

    def copy_to(self, host_src: str, container_dst: str) -> None:
        """Copy file/directory from host to container."""
        host_src = Path(host_src)
        if not host_src.exists():
            raise FileNotFoundError(f"Source not found: {host_src}")

        # Use work_dir as transfer staging area (ensure Path for / operator)
        transfer_dir = Path(self._work_dir) / "transfer_to"
        transfer_dir.mkdir(exist_ok=True)

        # Copy to transfer dir
        transfer_path = transfer_dir / host_src.name
        if host_src.is_dir():
            if transfer_path.exists():
                shutil.rmtree(transfer_path)
            shutil.copytree(host_src, transfer_path)
        else:
            shutil.copy2(host_src, transfer_path)

        # Move from transfer dir to container destination
        self._exec_instance(f"mkdir -p $(dirname {shlex.quote(container_dst)})")
        self._exec_instance(f"cp -r {shlex.quote(str(transfer_path))} {shlex.quote(container_dst)}")

    def copy_from(self, container_src: str, host_dst: str) -> None:
        """Copy file/directory from container to host."""
        host_dst = Path(host_dst)
        host_dst.parent.mkdir(parents=True, exist_ok=True)

        # Use work_dir as transfer staging area (ensure Path for / operator)
        transfer_dir = Path(self._work_dir) / "transfer_from"
        transfer_dir.mkdir(exist_ok=True)

        # Copy from container to transfer dir
        transfer_path = transfer_dir / Path(container_src).name
        self._exec_instance(f"cp -r {shlex.quote(container_src)} {shlex.quote(str(transfer_path))}")

        # Copy from transfer dir to host destination
        if transfer_path.is_dir():
            if host_dst.exists():
                shutil.rmtree(host_dst)
            shutil.copytree(transfer_path, host_dst)
        else:
            shutil.copy2(transfer_path, host_dst)

    def to_container_path(self, host_path):
        """Map host path to container path.

        For Apptainer with bind mounts, paths are typically the same.
        """
        # Check if path is in artifacts root (which is bind mounted)
        host_path = str(host_path)
        if host_path.startswith(self._artifacts_root):
            return host_path

        # Check spec mounts
        for mount in self.spec.mounts:
            source = os.path.abspath(mount.source)
            if host_path.startswith(source):
                relative = host_path[len(source):]
                return mount.target + relative

        return host_path

    # =========================================================================
    # Checkpoint Support (Basic)
    # =========================================================================

    def set_checkpoint_key(self, cache_level: str, task_id: Optional[str] = None,
                           use_savevm: bool = False) -> None:
        """Set checkpoint key for caching."""
        self._checkpoint_cache_level = cache_level
        self._checkpoint_task_id = task_id
        # Note: use_savevm is ignored for Apptainer (no VM state to save)

    def checkpoint_exists(self) -> bool:
        """Check if checkpoint exists.

        For Apptainer, we could checkpoint the SIF + overlay, but for
        simplicity we return False and rely on fast startup.
        """
        return False

    def create_checkpoint(self) -> bool:
        """Create checkpoint.

        Apptainer doesn't support true VM-style checkpointing.
        """
        return False

    def start_from_checkpoint(self, seed: Optional[int] = None) -> bool:
        """Start from checkpoint.

        Not implemented for Apptainer.
        """
        return False
