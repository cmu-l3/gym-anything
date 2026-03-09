from __future__ import annotations

import os
import shlex
import subprocess
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional
import numpy as np

from ...specs import EnvSpec
from .base import BaseRunner


def _docker_sanitize_repo(name: str) -> str:
    """Sanitize a repo/name segment for Docker (lowercase, allowed chars).

    Allowed in repo path segments: lowercase letters, digits, underscores, periods,
    and dashes. Slashes separate path components.
    """
    import re

    # Only consider portion before '@' if present (treat '@' as version in id)
    base = name.split("@", 1)[0].lower()
    # Replace invalid chars with '-'
    base = re.sub(r"[^a-z0-9._/-]", "-", base)
    # Collapse consecutive separators
    base = re.sub(r"[-]{2,}", "-", base)
    base = re.sub(r"/{2,}", "/", base)
    base = base.strip("-/")
    return base or "env"


def _docker_sanitize_tag(tag: str) -> str:
    """Sanitize the tag portion (after ':') for Docker.

    Allowed: ASCII alphanumerics and [_.-]. Lowercase recommended.
    """
    import re

    t = tag.lower()
    t = re.sub(r"[^a-z0-9._-]", "-", t)
    t = re.sub(r"[-]{2,}", "-", t).strip("-.")
    return t or "latest"


def _container_is_running(container_name: str) -> bool:
    """Check if a Docker container is currently running."""
    try:
        result = subprocess.run(
            ["docker", "ps", "--filter", f"name={container_name}", "--format", "{{.Names}}"],
            capture_output=True,
            text=True,
            check=False
        )
        return container_name in result.stdout
    except Exception:
        return False


def _sh(cmd: List[str], check: bool = True, env: Optional[Dict[str, str]] = None, return_output: bool = False):
    if return_output:
        proc = subprocess.run(cmd, env=env, capture_output=True, text=True)
        result = {
            'returncode': proc.returncode,
            'stdout': proc.stdout,
            'stderr': proc.stderr
        }
        if check and proc.returncode != 0:
            raise RuntimeError(f"Command failed: {' '.join(cmd)}")
        return result
    else:
        proc = subprocess.run(cmd, env=env)
        if check and proc.returncode != 0:
            raise RuntimeError(f"Command failed: {' '.join(cmd)}")
        return proc.returncode


class DockerRunner(BaseRunner):
    """Docker-backed runtime.

    Responsibilities:
      - Build or pull image
      - Launch container with resource limits, mounts, and network policy
      - Start Xvfb, PulseAudio inside container for GUI/audio
      - Provide action injection via xdotool (if available) or stubs
      - Capture observations via lightweight commands (screenshot stub)

    Note: This class assumes the container image has the necessary tools (Xvfb,
    x11vnc or similar, PulseAudio, ffmpeg, xdotool). It does not enforce this.
    """

    def __init__(self, spec: EnvSpec):
        super().__init__(spec)
        # Sanitize container name: letters, digits, '_', '-', '.' only
        base_name = _docker_sanitize_repo(spec.id).replace("/", "_")
        self.container_name = f"ga_{base_name}_{uuid.uuid4().hex[:8]}"
        self.display = ":1" if spec.security.use_systemd else ":99"
        self.pulse_server = "unix:/tmp/pulse/native"
        self._running = False
        # Artifacts mount mapping
        self.artifacts_host_root = os.path.abspath(spec.recording.output_dir)
        self.artifacts_container_root = "/workspace/artifacts"
        self.vnc_host_port: Optional[int] = None
        self._used_xvnc = False
        # Checkpoint support
        self._checkpoint_loaded = False
        self._checkpoint_image_name = None
        self._checkpoint_cache_level: str = "pre_start"
        self._checkpoint_task_id: Optional[str] = None
        # Log streaming
        self._log_thread: Optional[threading.Thread] = None
        self._log_stop_event = threading.Event()

    # Lifecycle
    def start(self, seed: Optional[int] = None) -> None:
        if self.spec.dockerfile and not self.spec.image:
            self._build_image()
        if not self.spec.image:
            raise ValueError("EnvSpec.image or dockerfile must be provided for DockerRunner")
        if self.spec.security.use_systemd:
            self._check_systemd_prereqs()
        self._start_container()
        if self.spec.security.use_systemd:
            self._wait_for_systemd()
        self._setup_user_accounts()
        if not self.spec.skip_display_audio_bootstrap:
            self._bootstrap_display_audio()
        self._launch_entrypoint()
        self._running = True

    def _stream_logs_to_file(self, log_file_path: Path) -> None:
        """Background thread function to stream container logs to a file in real-time."""
        try:
            # Open the log file in append mode
            with open(log_file_path, 'w') as f:
                f.write(f"=== Container logs for {self.container_name} ===\n")
                f.write(f"=== Started at {time.strftime('%Y-%m-%d %H:%M:%S')} ===\n\n")
                f.flush()
                
                # Start streaming logs with -f (follow)
                process = subprocess.Popen(
                    ["docker", "logs", "-f", self.container_name],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1  # Line buffered
                )
                
                # Stream logs line by line until stop event is set
                while not self._log_stop_event.is_set():
                    line = process.stdout.readline()
                    if line:
                        f.write(line)
                        f.flush()
                    elif process.poll() is not None:
                        # Container stopped, read remaining output
                        remaining = process.stdout.read()
                        if remaining:
                            f.write(remaining)
                            f.flush()
                        break
                    time.sleep(0.01)  # Small delay to avoid busy loop
                
                # Terminate the docker logs process
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=2)
                
                f.write(f"\n=== Ended at {time.strftime('%Y-%m-%d %H:%M:%S')} ===\n")
        except Exception as e:
            print(f"⚠️  Log streaming error: {e}")

    def _start_log_streaming(self) -> None:
        """Start background thread to stream container logs to file."""
        container_log_dir = Path(self.artifacts_host_root) / "container_logs"
        container_log_dir.mkdir(parents=True, exist_ok=True)
        container_log_file = container_log_dir / f"{self.container_name}.log"
        
        self._log_stop_event.clear()
        self._log_thread = threading.Thread(
            target=self._stream_logs_to_file,
            args=(container_log_file,),
            daemon=True
        )
        self._log_thread.start()
        print(f"📝 Streaming container logs to: {container_log_file}")

    def stop(self) -> None:
        if not self._running:
            return
        
        # Stop log streaming thread
        if self._log_thread and self._log_thread.is_alive():
            self._log_stop_event.set()
            self._log_thread.join(timeout=3)  # Wait up to 3 seconds for thread to finish
            print(f"📝 Container logs streaming stopped")
        
        _sh(["docker", "rm", "-f", self.container_name], check=False)
        self._running = False

    def run_reset(self, reset_script: str, seed: Optional[int] = None) -> None:
        seed_env = {"SEED": str(seed)} if seed is not None else {}
        self.exec(f"bash -lc {shlex.quote(reset_script)}", env=seed_env)

    def run_task_init(self, init_script: str) -> None:
        self.exec(f"bash -lc {shlex.quote(init_script)}")

    def supports_live_recording(self) -> bool:
        return True

    def supports_checkpoint_caching(self) -> bool:
        return True

    # Actions / Observations
    def inject_action(self, action: Dict[str, Any]) -> None:
        # Minimal xdotool-based injection. Container must have DISPLAY set.
        parts: List[str] = []
        mouse = action.get("mouse")
        if mouse:
            if 'left_click' in mouse:
                x, y = mouse["left_click"]
                parts.append(f"xdotool mousemove {int(x)} {int(y)} click 1")
            if 'right_click' in mouse:
                x, y = mouse["right_click"]
                parts.append(f"xdotool mousemove {int(x)} {int(y)} click 3")
            if 'double_click' in mouse:
                x, y = mouse["double_click"]
                parts.append(f"xdotool mousemove {int(x)} {int(y)} click --repeat 2 1")
            if 'triple_click' in mouse:
                x, y = mouse["triple_click"]
                parts.append(f"xdotool mousemove {int(x)} {int(y)} click --repeat 3 1")
            if 'left_click_drag' in mouse:
                x1, y1 = mouse["left_click_drag"][0]
                x2, y2 = mouse["left_click_drag"][1]
                # parts.append(f"xdotool mousemove --sync {int(x1)} {int(y1)} mousedown 1 mousemove --sync {int(x2)} {int(y2)} mouseup 1")
                # pyautogui.moveTo(640, 415)
                # pyautogui.dragTo(950, 515, duration=1.5, button='left')
                parts.append(f"python3 - <<'PY'\nimport pyautogui\npyautogui.moveTo({int(x1)}, {int(y1)})\npyautogui.dragTo({int(x2)}, {int(y2)}, duration=1.5, button='left')\nPY")
            if 'right_click_drag' in mouse:
                x1, y1 = mouse["right_click_drag"][0]
                x2, y2 = mouse["right_click_drag"][1]
                # parts.append(f"xdotool mousemove --sync {int(x1)} {int(y1)} mousedown 3 mousemove --sync {int(x2)} {int(y2)} mouseup 3")
                parts.append(f"python3 - <<'PY'\nimport pyautogui\npyautogui.moveTo({int(x1)}, {int(y1)})\npyautogui.dragTo({int(x2)}, {int(y2)}, duration=1.5, button='right')\nPY")
            if "move" in mouse:
                x, y = mouse["move"]
                parts.append(f"xdotool mousemove {int(x)} {int(y)}")
            # buttons: {left_down,left_up,right_down,scroll}
            buttons = mouse.get("buttons", {})
            if buttons.get("left_down"):
                parts.append("xdotool mousedown 1")
            if buttons.get("left_up"):
                parts.append("xdotool mouseup 1")
            if buttons.get("right_down"):
                parts.append("xdotool click 3")
            if "scroll" in mouse:
                dy = int(mouse["scroll"])  # positive down
                click_code = 5 if dy > 0 else 4
                for _ in range(abs(dy)):
                    parts.append(f"xdotool click {click_code}")

        keyboard = action.get("keyboard")
        if keyboard:
            text = keyboard.get("text")
            keys = keyboard.get("keys")
            if text:
                parts.append(f"xdotool type --delay 1 {shlex.quote(text)}")
            if keys:
                # keys as a sequence: ["ctrl","s"] -> chord
                if isinstance(keys, str):
                    keys = [keys]
                keys_norm = [self._normalize_key_name(k) for k in keys]
                key_str = "+".join(keys_norm)
                parts.append(f"xdotool key {shlex.quote(key_str)}")

        voice = action.get("voice")
        if voice:
            # Play PCM16 audio to default Pulse sink; not a true microphone inject.
            # Accepts voice:{ pcm16_b64, rate, channels }
            b64 = voice.get("pcm16_b64")
            rate = int(voice.get("rate", 16000))
            ch = int(voice.get("channels", 1))
            if b64:
                tmp = f"/tmp/voice_{uuid.uuid4().hex[:6]}.wav"
                # Decode base64 to wav and play via paplay (if available) or ffplay fallback
                cmd_decode = (
                    "python3 - <<'PY'\n"
                    "import sys,base64,struct,wave;\n"
                    "data=base64.b64decode(sys.stdin.read());\n"
                    f"wf=wave.open('{tmp}','wb');wf.setnchannels({ch});wf.setsampwidth(2);wf.setframerate({rate});wf.writeframes(data);wf.close()\n"
                    "PY"
                )
                self.exec(f"bash -lc \"echo {shlex.quote(b64)} | {cmd_decode} && (paplay {tmp} || ffplay -nodisp -autoexit {tmp})\"")

        api_call = action.get("api_call")
        if api_call:
            # High-level calls are env-specific; expose hook naming convention
            name = api_call.get("name")
            args = api_call.get("args", {})
            self._invoke_env_api(name, args)

        if parts:
            cmd = " && ".join(parts)
            # if 'repeat' in cmd:
            #     breakpoint()
            try:
                st_time = time.time()
                self.exec(f"bash -lc {shlex.quote(cmd)}")
                end_time = time.time()
                print(f"Time taken to exec in inject_action: {end_time - st_time} seconds")
            except Exception as e:
                print(f"Error executing command: {cmd}")
                print(f"Error: {e}")
                # breakpoint()

    def capture_observation(self) -> Dict[str, Any]:
        # In M2 we return only structural metadata; frame data lives in recording.
        obs: Dict[str, Any] = {}
        # Screen metadata
        screen_spec = next((o for o in self.spec.observation if o.type == "rgb_screen"), None)
        if screen_spec:
            obs["screen"] = {
                "format": "rgb",
                "fps": screen_spec.fps,
                "resolution": screen_spec.resolution,
            }
        # Audio metadata
        audio_spec = next((o for o in self.spec.observation if o.type == "audio_waveform"), None)
        if audio_spec:
            obs["audio"] = {
                "rate": audio_spec.sample_rate or 16000,
                "channels": audio_spec.channels or 1,
            }
        return obs

    def capture_ui_tree(self) -> str:
        # Fallback: xwininfo window tree (textual)
        try:
            return self.exec_capture("xwininfo -root -tree || true")
        except Exception:
            return ""

    # Internals
    def _build_image(self) -> None:
        df_path = Path(self.spec.dockerfile)
        if not df_path.exists():
            raise FileNotFoundError(f"Dockerfile not found: {df_path}")
        repo = f"ga/{_docker_sanitize_repo(self.spec.id)}"
        tag = f"{repo}:{_docker_sanitize_tag(self.spec.version)}"
        _sh(["docker", "build", "-t", tag, "-f", str(df_path), str(df_path.parent)])
        self.spec.image = tag

    def _start_container(self) -> None:
        cmd = ["docker", "run", "-d",'--rm', "--name", self.container_name]
        # --network apt-net -e http_proxy=http://apt-cache:3142
        # cmd += ["--network", "apt-net"]
        # cmd += ["-e", "http_proxy=http://apt-cache:3142"]
        
        # Runtime (e.g., sysbox-runc for systemd containers)
        use_sysbox = False
        if hasattr(self.spec.security, 'runtime') and self.spec.security.runtime:
            cmd += ["--runtime", self.spec.security.runtime]
            use_sysbox = self.spec.security.runtime == "sysbox-runc"
            if use_sysbox:
                print(f"Using Sysbox runtime for systemd container")
        
        # Logging: configure Docker's internal log driver
        cmd += [
            "--log-driver", "json-file",
            "--log-opt", f"max-size=100m",
            "--log-opt", f"max-file=3",
            "--log-opt", f"labels=gym-anything"
        ]

        # Resources
        if self.spec.resources.cpu:
            cmd += ["--cpus", str(self.spec.resources.cpu)]
        if self.spec.resources.mem_gb:
            print('Setting memory to', self.spec.resources.mem_gb)
            cmd += ["--memory", f"{self.spec.resources.mem_gb}g"]
        if self.spec.resources.gpu:
            print('Setting GPU to', self.spec.resources.gpu)
            cmd += ["--gpus", str(self.spec.resources.gpu)]

        # Network policy: if VNC enabled, use default bridge to allow port publish; else keep original policy
        vnc_enabled = bool(getattr(self.spec, "vnc", None) and self.spec.vnc.enable)
        if self.spec.resources.net is False and not vnc_enabled:
            cmd += ["--network", "none"]

        # Security (skip most flags for Sysbox as it handles them internally)
        if self.spec.security.user:
            cmd += ["--user", self.spec.security.user]
        
        if not use_sysbox:
            # These flags are incompatible with Sysbox (it handles them internally)
            for cap in (self.spec.security.cap_drop or []):
                cmd += ["--cap-drop", cap]
            for cap in (self.spec.security.cap_add or []):
                cmd += ["--cap-add", cap]
            if self.spec.security.privileged:
                cmd += ["--privileged"]
            if self.spec.security.tmpfs_run:
                cmd += ["--tmpfs", "/run", "--tmpfs", "/run/lock"]
            if self.spec.security.cgroupns_host:
                cmd += ["--cgroupns=host"]
            if self.spec.security.mount_cgroups:
                cmd += ["-v", "/sys/fs/cgroup:/sys/fs/cgroup:rw"]
        
        # These work with both standard and Sysbox runtime
        for device in (self.spec.security.devices or []):
            cmd += ["--device", device]
        if self.spec.security.seccomp_profile:
            cmd += ["--security-opt", f"seccomp={self.spec.security.seccomp_profile}"]
        if self.spec.security.stop_timeout:
            cmd += ["--stop-timeout", str(self.spec.security.stop_timeout)]

        # Mounts (user-specified)
        for m in self.spec.mounts:
            source = os.path.abspath(m.source)
            target = m.target
            mode = m.mode
            cmd += ["-v", f"{source}:{target}:{mode}"]

        # Mount artifacts root for recording
        Path(self.artifacts_host_root).mkdir(parents=True, exist_ok=True)
        cmd += ["-v", f"{self.artifacts_host_root}:{self.artifacts_container_root}:rw"]

        # Publish VNC port if enabled (bind to loopback, auto-retry on conflict)
        cmd_publish_prefix: List[str] = []
        host_port: Optional[int] = None
        if vnc_enabled:
            start_port = int(self.spec.vnc.host_port or 5901)
            if start_port == -1:
                start_port = np.random.randint(10000, 65535)
            container_vnc_port = int(self.spec.vnc.container_port or 5901)
            # Try up to 20 ports starting from start_port
            for attempt in range(0, 20):
                candidate = self._find_free_port(start_port + attempt)
                # Bind to loopback only to avoid conflicts on all interfaces
                cmd_publish_prefix = ["-p", f"127.0.0.1:{candidate}:{container_vnc_port}"]
                # Stash but don't print yet; we'll print after successful start
                host_port = candidate
                break
            # If for some reason no port found, leave host_port None (docker will fail and surface error)

        # Environment for X and Pulse
        cmd += ["-e", f"DISPLAY={self.display}"]
        cmd += ["-e", f"PULSE_SERVER={self.pulse_server}"]
        for key, value in self.default_exec_env().items():
            cmd += ["-e", f"{key}={value}"]
        if self.spec.security.use_systemd:
            cmd += ["-e", "container=docker"]

        # Image and initial process; attempt with auto-retry if VNC port is busy at docker layer
        if self.spec.security.use_systemd:
            cmd_tail = [self.spec.image]
        else:
            cmd_tail = [self.spec.image, "bash", "-lc", "sleep infinity"]

        # Try running; if it fails due to port allocation, advance port and retry a few times
        attempts = 0
        max_attempts = 20 if vnc_enabled else 20
        while True:
            attempts += 1
            cmd_run = cmd[:]
            if cmd_publish_prefix:
                cmd_run += cmd_publish_prefix
            cmd_run += cmd_tail
            try:
                print('Running command: ', cmd_run)
                print(_sh(cmd_run, return_output=True))

                # Make sure the container is running
                if not _container_is_running(self.container_name):
                    print(f"Container {self.container_name} is not running")
                    time.sleep(1)
                    continue
                else:
                    print(f"Container {self.container_name} is running atleast now.")
                    # Start log streaming immediately
                    self._start_log_streaming()
                    time.sleep(5)
                    # Alright let's try rerunning the command this time with output
                    # if not _container_is_running(self.container_name):
                    #     # breakpoint()
                    #     print(_sh(cmd_run, return_output=True))
                        
                    #     time.sleep(1)
                    #     continue
                    print(_container_is_running(self.container_name))
                    if not _container_is_running(self.container_name):
                        continue
                break
            except RuntimeError as e:
                # breakpoint()
                if not vnc_enabled:
                    # Now there could have been an error on the self.exec, which implies simply that the container is not running
                    print(f"Error starting container: {e}")
                    time.sleep(1)
                    continue
                
                if attempts >= max_attempts:
                    raise
                # Pick next port and retry
                assert host_port is not None

                host_port = np.random.randint(10000, 65535)
                host_port = self._find_free_port(host_port)
                cmd_publish_prefix = ["-p", f"127.0.0.1:{host_port}:5901"]
                continue
            except Exception as e:
                print(f"Error starting container: {e}")
                # breakpoint()
                continue

        # Success: record chosen host VNC port
        if vnc_enabled and host_port is not None:
            self.vnc_host_port = host_port
            container_vnc_port = int(self.spec.vnc.container_port or 5901)
            print(f"Publishing VNC port localhost:{host_port} -> container:{container_vnc_port}")

    def _setup_user_accounts(self) -> None:
        """Create and configure user accounts as specified in the env spec."""
        if not self.spec.user_accounts:
            return
        # breakpoint()
        print(f"Setting up {len(self.spec.user_accounts)} user account(s)...")
        
        # Get list of existing users to avoid conflicts
        try:
            existing_users = self.exec_capture("cut -d: -f1 /etc/passwd").strip().split('\n')
            existing_uids = set()
            uid_output = self.exec_capture("cut -d: -f3 /etc/passwd").strip().split('\n')
            for uid_str in uid_output:
                if uid_str.isdigit():
                    existing_uids.add(int(uid_str))
        except Exception:
            existing_users = []
            existing_uids = set()
            
        print(f"  Found {len(existing_users)} existing users")
        
        for user in self.spec.user_accounts:
            print(f"  Setting up user: {user.name} (role: {user.role or 'default'})")
            
            # Skip if user already exists
            if user.name in existing_users:
                print(f"    User {user.name} already exists, configuring permissions only...")
                self._configure_existing_user(user)
                continue
            
            # Determine UID/GID
            uid = user.uid
            gid = user.gid or uid  # Default GID to UID if not specified
            
            # Auto-assign UID if not specified, avoiding conflicts
            if uid is None:
                if user.permissions.system_user:
                    uid = 999  # System users typically under 1000
                    while uid in existing_uids:
                        uid -= 1
                        if uid < 100:  # Don't go too low
                            uid = 999
                            break
                else:
                    uid = 1001  # Start at 1001 to avoid conflict with ga user at 1000
                    while uid in existing_uids:
                        uid += 1
                gid = uid if user.gid is None else user.gid
            
            # Create the user
            self._create_new_user(user, uid, gid, existing_uids)
        
        print("User account setup completed.")

    def _create_new_user(self, user, uid, gid, existing_uids):
        """Create a new user account with the specified permissions."""
        try:
            # Create primary group if it doesn't exist
            primary_group = user.permissions.primary_group or user.name
            # Try to create group with specific GID, fallback to auto-assigned GID if conflict
            group_result = self.exec_capture(f"bash -lc 'getent group {primary_group} >/dev/null 2>&1 || (groupadd -g {gid} {primary_group} 2>/dev/null || groupadd {primary_group}) 2>&1 || echo GROUP_FAILED'")
            if "GROUP_FAILED" in group_result:
                print(f"    Warning: Failed to create group {primary_group}: {group_result}")
            
            # Create additional groups
            for group in user.permissions.groups:
                try:
                    self.exec(f"bash -lc 'getent group {group} >/dev/null 2>&1 || groupadd {group}'")
                except Exception as e:
                    # breakpoint()
                    pass

            # Determine home directory
            home_dir = user.permissions.home_dir or (f"/home/{user.name}" if not user.permissions.system_user else f"/var/lib/{user.name}")
            
            # Create user with appropriate flags
            useradd_cmd = ["useradd"]
            
            # UID and primary group
            useradd_cmd.extend(["-u", str(uid), "-g", primary_group])
            
            # Home directory
            if user.permissions.create_home:
                useradd_cmd.extend(["-m", "-d", home_dir])
            else:
                useradd_cmd.extend(["-M"])  # Don't create home directory
            
            # Shell
            useradd_cmd.extend(["-s", user.permissions.shell])
            
            # System user flag
            if user.permissions.system_user:
                useradd_cmd.append("-r")
            
            # Additional groups
            if user.permissions.groups:
                useradd_cmd.extend(["-G", ",".join(user.permissions.groups)])
            
            # Add username
            useradd_cmd.append(user.name)
            
            # Execute useradd command
            # breakpoint()
            useradd_result = self.exec_capture(f"bash -lc '{' '.join(useradd_cmd)} 2>&1 || echo FAILED'")
            if "FAILED" in useradd_result:
                print(f"    Warning: Failed to create user {user.name}: {useradd_result}")
                return
            
            print(f"    Created user {user.name} with UID {uid}")
            
            # Configure the user
            self._configure_user_permissions(user, uid, gid, home_dir)
            
        except Exception as e:
            print(f"    Error creating user {user.name}: {e}")

    def _configure_existing_user(self, user):
        """Configure permissions for an existing user."""
        try:
            # Get user info
            user_info = self.exec_capture(f"getent passwd {user.name}").strip()
            if not user_info:
                print(f"    Warning: User {user.name} not found")
                return
            
            parts = user_info.split(':')
            uid = int(parts[2])
            gid = int(parts[3])
            home_dir = parts[5]
            
            print(f"    Configuring existing user {user.name} (UID: {uid})")
            self._configure_user_permissions(user, uid, gid, home_dir)
            
        except Exception as e:
            print(f"    Error configuring existing user {user.name}: {e}")

    def _configure_user_permissions(self, user, uid, gid, home_dir):
        """Configure permissions for a user (new or existing)."""
        try:
            # Set password if provided
            if user.password:
                escaped_password = user.password.replace("'", "'\"'\"'")  # Escape single quotes
                self.exec(f"bash -lc \"echo '{user.name}:{escaped_password}' | chpasswd\"")
            
            # Add user to additional groups
            if user.permissions.groups:
                for group in user.permissions.groups:
                    self.exec(f"bash -lc 'getent group {group} >/dev/null 2>&1 || groupadd {group}'")
                    self.exec(f"bash -lc 'usermod -a -G {group} {user.name} 2>/dev/null || true'")
            
            # Set home directory permissions
            if user.permissions.create_home and home_dir and home_dir != "/":
                self.exec(f"bash -lc 'mkdir -p {home_dir} && chmod {user.permissions.home_permissions} {home_dir}'")
                self.exec(f"bash -lc 'chown {uid}:{gid} {home_dir} 2>/dev/null || true'")
            
            # Configure sudo access
            if user.permissions.sudo:
                sudo_rule = f"{user.name} ALL=(ALL)"
                if user.permissions.sudo_nopasswd:
                    sudo_rule += " NOPASSWD: ALL"
                else:
                    sudo_rule += " ALL"
                
                self.exec(f"bash -lc 'echo \"{sudo_rule}\" > /etc/sudoers.d/{user.name}'")
                self.exec(f"bash -lc 'chmod 440 /etc/sudoers.d/{user.name}'")
            
            # Set environment variables for user
            if user.permissions.env_vars and home_dir:
                env_file = f"{home_dir}/.env_vars"
                env_content = "\\n".join([f"export {k}={v}" for k, v in user.permissions.env_vars.items()])
                self.exec(f"bash -lc 'echo -e \"{env_content}\" > {env_file}'")
                self.exec(f"bash -lc 'chown {uid}:{gid} {env_file} 2>/dev/null || true'")
                
                # Add to .bashrc if it exists
                bashrc_path = f"{home_dir}/.bashrc"
                self.exec(f"bash -lc 'if [ -f {bashrc_path} ]; then echo \"source {env_file}\" >> {bashrc_path}; fi'")
            
            # Set resource limits if specified
            if user.permissions.max_processes or user.permissions.max_memory:
                limits_content = ""
                if user.permissions.max_processes:
                    limits_content += f"{user.name} soft nproc {user.permissions.max_processes}\\n"
                    limits_content += f"{user.name} hard nproc {user.permissions.max_processes}\\n"
                if user.permissions.max_memory:
                    # Convert memory limit to KB (assuming input like "1G", "512M")
                    mem_limit = user.permissions.max_memory
                    if mem_limit.endswith('G'):
                        mem_kb = int(mem_limit[:-1]) * 1024 * 1024
                    elif mem_limit.endswith('M'):
                        mem_kb = int(mem_limit[:-1]) * 1024
                    else:
                        mem_kb = int(mem_limit)
                    limits_content += f"{user.name} soft rss {mem_kb}\\n"
                    limits_content += f"{user.name} hard rss {mem_kb}\\n"
                
                if limits_content:
                    self.exec(f"bash -lc 'echo -e \"{limits_content}\" >> /etc/security/limits.conf'")
                    
        except Exception as e:
            print(f"    Error configuring permissions for {user.name}: {e}")

    def _wait_for_systemd(self) -> None:
        """Wait for systemd to fully initialize in systemd containers."""
        print("Waiting for systemd to initialize...")
        max_attempts = 30
        for attempt in range(max_attempts):
            try:
                # Test if systemd is ready by checking if we can query service status
                result = self.exec_capture("systemctl is-system-running || systemctl is-active multi-user.target")
                if result.strip():  # If we get any output, systemd is responding
                    print(f"Systemd ready after {attempt + 1} attempts")
                    time.sleep(2)  # Give it a bit more time for services to settle
                    return
            except Exception:
                pass
            time.sleep(1)
        print(f"Warning: systemd may not be fully ready after {max_attempts} attempts")

    def _cleanup_xserver_state(self) -> None:
        """Clean up X server lock files and stale state after loading from checkpoint.
        
        When loading from checkpoint, the filesystem may contain stale X server state
        (lock files, sockets, etc.) from the previous run. This prevents GDM from
        starting X server cleanly. We need to clean these up.
        """
        print("Cleaning up X server state from checkpoint...")
        cleanup_commands = [
            # Remove X lock files
            "rm -f /tmp/.X*-lock",
            # Remove stale X11 sockets (directory will be recreated)
            "rm -f /tmp/.X11-unix/X*",
            # Ensure X11-unix directory exists with correct permissions
            "mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix",
            # Clean up GDM runtime state
            "rm -rf /var/run/gdm3/* 2>/dev/null || true",
            "rm -rf /run/gdm3/* 2>/dev/null || true",
            "rm -rf /var/lib/gdm3/.config/pulse 2>/dev/null || true",
            # Clean up any stale Xauthority files
            "rm -f /run/user/*/gdm/Xauthority 2>/dev/null || true",
            "rm -f /run/user/*/X* 2>/dev/null || true",
            # Clean up /tmp files that might interfere
            "rm -rf /tmp/.ICE-unix/* 2>/dev/null || true",
        ]
        
        for cmd in cleanup_commands:
            try:
                self.exec(f"bash -lc '{cmd}'")
            except Exception as e:
                # Non-critical, continue
                pass
        
        print("X server state cleanup complete")

    def _wait_for_xserver(self) -> None:
        """Wait for X server to be ready (important when loading from checkpoint)."""
        print(f"Waiting for X server on {self.display}...")
        max_attempts = 60
        for attempt in range(max_attempts):
            try:
                # Check if X11 socket exists
                display_num = self.display.replace(':', '')
                result = self.exec_capture(f"test -S /tmp/.X11-unix/X{display_num} && echo 'ready'")
                if 'ready' in result:
                    # Double check with xdpyinfo or xdotool
                    try:
                        self.exec_capture(f"DISPLAY={self.display} xdotool getmouselocation")
                        print(f"X server ready on {self.display} after {attempt + 1} attempts")
                        return
                    except Exception:
                        pass
            except Exception:
                pass
            time.sleep(1)
        print(f"Warning: X server may not be ready after {max_attempts} attempts")

    def _bootstrap_display_audio(self) -> None:
        # Start X server and PulseAudio depending on systemd mode
        screen_spec = next((o for o in self.spec.observation if o.type == "rgb_screen"), None)
        res = f"{screen_spec.resolution[0]}x{screen_spec.resolution[1]}" if (screen_spec and screen_spec.resolution) else "1920x1080"
        pa_system = "true" if getattr(self.spec.security, "use_systemd", False) else "false"
        vnc_cfg = getattr(self.spec, "vnc", None)
        vnc_enabled = bool(vnc_cfg and vnc_cfg.enable)
        vnc_pw = (vnc_cfg.password if vnc_cfg else None)
        vnc_view_only = bool(vnc_cfg.view_only) if vnc_cfg else False


        # Start VNC server if enabled (non-systemd path only; systemd uses TigerVNC unit)
        if vnc_enabled and not self.spec.security.use_systemd:
            # If a password is provided, create a hashed auth file and use -rfbauth
            if vnc_pw:
                pw = vnc_pw
                self.exec(
                    "bash -lc \"x11vnc -storepasswd '" + pw + "' /tmp/x11vnc.pass >/dev/null 2>&1\""
                )
                auth_arg = "-rfbauth /tmp/x11vnc.pass"
            else:
                auth_arg = "-nopw"
            viewonly = "-viewonly" if vnc_view_only else ""
            # Add -noxdamage to avoid black screen on Docker Desktop/macOS
            cmd = (
                "x11vnc -display "
                + self.display
                + " -forever -shared -noxdamage -rfbport 5901 "
                + auth_arg
                + " "
                + viewonly
                + " -o /tmp/x11vnc.log"
            )
            self.exec(f"{cmd} &")

    def _launch_entrypoint(self) -> None:
        if self.spec.entrypoint:
            self.exec(f"bash -lc {shlex.quote(self.spec.entrypoint)}")

    def _find_free_port(self, start_port: int) -> int:
        import socket
        port = max(1, int(start_port))
        while port < 65535:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                try:
                    # Bind to 0.0.0.0 to mirror Docker port publish behavior
                    s.bind(("0.0.0.0", port))
                    return port
                except OSError:
                    port += 1
        raise RuntimeError("No free port found for VNC")

    def _check_systemd_prereqs(self) -> None:
        import platform
        warn_msgs = []
        if platform.system() != "Linux":
            warn_msgs.append("Systemd containers work best on Linux hosts; Docker Desktop may limit cgroups")
        # Probe docker info for Desktop hint
        try:
            out = subprocess.run(["docker", "info"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=5).stdout
            if "Docker Desktop" in out:
                warn_msgs.append("Detected Docker Desktop; systemd/cgroups may be partially supported")
        except Exception:
            pass
        if warn_msgs:
            for m in warn_msgs:
                print(f"[gym-anything] WARNING: {m}")

    def _invoke_env_api(self, name: str, args: Dict[str, Any]) -> None:
        # Convention: container provides /workspace/env_api.py with functions
        argv = " ".join(f"--{k} {shlex.quote(str(v))}" for k, v in (args or {}).items())
        self.exec(f"bash -lc 'python3 /workspace/env_api.py {shlex.quote(name)} {argv}'")

    # Public utility for recorders
    def exec(self, cmd: str, env: Optional[Dict[str, str]] = None, user: Optional[str] = None, use_pty: bool = True) -> int:
        # Note: use_pty is accepted for API compatibility with QemuApptainerRunner but is
        # ignored here. Docker exec doesn't have the same PTY/SIGHUP behavior as SSH.
        env = self.merge_exec_env(env)
        full_cmd = ["docker", "exec"]
        if env:
            for k, v in env.items():
                full_cmd += ["-e", f"{k}={v}"]
        if user:
            full_cmd += ["-u", user]
        full_cmd += [self.container_name, "bash", "-lc", cmd]

        sh_output = _sh(full_cmd, check=True)
        return sh_output

    def exec_async(self, cmd: str, env: Optional[Dict[str, str]] = None, stdout=None, stderr=None, user: Optional[str] = None):
        env = self.merge_exec_env(env)
        full_cmd = ["docker", "exec"]
        if env:
            for k, v in env.items():
                full_cmd += ["-e", f"{k}={v}"]
        if user:
            full_cmd += ["-u", user]
        full_cmd += [self.container_name, "bash", "-lc", cmd]
        return subprocess.Popen(full_cmd, stdout=stdout, stderr=stderr)

    def to_container_path(self, host_path):
        host_path = os.path.abspath(str(host_path))
        # If under artifacts host root, map to container root
        if host_path.startswith(self.artifacts_host_root):
            rel = os.path.relpath(host_path, self.artifacts_host_root)
            return os.path.join(self.artifacts_container_root, rel)
        return host_path

    def put_file(self, host_path) -> str:
        host_path = os.path.abspath(str(host_path))
        dest = f"/tmp/ga_{uuid.uuid4().hex[:8]}_{os.path.basename(host_path)}"
        
        # Use copy_to which handles both standard and Sysbox containers
        self.copy_to(host_path, dest)
        return dest

    def exec_capture(self, cmd: str) -> str:
        # Capture combined stdout/stderr as text
        full_cmd = ["docker", "exec"]
        for k, v in self.default_exec_env().items():
            full_cmd += ["-e", f"{k}={v}"]
        full_cmd += [self.container_name, "bash", "-lc", cmd]
        proc = subprocess.run(full_cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        return proc.stdout

    def exec_capture_bytes(self, cmd: str) -> bytes:
        full_cmd = ["docker", "exec"]
        for k, v in self.default_exec_env().items():
            full_cmd += ["-e", f"{k}={v}"]
        full_cmd += [self.container_name, "bash", "-lc", cmd]
        proc = subprocess.run(full_cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return proc.stdout

    def capture_screenshot(self, host_path) -> bool:
        # Use ffmpeg to capture one frame from X11 display
        # breakpoint()
        host_path = os.path.abspath(str(host_path))
        Path(os.path.dirname(host_path)).mkdir(parents=True, exist_ok=True)
        container_out = self.to_container_path(host_path)
        # Try to infer resolution from spec; else omit -video_size
        screen_spec = next((o for o in self.spec.observation if o.type == "rgb_screen"), None)
        size_arg = (
            f"-video_size {screen_spec.resolution[0]}x{screen_spec.resolution[1]}"
            if (screen_spec and screen_spec.resolution)
            else ""
        )
        cmd = f"ffmpeg -y -loglevel error -f x11grab {size_arg} -i $DISPLAY -vframes 1 {shlex.quote(container_out)}"
        rc = self.exec(cmd)
        return rc == 0

    def capture_audio_raw(self, duration_sec: float, rate: int, channels: int) -> bytes:
        # Capture raw s16le from Pulse to stdout
        dur = max(0.05, float(duration_sec))
        cmd = (
            f"ffmpeg -hide_banner -loglevel error -f pulse -ac {int(channels)} -ar {int(rate)} "
            f"-t {dur:.3f} -i default -f s16le -"
        )
        return self.exec_capture_bytes(cmd)

    def copy_to(self, host_src: str, container_dst: str) -> None:
        host_src = os.path.abspath(host_src)
        
        # Check if using Sysbox runtime (docker cp doesn't work with Sysbox)
        use_sysbox = hasattr(self.spec.security, 'runtime') and \
                     self.spec.security.runtime == "sysbox-runc"
        
        if use_sysbox:
            # Sysbox workaround: use tar to transfer files (most robust method)
            # This is what docker cp uses internally
            import tarfile
            import io
            
            # Ensure parent directory exists in container
            parent_dir = os.path.dirname(container_dst)
            if parent_dir:
                self.exec(f"mkdir -p {shlex.quote(parent_dir)}")
            
            # Create tar archive in memory
            tar_stream = io.BytesIO()
            with tarfile.open(fileobj=tar_stream, mode='w') as tar:
                # Add file to tar with the destination basename
                tar.add(host_src, arcname=os.path.basename(container_dst))
            tar_stream.seek(0)
            
            # Extract tar in the parent directory via docker exec
            extract_dir = parent_dir if parent_dir else "/"
            proc = subprocess.run(
                ["docker", "exec", "-i", self.container_name, "tar", "-xf", "-", "-C", extract_dir],
                input=tar_stream.read(),
                stderr=subprocess.PIPE
            )
            if proc.returncode != 0:
                raise RuntimeError(f"Failed to copy to Sysbox container: {proc.stderr.decode()}")
        else:
            _sh(["docker", "cp", host_src, f"{self.container_name}:{container_dst}"])

    def copy_from(self, container_src: str, host_dst: str) -> None:
        host_dst = os.path.abspath(host_dst)
        Path(os.path.dirname(host_dst)).mkdir(parents=True, exist_ok=True)
        
        # Check if using Sysbox runtime (docker cp doesn't work with Sysbox)
        use_sysbox = hasattr(self.spec.security, 'runtime') and \
                     self.spec.security.runtime == "sysbox-runc"
        
        if use_sysbox:
            # Sysbox workaround: use tar to transfer files (most robust method)
            # This is what docker cp uses internally
            import tarfile
            import io
            
            # Create tar archive of the file in container
            parent_dir = os.path.dirname(container_src)
            basename = os.path.basename(container_src)
            tar_dir = parent_dir if parent_dir else "/"
            
            proc = subprocess.run(
                ["docker", "exec", self.container_name, 
                 "tar", "-cf", "-", "-C", tar_dir, basename],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            if proc.returncode != 0:
                raise RuntimeError(f"Failed to copy from Sysbox container: {proc.stderr.decode()}")
            
            # Extract tar archive to host
            tar_stream = io.BytesIO(proc.stdout)
            with tarfile.open(fileobj=tar_stream, mode='r') as tar:
                # Extract the file
                member = tar.getmember(basename)
                with tar.extractfile(member) as src, open(host_dst, 'wb') as dst:
                    dst.write(src.read())
        else:
            _sh(["docker", "cp", f"{self.container_name}:{container_src}", host_dst])

    def save_state(self, save_paths: Optional[List[str]]) -> str:
        # Tar selected paths inside container into /tmp and return that container path
        paths = save_paths or ["/workspace"]
        tar_path = f"/tmp/ga_snapshot_{uuid.uuid4().hex[:8]}.tar"
        paths_quoted = " ".join(shlex.quote(p) for p in paths)
        self.exec(f"bash -lc 'tar -cf {tar_path} {paths_quoted} 2>/dev/null || true'")
        return tar_path

    def load_state(self, snapshot_container_path: str) -> None:
        # Extract tar into root (may overwrite)
        self.exec(f"bash -lc 'tar -xf {shlex.quote(snapshot_container_path)} -C / 2>/dev/null || true'")

    # Helpers
    def _normalize_key_name(self, key: str) -> str:
        # Minimal normalization mapping for common keys to xdotool symbols
        k = key.strip()
        lower = k.lower()
        mapping = {
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
            "meta": "Super_L",
            "super": "Super_L",
            "cmd": "Super_L",
        }
        if lower in mapping:
            return mapping[lower]
        # Leave other keys as-is to preserve case-sensitive names (e.g., Return, Left)
        return k

    # Checkpoint support

    def set_checkpoint_key(self, cache_level: str, task_id: Optional[str] = None, use_savevm: bool = False) -> None:
        """Set the checkpoint key components.

        This determines which checkpoint image to look for/create.
        Must be called before checkpoint_exists(), create_checkpoint(), or start_from_checkpoint().

        Args:
            cache_level: One of "pre_start", "post_start", "post_task"
            task_id: Task ID (only relevant for post_task level)
            use_savevm: Ignored for Docker runner (savevm is QEMU-specific)
        """
        self._checkpoint_cache_level = cache_level
        self._checkpoint_task_id = task_id

    def _get_checkpoint_name(self) -> str:
        """Generate checkpoint image name based on env spec and checkpoint key.

        Checkpoint naming:
        - pre_start:  ga-checkpoint/{env_id}:{version}-pre_start
        - post_start: ga-checkpoint/{env_id}:{version}-post_start
        - post_task:  ga-checkpoint/{env_id}:{version}-post_task-{task_id}
        """
        base_name = _docker_sanitize_repo(self.spec.id)
        version = _docker_sanitize_tag(self.spec.version) if self.spec.version else "latest"
        level = self._checkpoint_cache_level

        if level == "post_task" and self._checkpoint_task_id:
            # Task-specific checkpoint
            safe_task_id = _docker_sanitize_tag(self._checkpoint_task_id.replace("/", "_").replace("@", "_"))
            return f"ga-checkpoint/{base_name}:{version}-{level}-{safe_task_id}"
        else:
            # Environment-level checkpoint (pre_start or post_start)
            return f"ga-checkpoint/{base_name}:{version}-{level}"

    def checkpoint_exists(self) -> bool:
        """Check if a checkpoint image exists for current checkpoint key."""
        checkpoint_name = self._get_checkpoint_name()
        try:
            result = subprocess.run(
                ["docker", "images", "-q", checkpoint_name],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True
            )
            exists = bool(result.stdout.strip())
            if exists:
                print(f"[gym-anything] Checkpoint found: {checkpoint_name}")
            return exists
        except Exception:
            return False

    def create_checkpoint(self) -> bool:
        """Create a checkpoint by committing the current container state.

        The checkpoint name is determined by the current checkpoint key
        (set via set_checkpoint_key).

        Returns:
            bool: True if checkpoint was created successfully, False otherwise.
        """
        if not self._running:
            print("[gym-anything] Cannot create checkpoint: container not running")
            return False

        checkpoint_name = self._get_checkpoint_name()
        print(f"[gym-anything] Creating checkpoint: {checkpoint_name}")
        print(f"[gym-anything]   cache_level={self._checkpoint_cache_level}, task_id={self._checkpoint_task_id}")

        try:
            # Commit the container to a new image
            _sh(["docker", "commit", self.container_name, checkpoint_name])
            print(f"[gym-anything] Checkpoint created successfully: {checkpoint_name}")
            return True
        except Exception as e:
            print(f"[gym-anything] Failed to create checkpoint: {e}")
            return False

    def start_from_checkpoint(self, seed: Optional[int] = None) -> bool:
        """Start a container from an existing checkpoint image.

        This bypasses the full initialization and loads a pre-configured state.
        The checkpoint name is determined by the current checkpoint key
        (set via set_checkpoint_key).

        Returns:
            bool: True if started from checkpoint successfully, False otherwise.
        """
        checkpoint_name = self._get_checkpoint_name()

        if not self.checkpoint_exists():
            print(f"[gym-anything] No checkpoint found: {checkpoint_name}")
            return False

        print(f"[gym-anything] Starting from checkpoint: {checkpoint_name}")
        print(f"[gym-anything]   cache_level={self._checkpoint_cache_level}, task_id={self._checkpoint_task_id}")

        try:
            # Temporarily store the original image
            original_image = self.spec.image

            # Replace the image with checkpoint
            self.spec.image = checkpoint_name

            # Start container (this will use the checkpoint image)
            self._start_container()

            # Clean up stale X server state from checkpoint before systemd starts services
            if self.spec.security.use_systemd:
                self._cleanup_xserver_state()
                self._wait_for_systemd()
                # Wait for GDM to start X server after cleanup
                self._wait_for_xserver()

            if not self.spec.skip_display_audio_bootstrap:
                self._bootstrap_display_audio()
            self._launch_entrypoint()

            # Mark that we loaded from checkpoint
            self._checkpoint_loaded = True
            self._checkpoint_image_name = checkpoint_name
            self._running = True

            print(f"[gym-anything] Successfully started from checkpoint")
            return True

        except Exception as e:
            print(f"[gym-anything] Failed to start from checkpoint: {e}")
            # Restore original image on failure
            self.spec.image = original_image
            return False

    def delete_checkpoint(self) -> bool:
        """Delete the checkpoint image for current checkpoint key.

        Returns:
            bool: True if checkpoint was deleted successfully, False otherwise.
        """
        checkpoint_name = self._get_checkpoint_name()

        if not self.checkpoint_exists():
            print(f"[gym-anything] No checkpoint to delete: {checkpoint_name}")
            return False

        try:
            _sh(["docker", "rmi", checkpoint_name], check=False)
            print(f"[gym-anything] Checkpoint deleted: {checkpoint_name}")
            return True
        except Exception as e:
            print(f"[gym-anything] Failed to delete checkpoint: {e}")
            return False
