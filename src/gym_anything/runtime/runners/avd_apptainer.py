"""
AVD Apptainer Runner for Android Emulation.

Runs the official Android emulator inside Apptainer containers for isolation.
Supports multiple parallel instances through unique port allocation and shared ADB server.

Architecture:
- SDK is cached on host (~/.cache/gym-anything/android-sdk/)
- SDK is bind-mounted into Apptainer container
- Emulator runs inside container with headless flags
- Single shared ADB server runs on host (all emulators auto-register)
- Each instance gets unique ports (console: 5554-5700, adb: console+1)

Parallel Instance Support:
- Each instance gets its own Apptainer container with filesystem isolation
- Emulator uses -read-only flag to share AVD config without conflicts
- Unique port allocation prevents port conflicts between instances
- Shared ADB server on host manages all emulator connections

Checkpoint Support:
- Checkpoints save emulator state (userdata, snapshots) for fast resume
- Checkpoint levels: pre_start, post_start, post_task
- Each checkpoint has its own AVD copy with saved emulator snapshot
- Loading from checkpoint skips SDK setup and hook execution
- Checkpoint cache: ~/.cache/gym-anything/avd-checkpoints/{env_hash}/{level}/
"""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Generator, List, Optional, Tuple

from ...security import wrap_posix_command_with_env
from ...specs import EnvSpec
from .avd_sdk_manager import AVDSDKManager, DEFAULT_CACHE_DIR
from .base import BaseRunner


# Port range for emulator instances
AVD_PORT_RANGE_START = 5554
AVD_PORT_RANGE_END = 5700

# Checkpoint cache directory
AVD_CHECKPOINT_CACHE = Path(os.environ.get(
    "GYM_ANYTHING_AVD_CHECKPOINT_CACHE",
    "~/.cache/gym-anything/avd-checkpoints"
)).expanduser()

# Apptainer container for Android emulator
AVD_CONTAINER_CACHE = Path(os.environ.get(
    "GYM_ANYTHING_AVD_CONTAINER_CACHE",
    "~/.cache/gym-anything/containers"
)).expanduser()
AVD_CONTAINER_SIF = AVD_CONTAINER_CACHE / "avd_emulator.sif"
AVD_CONTAINER_DEF = Path(__file__).parent / "avd_container.def"

# Lock file for port allocation (prevents race conditions in parallel starts)
AVD_PORT_LOCK_FILE = AVD_CHECKPOINT_CACHE.parent / "avd_port_allocation.lock"


def _ensure_avd_container() -> Path:
    """Ensure the AVD container image exists, building if necessary.

    Returns:
        Path to the SIF container image
    """
    if AVD_CONTAINER_SIF.exists():
        return AVD_CONTAINER_SIF

    print("[AVD Runner] Building Apptainer container (one-time setup)...")
    AVD_CONTAINER_CACHE.mkdir(parents=True, exist_ok=True)

    # Build the container from definition file
    result = subprocess.run(
        ["apptainer", "build", str(AVD_CONTAINER_SIF), str(AVD_CONTAINER_DEF)],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"[AVD Runner] Container build failed: {result.stderr}")
        raise RuntimeError(f"Failed to build AVD container: {result.stderr}")

    print(f"[AVD Runner] Container built: {AVD_CONTAINER_SIF}")
    return AVD_CONTAINER_SIF


def _find_free_port_pair(start: int = AVD_PORT_RANGE_START,
                          end: int = AVD_PORT_RANGE_END) -> Tuple[int, int]:
    """Find a free console/adb port pair for emulator.

    Emulator uses consecutive ports: console_port and console_port+1 (adb).
    Uses file locking to prevent race conditions when multiple instances
    start simultaneously.

    Returns:
        Tuple of (console_port, adb_port)
    """
    # Ensure lock directory exists
    AVD_PORT_LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)

    # Use file lock to prevent race conditions in parallel starts
    lock_file = None
    try:
        lock_file = open(AVD_PORT_LOCK_FILE, "w")
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

        for port in range(start, end, 2):
            try:
                # Check both ports are free by actually binding to them
                # We create sockets, bind, and keep them open briefly to reserve
                sockets = []
                for p in [port, port + 1]:
                    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                    s.bind(('localhost', p))
                    sockets.append(s)

                # Close the sockets - ports are now confirmed free
                for s in sockets:
                    s.close()

                return port, port + 1
            except OSError:
                continue

        raise RuntimeError(f"No free port pair found in range {start}-{end}")

    finally:
        if lock_file:
            try:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            except:
                pass
            lock_file.close()


def _check_kvm() -> bool:
    """Check if KVM is available."""
    return os.path.exists("/dev/kvm") and os.access("/dev/kvm", os.R_OK | os.W_OK)


class AVDApptainerRunner(BaseRunner):
    """Runner for Android AVD emulator in Apptainer container.

    This runner:
    1. Ensures Android SDK is installed (cached on host)
    2. Creates/uses an AVD configuration
    3. Launches emulator in Apptainer with headless flags
    4. Connects via ADB for all operations

    Parallel Instance Support:
    - Multiple instances can run simultaneously
    - Each instance gets unique console/adb ports (5554-5700 range)
    - Emulator uses -read-only flag for shared AVD access
    - Single shared ADB server on host manages all instances

    Checkpoint Support:
    - set_checkpoint_key(level, task_id): Set checkpoint to use
    - checkpoint_exists(): Check if checkpoint exists
    - create_checkpoint(): Save current state to checkpoint
    - start_from_checkpoint(): Load from checkpoint (skips hooks)
    - delete_checkpoint(): Remove checkpoint

    Checkpoint saves emulator userdata and snapshot for fast resume.
    """

    def __init__(self, spec: EnvSpec):
        """Initialize AVD runner.

        Args:
            spec: Environment specification
        """
        self.spec = spec
        self.is_android = True

        # Parse AVD configuration from spec
        avd_config = getattr(spec, 'avd', None) or {}
        if isinstance(avd_config, dict):
            self.api_level = avd_config.get('api_level', 35)
            self.variant = avd_config.get('variant', 'google_apis_playstore')
            self.arch = avd_config.get('arch', 'x86_64')
            self.device = avd_config.get('device', 'pixel_6')
        else:
            self.api_level = getattr(avd_config, 'api_level', 35)
            self.variant = getattr(avd_config, 'variant', 'google_apis_playstore')
            self.arch = getattr(avd_config, 'arch', 'x86_64')
            self.device = getattr(avd_config, 'device', 'pixel_6')

        # SDK manager
        self.sdk_manager = AVDSDKManager(DEFAULT_CACHE_DIR)

        # Resources
        mem_val = getattr(spec.resources, 'mem_gb', None) if spec.resources else None
        self.mem_gb = int(mem_val) if mem_val is not None else 4
        cpu_val = getattr(spec.resources, 'cpu', None) if spec.resources else None
        self.cpus = int(cpu_val) if cpu_val is not None else 4
        self.enable_kvm = self._detect_acceleration()

        # Screen resolution
        screen_spec = next((o for o in spec.observation if o.type == "rgb_screen"), None)
        self.resolution = screen_spec.resolution if screen_spec else (1080, 2400)

        # Instance ID and paths
        self._instance_id = f"ga_avd_{uuid.uuid4().hex[:12]}"
        self._avd_name = f"gym_android_{self.api_level}"
        self._work_dir: Optional[Path] = None

        # Ports
        self.console_port: Optional[int] = None
        self.adb_port: Optional[int] = None
        self.vnc_port: Optional[int] = None  # Host port for VNC
        self.vnc_host_port: Optional[int] = None  # Alias for framework compatibility

        # State
        self._running = False
        self._emulator_process: Optional[subprocess.Popen] = None
        self._apptainer_process: Optional[subprocess.Popen] = None

        # Checkpoint support
        self._checkpoint_cache_level: str = "pre_start"
        self._checkpoint_task_id: Optional[str] = None
        self._env_hash: Optional[str] = None
        self._checkpoint_avd_home: Optional[Path] = None  # AVD home for checkpoint instance
        self._loaded_from_checkpoint = False

        # Per-instance AVD home (for parallel instance isolation)
        # Each instance gets its own AVD copy with COW overlays to prevent
        # userdata corruption when running multiple instances in parallel
        self._instance_avd_home: Optional[Path] = None

    def _detect_acceleration(self) -> bool:
        """Detect hardware acceleration. Returns True if available. Subclasses override."""
        return _check_kvm()

    def _ensure_container(self) -> Optional[Path]:
        """Ensure container image exists. Returns path to SIF. Subclasses override (return None)."""
        return _ensure_avd_container()

    def _build_launch_cmd(self, startup_script: Path, container_sif: Optional[Path],
                          sdk_root: str, avd_home: str, android_home: str,
                          work_dir: str) -> List[str]:
        """Build the command to launch the emulator. Subclasses override to remove Apptainer.

        Args:
            startup_script: Path to the shell script that runs the emulator
            container_sif: Path to the Apptainer container image (None for native)
            sdk_root: Android SDK root path
            avd_home: AVD home directory path
            android_home: Android home directory path
            work_dir: Working directory path

        Returns:
            Command list for subprocess.Popen
        """
        cmd = [
            "apptainer", "exec",
            "--compat",
            "--contain",
            "--writable-tmpfs",
            "--no-home",
        ]

        if self.enable_kvm:
            cmd.extend(["--bind", "/dev/kvm"])

        cmd.extend([
            "--bind", sdk_root,
            "--bind", avd_home,
            "--bind", android_home,
            "--bind", work_dir,
            "--bind", "/tmp",
        ])

        cmd.extend([
            "--env", f"ANDROID_SDK_ROOT={sdk_root}",
            "--env", f"ANDROID_AVD_HOME={avd_home}",
            "--env", "ADB_MDNS=0",
        ])

        cmd.append(str(container_sif))
        cmd.append(str(startup_script))
        return cmd

    def supports_checkpoint_caching(self) -> bool:
        return True

    def _compute_env_hash(self) -> str:
        """Compute a hash of the environment configuration for checkpoint naming."""
        if self._env_hash:
            return self._env_hash

        # Create a deterministic hash from env spec
        hash_data = {
            "id": self.spec.id,
            "api_level": self.api_level,
            "variant": self.variant,
            "arch": self.arch,
            "device": self.device,
        }
        hash_str = json.dumps(hash_data, sort_keys=True)
        self._env_hash = hashlib.sha256(hash_str.encode()).hexdigest()[:16]
        return self._env_hash

    def start(self, seed: Optional[int] = None) -> None:
        """Start the AVD emulator.

        Args:
            seed: Random seed (used to differentiate instances)
        """
        print(f"[AVD Runner] Instance: {self._instance_id}")
        print(f"[AVD Runner] KVM: {'enabled' if self.enable_kvm else 'disabled'}")

        # Step 1: Ensure SDK is ready
        print("[AVD Runner] Ensuring SDK components...")
        if not self.sdk_manager.ensure_all(
            api_level=self.api_level,
            variant=self.variant,
            arch=self.arch
        ):
            raise RuntimeError("Failed to install SDK components")

        # Step 2: Create AVD if needed
        print(f"[AVD Runner] Ensuring AVD: {self._avd_name}")
        if not self.sdk_manager.create_avd(
            name=self._avd_name,
            api_level=self.api_level,
            variant=self.variant,
            arch=self.arch,
            device=self.device
        ):
            raise RuntimeError(f"Failed to create AVD: {self._avd_name}")

        # Step 3: Allocate ports
        self.console_port, self.adb_port = _find_free_port_pair()
        print(f"[AVD Runner] Ports: console={self.console_port}, adb={self.adb_port}")

        # Step 4: Create work directory
        self._work_dir = Path(tempfile.mkdtemp(prefix=f"{self._instance_id}_"))
        print(f"[AVD Runner] Work dir: {self._work_dir}")

        # Step 5: Create per-instance AVD copy with COW overlays
        # This prevents userdata corruption when running multiple instances in parallel.
        # Each instance gets its own AVD directory with COW (copy-on-write) overlays
        # for QCOW2 files, making parallel instances isolated and fast to create.
        self._instance_avd_home = self._work_dir / "avd"
        self._instance_avd_home.mkdir(exist_ok=True)
        src_avd_dir = self.sdk_manager.avd_home / f"{self._avd_name}.avd"
        src_avd_ini = self.sdk_manager.avd_home / f"{self._avd_name}.ini"
        dst_avd_dir = self._instance_avd_home / f"{self._avd_name}.avd"
        dst_avd_ini = self._instance_avd_home / f"{self._avd_name}.ini"

        print(f"[AVD Runner] Creating per-instance AVD copy with COW overlays...")
        self._create_avd_cow_copy(src_avd_dir, dst_avd_dir)

        # Copy and update the AVD ini file to point to the instance directory
        if src_avd_ini.exists():
            with open(src_avd_ini) as f:
                ini_content = f.read()
            # Update path in ini file to point to per-instance directory
            ini_content = ini_content.replace(
                str(self.sdk_manager.avd_home),
                str(self._instance_avd_home)
            )
            with open(dst_avd_ini, "w") as f:
                f.write(ini_content)
        print(f"[AVD Runner] Per-instance AVD ready at: {self._instance_avd_home}")

        # Step 6: Launch emulator
        self._launch_emulator()

        # Step 6: Wait for boot
        if not self._wait_for_boot(timeout=300):
            self._dump_log()
            self.stop()
            raise RuntimeError("Emulator failed to boot")

        self._running = True
        print(f"[AVD Runner] Emulator ready! ADB device: emulator-{self.console_port}")

        # Step 7: Set up mounts (push scripts/tasks to device via adb)
        self._setup_mounts_adb()

        # Step 8: Install APKs from env spec (uses adb install - much faster than push + pm install)
        self._install_apks_from_spec()

        # Step 9: Set up VNC server for interactive access
        self._setup_vnc()

        # Step 10: Apply Android system settings (like disabling immersive mode confirmations)
        self._apply_android_settings()

    def _launch_emulator(self) -> None:
        """Launch the Android emulator inside Apptainer container.

        Uses Apptainer for full filesystem isolation (--contain).
        A single shared ADB server runs on the host, and all emulators
        auto-register with it using their unique port allocations.

        Each instance uses its own per-instance AVD copy (created in start())
        with COW overlays, ensuring parallel instances don't corrupt each other's
        userdata. The -read-only flag is also used for additional protection.
        """
        # Ensure container image exists (returns None for native runner)
        container_sif = self._ensure_container()

        # Ensure ADB server is running on host (idempotent - won't restart if already running)
        env = os.environ.copy()
        env["ADB_MDNS"] = "0"
        subprocess.run(
            [str(self.sdk_manager.adb), "start-server"],
            capture_output=True, env=env
        )

        # Build paths for bind mounts
        sdk_root = str(self.sdk_manager.sdk_root.absolute())
        avd_home = str(self._instance_avd_home.absolute())
        android_home = str(self._instance_avd_home.parent.absolute())
        work_dir = str(self._work_dir.absolute())

        # Build emulator arguments
        startup_script = self._work_dir / "start_emulator.sh"
        emulator_args = [
            "-avd", self._avd_name,
            "-port", str(self.console_port),
            "-no-window", "-no-audio", "-no-boot-anim",
            "-no-snapshot-save", "-no-snapshot-load",
            "-read-only", "-no-metrics",
            "-gpu", "swiftshader_indirect",
            "-memory", str(self.mem_gb * 1024),
            "-cores", str(self.cpus),
        ]
        if self.enable_kvm:
            emulator_args.extend(["-accel", "on"])
        else:
            emulator_args.extend(["-accel", "off"])
        if self.resolution:
            width, height = self.resolution
            emulator_args.extend(["-skin", f"{width}x{height}"])

        script_content = f"""#!/bin/bash
export HOME=/tmp
export ADB_MDNS=0
export ANDROID_SDK_ROOT={sdk_root}
export ANDROID_AVD_HOME={avd_home}

# Run emulator (exec replaces shell process)
exec {self.sdk_manager.emulator_bin} {' '.join(emulator_args)}
"""
        startup_script.write_text(script_content)
        startup_script.chmod(0o755)

        # Build launch command (Apptainer-wrapped or direct, depending on subclass)
        launch_cmd = self._build_launch_cmd(
            startup_script, container_sif,
            sdk_root, avd_home, android_home, work_dir
        )

        print(f"[AVD Runner] Launching emulator...")
        print(f"[AVD Runner] Ports: console={self.console_port}, adb={self.adb_port}")

        log_file = self._work_dir / "emulator.log"
        with open(log_file, "w") as lf:
            self._emulator_process = subprocess.Popen(
                launch_cmd,
                stdout=lf,
                stderr=subprocess.STDOUT,
                preexec_fn=os.setsid
            )

        # Give emulator a moment to start
        time.sleep(5)

        # Check if process is still running
        if self._emulator_process.poll() is not None:
            print(f"[AVD Runner] Emulator exited immediately with code: {self._emulator_process.returncode}")
            self._dump_log()
            raise RuntimeError("Emulator failed to start")

    def _wait_for_boot(self, timeout: int = 300) -> bool:
        """Wait for emulator to fully boot.

        Args:
            timeout: Maximum wait time in seconds

        Returns:
            True if boot completed, False on timeout
        """
        print(f"[AVD Runner] Waiting for boot (timeout={timeout}s)...")
        start_time = time.time()
        device_name = f"emulator-{self.console_port}"

        # Environment with mDNS disabled (for InfiniBand compatibility)
        env = os.environ.copy()
        env["ADB_MDNS"] = "0"

        # First, wait for device to appear in ADB
        while time.time() - start_time < timeout:
            try:
                result = subprocess.run(
                    [str(self.sdk_manager.adb), "devices"],
                    capture_output=True,
                    text=True,
                    timeout=10,
                    env=env
                )
                if device_name in result.stdout and "device" in result.stdout:
                    break
            except Exception:
                pass

            # Check if emulator is still running
            if self._emulator_process and self._emulator_process.poll() is not None:
                print("[AVD Runner] Emulator process died")
                return False

            time.sleep(2)
        else:
            print("[AVD Runner] Timeout waiting for device to appear in ADB")
            return False

        print(f"[AVD Runner] Device appeared in ADB ({time.time() - start_time:.1f}s)")

        # Now wait for boot to complete
        while time.time() - start_time < timeout:
            try:
                result = subprocess.run(
                    [str(self.sdk_manager.adb), "-s", device_name,
                     "shell", "getprop", "sys.boot_completed"],
                    capture_output=True,
                    text=True,
                    timeout=10,
                    env=env
                )
                if result.stdout.strip() == "1":
                    elapsed = time.time() - start_time
                    print(f"[AVD Runner] Boot completed ({elapsed:.1f}s)")
                    return True
            except Exception:
                pass

            time.sleep(2)

        print("[AVD Runner] Timeout waiting for boot completion")
        return False

    def _dump_log(self) -> None:
        """Print emulator log for debugging."""
        if self._work_dir:
            log_file = self._work_dir / "emulator.log"
            if log_file.exists():
                print("[AVD Runner] === Emulator Log ===")
                print(log_file.read_text()[-5000:])  # Last 5000 chars
                print("[AVD Runner] === End Log ===")

    def _setup_mounts_adb(self) -> None:
        """Setup mounts for Android via ADB push.

        Copies files from host to device using adb push.
        This mimics the mount behavior for Android where we can't use file mounts.
        """
        mounts = getattr(self.spec, "mounts", [])
        if not mounts:
            return

        # Wait for storage to be ready after boot
        print("[AVD Runner] Waiting for storage to be ready...")
        time.sleep(5)

        print(f"[AVD Runner] Setting up {len(mounts)} mounts via ADB...")

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
                print(f"[AVD Runner] Mount source not found: {source_path}")
                continue

            # Push files to Android - create target dir first and push contents
            print(f"[AVD Runner] Pushing {source_path} -> {target}")

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
                            print(f"[AVD Runner] ADB push failed for {file_path.name}: {result.stderr.decode()}")
            else:
                # Single file push
                result = self._adb_command(["push", str(source_path), target])
                if result.returncode != 0:
                    print(f"[AVD Runner] ADB push failed: {result.stderr.decode()[:200]}")

    def _install_apks_from_spec(self) -> None:
        """Install APKs listed in env spec.

        Looks for an "apks" field in the spec, which should be a list of APK paths
        relative to the env directory. Uses adb install (streaming) which is much
        faster than pushing to /sdcard and using pm install.

        Example env.json:
            {
                "apks": [
                    "scripts/apks/myapp.apk",
                    "scripts/apks/dependency.apk"
                ]
            }
        """
        apks = getattr(self.spec, 'apks', None)
        if not apks:
            return

        print(f"[AVD Runner] Installing {len(apks)} APK(s) from spec...")

        for apk_path in apks:
            # Resolve path relative to current directory (env directory)
            apk_file = Path(apk_path)
            if not apk_file.is_absolute():
                apk_file = Path.cwd() / apk_file

            if not apk_file.exists():
                print(f"[AVD Runner] Warning: APK not found: {apk_file}")
                continue

            print(f"[AVD Runner] Installing APK: {apk_file.name} ({apk_file.stat().st_size / 1024 / 1024:.1f} MB)")

            # Use install_apk which uses adb install (streaming, much faster)
            if self.install_apk(str(apk_file)):
                print(f"[AVD Runner] Successfully installed: {apk_file.name}")
            else:
                print(f"[AVD Runner] Warning: Failed to install: {apk_file.name}")

    def _setup_vnc(self) -> None:
        """Set up VNC server for interactive access."""
        print("[AVD Runner] Setting up VNC server...")

        try:
            # Step 1: Download VNC APK if needed
            vnc_apk = self.sdk_manager.ensure_vnc_server_apk()
            if not vnc_apk or not vnc_apk.exists():
                print("[AVD Runner] Warning: Could not download VNC server APK")
                return

            # Step 2: Install VNC APK
            if not self.install_apk(str(vnc_apk)):
                print("[AVD Runner] Warning: Could not install VNC server APK")
                return

            # Step 3: Start VNC server
            if not self.start_vnc_server(port=5900, password="password"):
                print("[AVD Runner] Warning: Could not start VNC server")
                return

            # Step 4: Forward VNC port
            host_port = self.forward_vnc_port()
            self.vnc_host_port = host_port  # Set for framework compatibility
            print(f"[AVD Runner] VNC available at localhost:{host_port} (password: password)")

        except Exception as e:
            print(f"[AVD Runner] Warning: VNC setup failed: {e}")
            # VNC is non-critical, don't fail the startup

    def _apply_android_settings(self) -> None:
        """Apply Android system settings for better automation.

        This includes:
        - Disabling immersive mode confirmation notifications
        - Other settings that improve automation reliability
        """
        print("[AVD Runner] Applying Android settings for automation...")

        try:
            # Disable immersive mode confirmation ("Viewing full screen" notification)
            # This notification appears when apps enter fullscreen mode
            self._adb_command(['shell', 'settings', 'put', 'secure', 'immersive_mode_confirmations', 'confirmed'])

            # Set policy control for immersive mode
            self._adb_command(['shell', 'settings', 'put', 'global', 'policy_control', 'immersive.full=*'])

        except Exception as e:
            print(f"[AVD Runner] Warning: Could not apply Android settings: {e}")

    def _adb_command(self, args: List[str], timeout: int = 60) -> subprocess.CompletedProcess:
        """Run an ADB command targeting this emulator.

        Args:
            args: ADB arguments (after -s <device>)
            timeout: Command timeout

        Returns:
            CompletedProcess result
        """
        device_name = f"emulator-{self.console_port}"
        cmd = [str(self.sdk_manager.adb), "-s", device_name] + args
        # Disable mDNS to avoid InfiniBand interface compatibility issues
        env = os.environ.copy()
        env["ADB_MDNS"] = "0"
        return subprocess.run(cmd, capture_output=True, timeout=timeout, env=env)

    def stop(self) -> None:
        """Stop the emulator and cleanup."""
        print(f"[AVD Runner] Stopping {self._instance_id}")
        self._running = False

        # Environment with mDNS disabled
        env = os.environ.copy()
        env["ADB_MDNS"] = "0"

        # Kill emulator via ADB
        if self.console_port:
            try:
                device_name = f"emulator-{self.console_port}"
                subprocess.run(
                    [str(self.sdk_manager.adb), "-s", device_name, "emu", "kill"],
                    capture_output=True,
                    timeout=10,
                    env=env
                )
            except Exception:
                pass

        # Kill emulator process
        if self._emulator_process:
            try:
                os.killpg(os.getpgid(self._emulator_process.pid), signal.SIGTERM)
                self._emulator_process.wait(timeout=10)
            except Exception:
                try:
                    os.killpg(os.getpgid(self._emulator_process.pid), signal.SIGKILL)
                except Exception:
                    pass
            self._emulator_process = None

        # Cleanup work directory
        if self._work_dir and self._work_dir.exists():
            try:
                shutil.rmtree(self._work_dir)
            except Exception:
                pass

        print(f"[AVD Runner] Stopped")

    def capture_screenshot(self, dest_path) -> bool:
        """Capture screenshot via ADB.

        Args:
            dest_path: Local path to save screenshot (can be str or Path)

        Returns:
            True if screenshot was captured successfully
        """
        dest_path = str(dest_path)  # Handle Path objects
        remote_path = "/sdcard/ga_screenshot.png"

        # Capture on device
        result = self._adb_command(["shell", "screencap", "-p", remote_path])
        if result.returncode != 0:
            print(f"[AVD Runner] screencap failed: {result.stderr.decode()}")
            return False

        # Pull to local
        result = self._adb_command(["pull", remote_path, dest_path])
        if result.returncode != 0:
            print(f"[AVD Runner] adb pull failed: {result.stderr.decode()}")
            return False

        # Cleanup remote
        self._adb_command(["shell", "rm", remote_path])
        return True

    def inject_action(self, action: Dict[str, Any]) -> None:
        """Inject input action via ADB.

        Uses the same action format as QEMUApptainerRunner for consistency.
        Supports: {"mouse": {"left_click": [x, y]}} and {"keyboard": {"text": "..."}}

        Args:
            action: Action dict with mouse/keyboard parameters
        """
        mouse = action.get("mouse")
        if mouse:
            if "left_click" in mouse:
                x, y = mouse["left_click"]
                self._adb_command(["shell", "input", "tap", str(int(x)), str(int(y))])
            if "right_click" in mouse:
                # Android doesn't have right-click, treat as long press
                x, y = mouse["right_click"]
                self._adb_command(["shell", "input", "swipe",
                                   str(int(x)), str(int(y)),
                                   str(int(x)), str(int(y)), "1000"])
            if "double_click" in mouse:
                x, y = mouse["double_click"]
                # Double tap for double click
                self._adb_command(["shell", "input", "tap", str(int(x)), str(int(y))])
                time.sleep(0.1)
                self._adb_command(["shell", "input", "tap", str(int(x)), str(int(y))])
            if "triple_click" in mouse:
                x, y = mouse["triple_click"]
                for _ in range(3):
                    self._adb_command(["shell", "input", "tap", str(int(x)), str(int(y))])
                    time.sleep(0.1)
            if "left_click_drag" in mouse:
                (x1, y1), (x2, y2) = mouse["left_click_drag"]
                # ADB swipe: input swipe x1 y1 x2 y2 [duration_ms]
                self._adb_command(["shell", "input", "swipe",
                                   str(int(x1)), str(int(y1)),
                                   str(int(x2)), str(int(y2)), "500"])
            if "move" in mouse:
                # Android doesn't have mouse move - no-op
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
                    "space": "KEYCODE_SPACE",
                    "up": "KEYCODE_DPAD_UP",
                    "down": "KEYCODE_DPAD_DOWN",
                    "left": "KEYCODE_DPAD_LEFT",
                    "right": "KEYCODE_DPAD_RIGHT",
                }

                for key in keys:
                    key_lower = key.lower()
                    if key_lower in keycode_map:
                        keycode = keycode_map[key_lower]
                    else:
                        # Try as direct keycode
                        keycode = f"KEYCODE_{key.upper()}"
                    self._adb_command(["shell", "input", "keyevent", keycode])

    def exec(
        self,
        cmd: str,
        env: Optional[Dict[str, str]] = None,
        user: Optional[str] = None,
        use_pty: bool = True,
        timeout: int = 60,
    ) -> int:
        """Execute command on device via ADB shell.

        Args:
            cmd: Shell command to execute
            timeout: Command timeout

        Returns:
            Exit code
        """
        del user, use_pty
        cmd = wrap_posix_command_with_env(cmd, self.merge_exec_env(env), export=True)
        result = self._adb_command(["shell", cmd], timeout=timeout)
        return result.returncode

    def exec_capture(self, cmd: str, timeout: int = 60) -> str:
        """Execute command and capture output.

        Args:
            cmd: Shell command to execute
            timeout: Command timeout

        Returns:
            Command stdout
        """
        cmd = wrap_posix_command_with_env(cmd, self.default_exec_env(), export=True)
        result = self._adb_command(["shell", cmd], timeout=timeout)
        return result.stdout.decode('utf-8', errors='replace')

    def exec_capture_bytes(self, cmd: str, timeout: int = 60) -> bytes:
        """Execute command and capture raw bytes output.

        Args:
            cmd: Shell command to execute
            timeout: Command timeout

        Returns:
            Command stdout as bytes
        """
        cmd = wrap_posix_command_with_env(cmd, self.default_exec_env(), export=True)
        result = self._adb_command(["shell", cmd], timeout=timeout)
        return result.stdout

    def copy_to(self, local_path: str, remote_path: str) -> None:
        """Copy file to device via ADB push.

        Args:
            local_path: Local file path
            remote_path: Remote path on device
        """
        result = self._adb_command(["push", local_path, remote_path])
        if result.returncode != 0:
            raise RuntimeError(f"adb push failed: {result.stderr.decode()}")

    def install_apk(self, apk_path: str, reinstall: bool = True) -> bool:
        """Install APK on device via ADB.

        Args:
            apk_path: Path to APK file
            reinstall: If True, reinstall if already exists

        Returns:
            True if installation succeeded
        """
        args = ["install"]
        if reinstall:
            args.append("-r")
        args.append(apk_path)

        result = self._adb_command(args, timeout=120)
        if result.returncode != 0:
            print(f"[AVD Runner] APK install failed: {result.stderr.decode()[:200]}")
            return False
        return True

    def start_vnc_server(self, port: int = 5900, password: str = "password") -> bool:
        """Start VNC server on device (requires droidVNC-NG installed).

        Args:
            port: VNC port inside device
            password: VNC password

        Returns:
            True if server started
        """
        try:
            # Step 1: Start the droidVNC-NG app
            self._adb_command([
                "shell", "am", "start", "-n",
                "net.christianbeier.droidvnc_ng/.MainActivity"
            ])
            time.sleep(2)

            # Step 2: Click the "Start" toggle button in the app
            # The Start button is typically in the upper portion of the screen
            self._adb_command(["shell", "input", "tap", "540", "400"])
            time.sleep(1)

            # Step 3: Handle the MediaProjection permission dialog
            # The "Start now" button appears in a system dialog
            # Wait for dialog to appear
            time.sleep(1)

            # Click "Start now" button (usually in bottom right of dialog)
            # On 1080x2400 display, this is approximately:
            self._adb_command(["shell", "input", "tap", "850", "1340"])
            time.sleep(2)

            # Verify VNC is listening by checking the port
            result = self._adb_command(["shell", "netstat -tlpn 2>/dev/null | grep 5900 || ss -tlpn 2>/dev/null | grep 5900"])
            if b"5900" in result.stdout:
                self._vnc_port_device = port
                print(f"[AVD Runner] VNC server started on device port {port}")
                return True

            # If first attempt failed, try broadcast method as fallback
            self._adb_command([
                "shell", "am", "broadcast", "-a",
                "net.christianbeier.droidvnc_ng.START",
                "-e", "password", password,
                "-e", "port", str(port)
            ])
            time.sleep(2)

            # Check again
            result = self._adb_command(["shell", "netstat -tlpn 2>/dev/null | grep 5900 || ss -tlpn 2>/dev/null | grep 5900"])
            if b"5900" in result.stdout:
                self._vnc_port_device = port
                print(f"[AVD Runner] VNC server started on device port {port}")
                return True

            print(f"[AVD Runner] VNC server may not have started - continuing anyway")
            self._vnc_port_device = port
            return True  # Return True anyway, VNC is optional for debugging

        except Exception as e:
            print(f"[AVD Runner] Failed to start VNC server: {e}")
            return False

    def forward_vnc_port(self, host_port: int = None) -> int:
        """Forward VNC port from device to host.

        Args:
            host_port: Host port to use (auto-assign if None)

        Returns:
            Host port number
        """
        if host_port is None:
            # Find free port
            import socket
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('', 0))
                host_port = s.getsockname()[1]

        device_port = getattr(self, '_vnc_port_device', 5900)
        result = self._adb_command([
            "forward", f"tcp:{host_port}", f"tcp:{device_port}"
        ])

        if result.returncode == 0:
            self.vnc_port = host_port
            print(f"[AVD Runner] VNC forwarded: localhost:{host_port} -> device:{device_port}")
            return host_port
        else:
            raise RuntimeError(f"Failed to forward VNC port: {result.stderr.decode()}")

    def copy_from(self, remote_path: str, local_path: str) -> None:
        """Copy file from device via ADB pull.

        Args:
            remote_path: Remote path on device
            local_path: Local file path
        """
        result = self._adb_command(["pull", remote_path, local_path])
        if result.returncode != 0:
            raise RuntimeError(f"adb pull failed: {result.stderr.decode()}")

    def put_file(self, local_path: Path, remote_dir: str = "/sdcard") -> str:
        """Copy file to device and return remote path.

        Args:
            local_path: Local file path
            remote_dir: Remote directory

        Returns:
            Remote file path
        """
        remote_path = f"{remote_dir}/{local_path.name}"
        self.copy_to(str(local_path), remote_path)
        return remote_path

    def to_container_path(self, path: Path) -> str:
        """Convert local path to device path (for compatibility).

        Args:
            path: Local path

        Returns:
            Device path (unchanged for AVD)
        """
        return str(path)

    def run_reset(self, reset_script: str, seed: Optional[int] = None) -> None:
        """Run reset script on device.

        Args:
            reset_script: Shell command to execute
            seed: Optional seed (passed as environment variable)
        """
        if seed is not None:
            self.exec(reset_script, env={"SEED": str(seed)}, timeout=60)
        else:
            self.exec(reset_script, timeout=60)

    def run_task_init(self, init_script: str) -> None:
        """Run task initialization script.

        Args:
            init_script: Shell command to execute
        """
        result = self._adb_command(
            ["shell", wrap_posix_command_with_env(init_script, self.default_exec_env(), export=True)],
            timeout=120,
        )
        if result.returncode != 0:
            stderr = result.stderr.decode('utf-8', errors='replace')
            print(f"[AVD Runner] Task init warning: {stderr[:200]}")

    def capture_observation(self) -> Dict[str, Any]:
        """Capture current observation.

        Returns:
            Dict with observation data keyed by type
        """
        obs = {}

        for obs_spec in self.spec.observation:
            if obs_spec.type == "rgb_screen":
                # Capture screenshot
                import tempfile
                with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
                    temp_path = f.name
                try:
                    self.capture_screenshot(temp_path)
                    with open(temp_path, "rb") as f:
                        obs["rgb_screen"] = f.read()
                finally:
                    try:
                        os.remove(temp_path)
                    except:
                        pass

            elif obs_spec.type == "ui_tree":
                # Capture UI tree via uiautomator
                try:
                    self._adb_command(["shell", "uiautomator", "dump", "/sdcard/ui_tree.xml"])
                    result = self._adb_command(["shell", "cat", "/sdcard/ui_tree.xml"])
                    obs["ui_tree"] = result.stdout.decode('utf-8', errors='replace')
                except:
                    obs["ui_tree"] = ""

        return obs

    def capture_ui_tree(self) -> str:
        """Capture UI accessibility tree.

        Returns:
            XML string of UI hierarchy
        """
        try:
            self._adb_command(["shell", "uiautomator", "dump", "/sdcard/ui_tree.xml"])
            result = self._adb_command(["shell", "cat", "/sdcard/ui_tree.xml"])
            return result.stdout.decode('utf-8', errors='replace')
        except:
            return ""

    def get_session_info(self) -> Dict[str, Any]:
        """Get session information.

        Returns:
            Session info dict
        """
        return {
            "runner": "avd",
            "instance": self._instance_id,
            "avd_name": self._avd_name,
            "console_port": self.console_port,
            "adb_port": self.adb_port,
            "api_level": self.api_level,
            "resolution": list(self.resolution),
            "kvm_enabled": self.enable_kvm,
        }

    # === Audio Capture (API Compatibility) ===

    def capture_audio_raw(self, duration_ms: int = 200) -> bytes:
        """Capture audio from device.

        Note: Audio capture is not directly supported on Android AVD.
        This method returns empty bytes for API compatibility with
        the QEMU runner interface.

        Args:
            duration_ms: Duration to capture (ignored)

        Returns:
            Empty bytes (audio not supported)
        """
        return b""

    # === Runtime State Management ===
    #
    # These methods provide runtime snapshot support using the Android
    # emulator's built-in snapshot feature. Unlike checkpoints (which
    # are for caching between runs), these are for saving/restoring
    # state during a single session.
    #
    # Note: Snapshots capture port/network state. Loading a snapshot
    # saved with a different port allocation may cause issues.

    def save_state(self, name: str = "quicksave") -> bool:
        """Save emulator state snapshot.

        Creates a snapshot of the current emulator state that can be
        restored later with load_state(). Useful for saving progress
        during task execution.

        Note: Snapshots are stored in the AVD directory and persist
        across emulator restarts (within the same AVD).

        Args:
            name: Snapshot name (default: "quicksave")

        Returns:
            True if snapshot was saved successfully
        """
        if not self._running:
            print("[AVD Runner] Cannot save state: emulator not running")
            return False

        print(f"[AVD Runner] Saving snapshot: {name}")
        result = self._adb_command(["emu", "avd", "snapshot", "save", name], timeout=120)

        if result.returncode == 0:
            print(f"[AVD Runner] Snapshot saved: {name}")
            return True
        else:
            print(f"[AVD Runner] Failed to save snapshot: {result.stderr.decode()}")
            return False

    def load_state(self, name: str = "quicksave") -> bool:
        """Load emulator state snapshot.

        Restores a previously saved snapshot. The emulator state will
        be restored to exactly how it was when the snapshot was saved.

        Warning: Loading a snapshot saved with a different port allocation
        may cause connectivity issues. This is best used for snapshots
        created during the current session.

        Args:
            name: Snapshot name to load (default: "quicksave")

        Returns:
            True if snapshot was loaded successfully
        """
        if not self._running:
            print("[AVD Runner] Cannot load state: emulator not running")
            return False

        print(f"[AVD Runner] Loading snapshot: {name}")
        result = self._adb_command(["emu", "avd", "snapshot", "load", name], timeout=120)

        if result.returncode == 0:
            print(f"[AVD Runner] Snapshot loaded: {name}")
            # Give emulator time to stabilize after snapshot load
            time.sleep(2)
            return True
        else:
            print(f"[AVD Runner] Failed to load snapshot: {result.stderr.decode()}")
            return False

    def list_snapshots(self) -> List[str]:
        """List available emulator snapshots.

        Returns:
            List of snapshot names available in this AVD
        """
        if not self._running:
            print("[AVD Runner] Cannot list snapshots: emulator not running")
            return []

        result = self._adb_command(["emu", "avd", "snapshot", "list"], timeout=30)

        if result.returncode != 0:
            return []

        # Parse snapshot list from output
        # Format: "ID  TAG  VM SIZE  DATE  VM CLOCK  ICOUNT"
        # or just snapshot names depending on emulator version
        snapshots = []
        output = result.stdout.decode('utf-8', errors='replace')

        for line in output.strip().split('\n'):
            line = line.strip()
            if not line or line.startswith('ID') or line.startswith('-'):
                continue
            # Extract snapshot name (first column or whole line)
            parts = line.split()
            if parts:
                snapshots.append(parts[0])

        return snapshots

    def delete_snapshot(self, name: str) -> bool:
        """Delete an emulator snapshot.

        Args:
            name: Snapshot name to delete

        Returns:
            True if snapshot was deleted successfully
        """
        if not self._running:
            print("[AVD Runner] Cannot delete snapshot: emulator not running")
            return False

        print(f"[AVD Runner] Deleting snapshot: {name}")
        result = self._adb_command(["emu", "avd", "snapshot", "delete", name], timeout=60)

        if result.returncode == 0:
            print(f"[AVD Runner] Snapshot deleted: {name}")
            return True
        else:
            print(f"[AVD Runner] Failed to delete snapshot: {result.stderr.decode()}")
            return False

    # === Checkpoint Support ===
    #
    # Checkpointing for AVD works by saving the emulator's userdata and snapshot state.
    # Each checkpoint gets its own AVD home directory with saved state.
    #
    # Checkpoint structure:
    #   ~/.cache/gym-anything/avd-checkpoints/{env_hash}/
    #     {cache_level}/                    # pre_start, post_start, or post_task_{task_id}
    #       avd/                            # AVD home directory copy
    #         gym_android_{api}.avd/        # AVD with saved snapshot
    #         gym_android_{api}.ini
    #       metadata.json                   # Checkpoint metadata

    def set_checkpoint_key(self, cache_level: str, task_id: Optional[str] = None, use_savevm: bool = False) -> None:
        """Set the checkpoint key components.

        This determines which checkpoint to look for/create.
        Must be called before checkpoint_exists(), create_checkpoint(), or start_from_checkpoint().

        Args:
            cache_level: One of "pre_start", "post_start", "post_task"
            task_id: Task ID (only relevant for post_task level)
            use_savevm: Ignored for AVD runner (savevm is QEMU-specific)
        """
        self._checkpoint_cache_level = cache_level
        self._checkpoint_task_id = task_id

    def _get_checkpoint_dir(self) -> Path:
        """Get the checkpoint directory based on current checkpoint key.

        Checkpoint naming:
        - pre_start:  {env_hash}/pre_start/
        - post_start: {env_hash}/post_start/
        - post_task:  {env_hash}/post_task_{task_id}/
        """
        env_hash = self._compute_env_hash()
        level = self._checkpoint_cache_level

        if level == "post_task" and self._checkpoint_task_id:
            safe_task_id = self._checkpoint_task_id.replace("/", "_").replace("@", "_")
            return AVD_CHECKPOINT_CACHE / env_hash / f"post_task_{safe_task_id}"
        else:
            return AVD_CHECKPOINT_CACHE / env_hash / level

    def _get_checkpoint_lock_path(self) -> Path:
        """Get the lock file path for the current checkpoint."""
        return self._get_checkpoint_dir().with_suffix(".lock")

    @contextmanager
    def _checkpoint_lock(self, blocking: bool = True, timeout: float = 300.0) -> Generator[bool, None, None]:
        """Acquire an exclusive lock for checkpoint operations.

        Prevents race conditions when multiple processes try to create
        or load the same checkpoint simultaneously.
        """
        lock_path = self._get_checkpoint_lock_path()
        lock_path.parent.mkdir(parents=True, exist_ok=True)

        lock_file = None
        acquired = False
        try:
            lock_file = open(lock_path, "w")

            if blocking:
                start_time = time.time()
                while time.time() - start_time < timeout:
                    try:
                        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                        acquired = True
                        break
                    except (IOError, OSError):
                        time.sleep(0.5)
                if not acquired:
                    print(f"[AVD Runner] Timeout waiting for checkpoint lock: {lock_path}")
            else:
                try:
                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                    acquired = True
                except (IOError, OSError):
                    pass

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
        checkpoint_dir = self._get_checkpoint_dir()
        metadata_file = checkpoint_dir / "metadata.json"
        exists = metadata_file.exists()
        if exists:
            print(f"[AVD Runner] Checkpoint found: {checkpoint_dir}")
        return exists

    def create_checkpoint(self) -> bool:
        """Create checkpoint by saving emulator state.

        This saves:
        1. AVD userdata (installed apps, settings)
        2. Emulator snapshot for fast resume

        The checkpoint can be loaded on subsequent runs to skip hooks.
        """
        if not self._running:
            print("[AVD Runner] Cannot create checkpoint: emulator not running")
            return False

        checkpoint_dir = self._get_checkpoint_dir()
        print(f"[AVD Runner] Creating checkpoint: {checkpoint_dir}")
        print(f"[AVD Runner]   cache_level={self._checkpoint_cache_level}, task_id={self._checkpoint_task_id}")

        with self._checkpoint_lock(blocking=True, timeout=600.0) as acquired:
            if not acquired:
                print("[AVD Runner] Could not acquire checkpoint lock, aborting")
                return False

            # Check if another process created it while we waited
            if (checkpoint_dir / "metadata.json").exists():
                print(f"[AVD Runner] Checkpoint already exists (created by another process)")
                return True

            try:
                # Create checkpoint directory
                checkpoint_dir.mkdir(parents=True, exist_ok=True)
                checkpoint_avd_dir = checkpoint_dir / "avd"
                checkpoint_avd_dir.mkdir(exist_ok=True)

                # Save emulator snapshot (for fast resume)
                snapshot_name = "gym_checkpoint"
                print(f"[AVD Runner] Saving emulator snapshot: {snapshot_name}")
                result = self._adb_command(["emu", "avd", "snapshot", "save", snapshot_name])
                if result.returncode != 0:
                    print(f"[AVD Runner] Warning: Snapshot save may have failed: {result.stderr.decode()}")

                # Give emulator time to write snapshot
                time.sleep(3)

                # Copy AVD state to checkpoint
                # The AVD directory contains userdata, cache, and snapshots
                # Use the per-instance AVD home (which has the current running state)
                # Fall back to checkpoint AVD home if loaded from checkpoint
                src_avd_home = self._instance_avd_home or self._checkpoint_avd_home or self.sdk_manager.avd_home
                src_avd_dir = src_avd_home / f"{self._avd_name}.avd"
                src_avd_ini = src_avd_home / f"{self._avd_name}.ini"

                dst_avd_dir = checkpoint_avd_dir / f"{self._avd_name}.avd"
                dst_avd_ini = checkpoint_avd_dir / f"{self._avd_name}.ini"

                print(f"[AVD Runner] Copying AVD state to checkpoint...")

                # Copy AVD directory (contains userdata, snapshots)
                if dst_avd_dir.exists():
                    shutil.rmtree(dst_avd_dir)
                shutil.copytree(src_avd_dir, dst_avd_dir, symlinks=True)

                # Copy AVD ini file
                if src_avd_ini.exists():
                    shutil.copy2(src_avd_ini, dst_avd_ini)

                # Write metadata
                metadata = {
                    "env_id": self.spec.id,
                    "env_hash": self._compute_env_hash(),
                    "cache_level": self._checkpoint_cache_level,
                    "task_id": self._checkpoint_task_id,
                    "api_level": self.api_level,
                    "variant": self.variant,
                    "avd_name": self._avd_name,
                    "snapshot_name": snapshot_name,
                    "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                }
                with open(checkpoint_dir / "metadata.json", "w") as f:
                    json.dump(metadata, f, indent=2)

                print(f"[AVD Runner] Checkpoint created: {checkpoint_dir}")
                return True

            except Exception as e:
                print(f"[AVD Runner] Checkpoint creation failed: {e}")
                # Cleanup partial checkpoint
                if checkpoint_dir.exists():
                    try:
                        shutil.rmtree(checkpoint_dir)
                    except:
                        pass
                return False

    def start_from_checkpoint(self, seed: Optional[int] = None) -> bool:
        """Start emulator from existing checkpoint.

        This:
        1. Copies checkpoint AVD to work directory
        2. Starts emulator with the checkpoint AVD
        3. Loads saved snapshot for fast resume

        Returns False if no checkpoint exists, True if started successfully.
        """
        checkpoint_dir = self._get_checkpoint_dir()
        metadata_file = checkpoint_dir / "metadata.json"

        if not metadata_file.exists():
            print(f"[AVD Runner] No checkpoint found: {checkpoint_dir}")
            return False

        print(f"[AVD Runner] Starting from checkpoint: {checkpoint_dir}")
        print(f"[AVD Runner]   cache_level={self._checkpoint_cache_level}, task_id={self._checkpoint_task_id}")

        try:
            # Load metadata
            with open(metadata_file) as f:
                metadata = json.load(f)

            snapshot_name = metadata.get("snapshot_name", "gym_checkpoint")

            # Create work directory for this instance's AVD copy
            work_base = Path(tempfile.gettempdir())
            self._work_dir = Path(tempfile.mkdtemp(prefix=f"{self._instance_id}_", dir=work_base))
            self._checkpoint_avd_home = self._work_dir / "avd"
            self._checkpoint_avd_home.mkdir(exist_ok=True)

            # Create AVD work directory with COW overlays for QCOW2 files
            # This is MUCH faster than copying (creates thin overlays instead of 1.5GB+ copies)
            print(f"[AVD Runner] Creating AVD work directory with COW overlays...")
            src_avd_dir = checkpoint_dir / "avd" / f"{self._avd_name}.avd"
            src_avd_ini = checkpoint_dir / "avd" / f"{self._avd_name}.ini"
            dst_avd_dir = self._checkpoint_avd_home / f"{self._avd_name}.avd"
            dst_avd_ini = self._checkpoint_avd_home / f"{self._avd_name}.ini"

            self._create_avd_cow_copy(src_avd_dir, dst_avd_dir)
            if src_avd_ini.exists():
                # Update the ini file to point to new location
                with open(src_avd_ini) as f:
                    ini_content = f.read()
                # Update path in ini file
                ini_content = ini_content.replace(
                    str(checkpoint_dir / "avd"),
                    str(self._checkpoint_avd_home)
                )
                with open(dst_avd_ini, "w") as f:
                    f.write(ini_content)

            # Mark that we're loading from checkpoint
            self._loaded_from_checkpoint = True

            # Start emulator with checkpoint AVD (fresh boot from pre-configured userdata)
            self._launch_emulator_from_checkpoint()

            # Wait for boot (fresh boot from userdata, not snapshot restore)
            print(f"[AVD Runner] Waiting for emulator to boot from checkpoint userdata...")
            if not self._wait_for_boot(timeout=180):
                raise RuntimeError("Emulator failed to boot from checkpoint")

            # Setup mounts (need to push scripts even when loading from checkpoint)
            self._setup_mounts_adb()

            # Setup VNC (VNC server process doesn't survive snapshot restore)
            self._setup_vnc()

            self._running = True
            print(f"[AVD Runner] Started from checkpoint! ADB device: emulator-{self.console_port}")
            return True

        except Exception as e:
            print(f"[AVD Runner] Failed to start from checkpoint: {e}")
            import traceback
            traceback.print_exc()
            self.stop()
            return False

    def _get_qemu_img_path(self) -> Path:
        """Get path to qemu-img binary (bundled with Android emulator)."""
        qemu_img = self.sdk_manager.sdk_root / "emulator" / "qemu-img"
        if qemu_img.exists():
            return qemu_img
        # Fallback to system qemu-img
        return Path("qemu-img")

    def _create_avd_cow_copy(self, src_dir: Path, dst_dir: Path) -> None:
        """Create AVD copy using COW overlays for QCOW2 files.

        For .qcow2 files: Creates thin COW overlay (~200KB) instead of full copy (1.5GB+)
        For other files: Regular copy

        This makes checkpoint loading nearly instant instead of copying gigabytes.
        """
        dst_dir.mkdir(parents=True, exist_ok=True)
        qemu_img = self._get_qemu_img_path()

        for item in src_dir.iterdir():
            src_path = item
            dst_path = dst_dir / item.name

            if item.is_dir():
                # Recursively handle directories
                self._create_avd_cow_copy(src_path, dst_path)

            elif item.suffix == '.qcow2':
                # Create COW overlay for QCOW2 files (fast!)
                result = subprocess.run(
                    [
                        str(qemu_img), "create",
                        "-f", "qcow2",
                        "-b", str(src_path.absolute()),
                        "-F", "qcow2",
                        str(dst_path)
                    ],
                    capture_output=True
                )
                if result.returncode != 0:
                    print(f"[AVD Runner] Warning: COW overlay failed for {item.name}: {result.stderr.decode()}")
                    print(f"[AVD Runner] Falling back to copy (this may be slow)...")
                    shutil.copy2(src_path, dst_path)
                else:
                    print(f"[AVD Runner] Created COW overlay: {item.name}")

            else:
                # Regular copy for small files
                shutil.copy2(src_path, dst_path)

    def _launch_emulator_from_checkpoint(self) -> None:
        """Launch emulator from checkpoint's userdata.

        Uses COW overlays of checkpoint AVD for fast setup.
        Does NOT use emulator snapshots (they capture port state and cause crashes).
        Instead, boots fresh from checkpoint's userdata (apps already installed).
        Uses -read-only flag because emulator enforces single-instance by AVD name.
        """
        container_sif = self._ensure_container()

        # Ensure ADB server is running
        env = os.environ.copy()
        env["ADB_MDNS"] = "0"
        subprocess.run(
            [str(self.sdk_manager.adb), "start-server"],
            capture_output=True, env=env
        )

        # Allocate ports
        self.console_port, self.adb_port = _find_free_port_pair()
        print(f"[AVD Runner] Ports: console={self.console_port}, adb={self.adb_port}")

        # Build paths
        sdk_root = str(self.sdk_manager.sdk_root.absolute())
        avd_home = str(self._checkpoint_avd_home.absolute())
        android_home = str(self._checkpoint_avd_home.parent.absolute())
        work_dir = str(self._work_dir.absolute())

        # Emulator args
        emulator_args = [
            "-avd", self._avd_name,
            "-port", str(self.console_port),
            "-no-window", "-no-audio", "-no-boot-anim",
            "-read-only",
            "-no-snapshot-save", "-no-snapshot-load",
            "-no-metrics",
            "-gpu", "swiftshader_indirect",
            "-memory", str(self.mem_gb * 1024),
            "-cores", str(self.cpus),
        ]
        if self.enable_kvm:
            emulator_args.extend(["-accel", "on"])
        else:
            emulator_args.extend(["-accel", "off"])
        if self.resolution:
            width, height = self.resolution
            emulator_args.extend(["-skin", f"{width}x{height}"])

        # Create startup script
        startup_script = self._work_dir / "start_emulator.sh"
        script_content = f"""#!/bin/bash
export HOME=/tmp
export ADB_MDNS=0
export ANDROID_SDK_ROOT={sdk_root}
export ANDROID_AVD_HOME={avd_home}

# Run emulator from checkpoint userdata (fresh boot, apps pre-installed)
exec {self.sdk_manager.emulator_bin} {' '.join(emulator_args)}
"""
        startup_script.write_text(script_content)
        startup_script.chmod(0o755)

        # Build launch command (Apptainer-wrapped or direct)
        launch_cmd = self._build_launch_cmd(
            startup_script, container_sif,
            sdk_root, avd_home, android_home, work_dir
        )

        print(f"[AVD Runner] Launching emulator from checkpoint userdata (fresh boot)...")

        log_file = self._work_dir / "emulator.log"
        with open(log_file, "w") as lf:
            self._emulator_process = subprocess.Popen(
                launch_cmd,
                stdout=lf,
                stderr=subprocess.STDOUT,
                preexec_fn=os.setsid
            )

        time.sleep(5)

        if self._emulator_process.poll() is not None:
            print(f"[AVD Runner] Emulator exited immediately: {self._emulator_process.returncode}")
            self._dump_log()
            raise RuntimeError("Emulator failed to start from checkpoint")

    def delete_checkpoint(self) -> bool:
        """Delete the checkpoint for current checkpoint key."""
        checkpoint_dir = self._get_checkpoint_dir()
        if checkpoint_dir.exists():
            shutil.rmtree(checkpoint_dir)
            print(f"[AVD Runner] Checkpoint deleted: {checkpoint_dir}")
            return True
        return False


def main():
    """Test AVD runner."""
    from ...specs import EnvSpec, ObservationSpec, ResourceSpec

    # Create minimal spec
    spec = EnvSpec(
        id="test.avd@1",
        observation=[ObservationSpec(type="rgb_screen", resolution=(1080, 2400))],
        resources=ResourceSpec(cpu=4, mem_gb=4),
    )

    runner = AVDApptainerRunner(spec)

    try:
        print("Starting AVD...")
        runner.start()

        print("\nTaking screenshot...")
        runner.capture_screenshot("/tmp/avd_test.png")
        print("Screenshot saved to /tmp/avd_test.png")

        print("\nGetting device info...")
        info = runner.exec_capture("getprop ro.build.version.release")
        print(f"Android version: {info.strip()}")

        print("\nSession info:")
        import json
        print(json.dumps(runner.get_session_info(), indent=2))

    finally:
        runner.stop()


if __name__ == "__main__":
    main()
