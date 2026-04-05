from __future__ import annotations

import logging
import os
import time
from dataclasses import asdict
from pathlib import Path
from typing import Any, Dict, Optional, Tuple, List

from .contracts import RunnerRuntimeInfo, SessionInfo
from .specs import EnvSpec, TaskSpec
from .compatibility import get_runner_compatibility, infer_runner_key_from_name
from .runtime.post_reset import apply_post_reset_setup
from .runtime.recording.ffmpeg import FFmpegRecorder, RecordingHandle
from .runtime.recording.frames import assemble_step_video
from .runtime.runners.avd_apptainer import AVDApptainerRunner
from .runtime.runners.base import BaseRunner
from .runtime.runners.docker import DockerRunner
from .runtime.runners.local import LocalRunner
from .runtime.runners.qemu_apptainer import QemuApptainerRunner
from .runtime.runners.qemu_native import QemuNativeRunner
from .utils.jsonl import JSONLWriter
from .verification.runner import VerifierRunner
import base64
import uuid

logger = logging.getLogger(__name__)


class GymAnythingEnv:
    """Unified environment wrapper exposing Gym-like API.

    This class orchestrates a runtime runner (e.g., Docker) and optional A/V
    recording via FFmpeg. It exposes `reset`, `step`, and `close` and returns
    observation dicts keyed by modality (e.g., `screen`, `audio`, `ui_tree`).
    """

    def __init__(self, env_spec: EnvSpec, task_spec: Optional[TaskSpec] = None):
        self.env_spec = env_spec
        self.task_spec = task_spec
        self._reporter = None
        self._runner: BaseRunner = self._select_runner(env_spec)
        self._recorder: Optional[FFmpegRecorder] = None
        self._rec_handle: Optional[RecordingHandle] = None
        self._episode_dir: Optional[Path] = None
        self._step_idx: int = 0
        self._start_time: Optional[float] = None
        self._timeout_sec: Optional[int] = None
        self._max_steps: Optional[int] = None
        self._session_info: Optional[SessionInfo] = None
        self._traj_log: Optional[JSONLWriter] = None
        self._finalized: bool = False
        self._env_root: Optional[Path] = None
        self._task_root: Optional[Path] = None
        self._verifier = VerifierRunner()
        self._reward_fn = None
        self._roles = []
        self._turn_based = False
        self._turn_idx = 0

    def _select_runner(self, spec: EnvSpec) -> BaseRunner:
        """Select the appropriate runner based on environment and configuration.

        Runner selection:
        - GYM_ANYTHING_RUNNER=avd : Use AVD runner (auto-selects native on macOS)
        - GYM_ANYTHING_RUNNER=avd_native : Force AVDNativeRunner
        - GYM_ANYTHING_RUNNER=qemu : Use QEMU runner (auto-selects native on macOS)
        - GYM_ANYTHING_RUNNER=qemu_native : Force QemuNativeRunner
        - GYM_ANYTHING_RUNNER=apptainer : Use ApptainerDirectRunner (GPU-enabled, no QEMU)
        - GYM_ANYTHING_RUNNER=docker : Use DockerRunner (explicit)
        - Default: Auto-detect based on spec.runner field, then Docker, fallback to QEMU

        The SAME env.json files work with all runners!
        """
        runner_override = os.environ.get("GYM_ANYTHING_RUNNER", "").lower()

        spec_runner = getattr(spec, 'runner', None)
        spec_base = getattr(spec, 'base', None)

        # --- AVF runner (Apple Virtualization Framework + Rosetta) ---
        if runner_override == "avf" or spec_runner == "avf":
            from .runtime.runners.avf import AVFRunner
            logger.info("Using AVFRunner (Apple Virtualization Framework + Rosetta)")
            return AVFRunner(spec)

        # --- AVD runners ---
        if runner_override == "avd_native" or spec_runner == "avd_native":
            from .runtime.runners.avd_native import AVDNativeRunner
            logger.info("Using AVDNativeRunner (no Apptainer)")
            return AVDNativeRunner(spec)

        if runner_override == "avd" or spec_runner == "avd":
            return self._make_avd_runner(spec)

        # --- Direct Apptainer runner (GPU-enabled, no QEMU) ---
        if runner_override == "apptainer" or spec_runner == "apptainer":
            logger.info("Using ApptainerDirectRunner (GPU-enabled)")
            from .runtime.runners.apptainer_direct import ApptainerDirectRunner
            return ApptainerDirectRunner(spec)

        # --- QEMU runners ---
        if runner_override == "qemu_native":
            logger.info("Using QemuNativeRunner (GYM_ANYTHING_RUNNER=qemu_native)")
            return QemuNativeRunner(spec)

        if runner_override == "qemu" or spec_runner == "qemu":
            return self._make_qemu_runner(spec)

        # --- Explicit simple runners ---
        if runner_override == "local" or spec_runner == "local":
            logger.info("Using LocalRunner")
            return LocalRunner(spec)

        if runner_override == "docker":
            pass  # Fall through to docker runner
        elif runner_override:
            logger.warning("Unknown runner '%s', using default", runner_override)

        # --- Auto-detect: pick the best available runner for this platform ---
        if not runner_override:
            import sys as _sys
            import platform as _platform

            if _sys.platform == "darwin" and _platform.machine() == "arm64":
                # Apple Silicon: prefer AVF (Rosetta) > QemuNative (aarch64+HVF) > Docker
                if self._check_avf_available():
                    from .runtime.runners.avf import AVFRunner
                    logger.info("Using AVFRunner (Apple Silicon, auto-detected)")
                    return AVFRunner(spec)
                if self._check_qemu_native_available():
                    logger.info("Using QemuNativeRunner (Apple Silicon, auto-detected)")
                    return QemuNativeRunner(spec)
            elif _sys.platform == "darwin":
                # Intel Mac: prefer QemuNative (x86+HVF) > Docker
                if self._check_qemu_native_available():
                    logger.info("Using QemuNativeRunner (Intel Mac, auto-detected)")
                    return QemuNativeRunner(spec)
            else:
                # Linux: prefer QemuApptainer > QemuNative > Docker
                if self._check_apptainer_available():
                    logger.info("Using QemuApptainerRunner (auto-detected)")
                    return QemuApptainerRunner(spec)
                if self._check_qemu_native_available():
                    logger.info("Using QemuNativeRunner (auto-detected)")
                    return QemuNativeRunner(spec)

            # Fallback: Docker
            if self._check_docker_available() and (spec.image or spec.dockerfile):
                logger.info("Using DockerRunner (fallback)")
                return DockerRunner(spec)

            logger.warning("No suitable runtime found. Run: gym-anything doctor")
            return LocalRunner(spec)

    def _make_qemu_runner(self, spec: EnvSpec) -> BaseRunner:
        """Auto-select between QemuApptainerRunner and QemuNativeRunner."""
        import sys
        if sys.platform == "darwin":
            logger.info("Using QemuNativeRunner (macOS detected)")
            return QemuNativeRunner(spec)
        if self._check_apptainer_available():
            logger.info("Using QemuApptainerRunner")
            return QemuApptainerRunner(spec)
        if self._check_qemu_native_available():
            logger.info("Apptainer not found, using QemuNativeRunner")
            return QemuNativeRunner(spec)
        raise RuntimeError(
            "runner=qemu but neither Apptainer nor native QEMU found. "
            "Install Apptainer or QEMU (brew install qemu / apt install qemu-system-x86)."
        )

    def _make_avd_runner(self, spec: EnvSpec) -> BaseRunner:
        """Auto-select between AVDApptainerRunner and AVDNativeRunner."""
        import sys
        if sys.platform == "darwin":
            from .runtime.runners.avd_native import AVDNativeRunner
            logger.info("Using AVDNativeRunner (macOS detected)")
            return AVDNativeRunner(spec)
        if self._check_apptainer_available():
            logger.info("Using AVDApptainerRunner")
            return AVDApptainerRunner(spec)
        # Fallback to native if Apptainer missing
        from .runtime.runners.avd_native import AVDNativeRunner
        logger.info("Apptainer not found, using AVDNativeRunner")
        return AVDNativeRunner(spec)
    
    def _check_docker_available(self) -> bool:
        """Check if Docker daemon is available and running."""
        import subprocess
        try:
            result = subprocess.run(
                ["docker", "info"],
                capture_output=True,
                timeout=5
            )
            return result.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return False
    
    def _check_apptainer_available(self) -> bool:
        """Check if Apptainer is installed."""
        import subprocess
        try:
            result = subprocess.run(
                ["apptainer", "--version"],
                capture_output=True,
                timeout=5
            )
            return result.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return False

    def _check_qemu_native_available(self) -> bool:
        """Check if QEMU is installed directly on the host."""
        import shutil
        import platform
        if platform.machine() in ("arm64", "aarch64"):
            return shutil.which("qemu-system-aarch64") is not None
        return shutil.which("qemu-system-x86_64") is not None

    def set_reporter(self, reporter) -> None:
        self._reporter = reporter
        self._runner.set_reporter(reporter)

    def _check_avf_available(self) -> bool:
        """Check if Apple Virtualization Framework tooling is available."""
        import shutil
        return (shutil.which("vfkit") is not None
                and shutil.which("gvproxy") is not None)

    def _platform_family(self) -> str:
        getter = getattr(self._runner, "get_platform_family", None)
        if callable(getter):
            return getter()
        os_type = getattr(self.env_spec, "os_type", None)
        if os_type in {"linux", "windows", "android"}:
            return os_type
        if getattr(self._runner, "is_android", False):
            return "android"
        if getattr(self._runner, "is_windows", False):
            return "windows"
        return "linux"

    def _runtime_info(self) -> RunnerRuntimeInfo:
        getter = getattr(self._runner, "get_runtime_info", None)
        if callable(getter):
            return getter()
        return RunnerRuntimeInfo(
            platform_family=self._platform_family(),
            container_name=getattr(self._runner, "container_name", None),
            instance_name=getattr(self._runner, "instance_name", None),
            vnc_port=getattr(self._runner, "vnc_port", None) or getattr(self._runner, "vnc_host_port", None),
            vnc_password=getattr(self._runner, "vnc_password", None),
            ssh_port=getattr(self._runner, "ssh_port", None),
            ssh_user=getattr(self._runner, "_ssh_user", None),
            ssh_password=getattr(self._runner, "_ssh_password", None),
        )

    # Public API
    def reset(self, seed: Optional[int] = None, use_cache: bool = False,
              cache_level: str = "pre_start", use_savevm: bool = False) -> Dict[str, Any]:
        """Reset the environment.

        Args:
            seed: Random seed for reproducibility
            use_cache: Whether to use/create checkpoints for faster startup
            cache_level: When to create checkpoint and what to skip when loading. Options:
                - "pre_start": Checkpoint after pre_start hook. On load: skip pre_start only.
                - "post_start": Checkpoint after post_start hook. On load: skip pre_start AND post_start.
                - "post_task": Checkpoint after pre_task/init. On load: skip ALL hooks/init.
                              Note: post_task checkpoints are task-specific.
            use_savevm: If True, use QEMU savevm/loadvm for true VM state checkpointing.
                       This preserves memory, CPU state, running processes, and GUI state.
                       On restore, uses loadvm for instant state restoration (no reboot).
                       Only effective with QemuApptainerRunner. Requires use_cache=True.

                       Benefits of use_savevm=True:
                       - Instant restore (~3s vs 2-5min reboot)
                       - Preserves running processes (PyAutoGUI server, apps)
                       - Preserves GUI state (open windows, Notepad with text)
                       - Multiple instances can share the same checkpoint (COW overlays)

        Returns:
            Initial observation dictionary

        Checkpoint Behavior:
            When use_cache=True:
            1. First run: Executes all hooks up to cache_level, creates checkpoint, continues
            2. Subsequent runs: Loads from checkpoint, skips hooks up to cache_level, runs remaining

            Fallback: If the requested cache_level checkpoint is missing, falls back to
            lower levels (e.g., post_start -> pre_start -> scratch). This avoids redundant
            work when a lower-level checkpoint already exists.

            Example with cache_level="post_start":
            - First run: pre_start -> post_start -> [CHECKPOINT] -> reset -> pre_task -> init
            - Next runs: [LOAD CHECKPOINT] -> reset -> pre_task -> init

            With use_savevm=True (for QEMU runner):
            - Checkpoint includes full VM state (memory + disk)
            - Restore uses loadvm for instant state recovery
            - No need to wait for SSH/desktop/services
        """
        if self._episode_dir is not None or self._traj_log is not None:
            self.close()

        self._step_idx = 0
        self._finalized = False
        self._reward_fn = None
        self._recorder = None
        self._rec_handle = None
        self._session_info = None
        self._ensure_episode_dir()

        if use_cache and not self._runner.supports_checkpoint_caching():
            raise ValueError(
                f"Runner {type(self._runner).__name__} does not support checkpoint caching"
            )
        if use_savevm and not self._runner.supports_savevm():
            raise ValueError(
                f"Runner {type(self._runner).__name__} does not support use_savevm=True"
            )

        # Validate cache_level
        valid_levels = ["pre_start", "post_start", "post_task"]
        if cache_level not in valid_levels:
            raise ValueError(f"cache_level must be one of {valid_levels}, got '{cache_level}'")

        # Get task_id for post_task checkpoints (task-specific)
        task_id = self.task_spec.id if self.task_spec else None

        # Check if we can use cached checkpoint
        checkpoint_loaded = False
        checkpoint_level = None  # Track which level we loaded from

        # Always set checkpoint key if use_savevm=True, even when not using cache.
        # This is needed because use_savevm affects how the VM is started (OVMF_VARS readonly).
        # If user later creates a checkpoint, the VM needs to have been booted correctly.
        if use_savevm or use_cache:
            self._runner.set_checkpoint_key(cache_level, task_id, use_savevm=use_savevm)

        if use_cache:
            # Try the requested cache level first, then fall back to lower levels.
            # E.g., if post_start cache is missing but pre_start exists, load pre_start
            # and run only the remaining hooks (saving time by skipping earlier hooks).
            _fallback_order = {
                "post_task":  ["post_task", "post_start", "pre_start"],
                "post_start": ["post_start", "pre_start"],
                "pre_start":  ["pre_start"],
            }
            for try_level in _fallback_order[cache_level]:
                self._runner.set_checkpoint_key(try_level, task_id, use_savevm=use_savevm)
                if self._runner.checkpoint_exists():
                    if self._runner.start_from_checkpoint(seed=seed) and not os.environ.get("FORCE_REGENERATE_CHECKPOINT", False):
                        checkpoint_loaded = True
                        checkpoint_level = try_level  # actual loaded level, not requested
                        savevm_msg = " (with savevm)" if use_savevm else ""
                        if try_level != cache_level:
                            logger.info(
                                "Loaded from checkpoint (level=%s, requested=%s)%s - running remaining hooks",
                                try_level,
                                cache_level,
                                savevm_msg,
                            )
                        else:
                            logger.info(
                                "Loaded from checkpoint (level=%s)%s - skipping setup up to this point",
                                cache_level,
                                savevm_msg,
                            )
                        break
                    else:
                        logger.warning(
                            "Failed to load checkpoint at level=%s - trying next level",
                            try_level,
                        )
            if not checkpoint_loaded:
                logger.info("No checkpoint found at any level - full setup required")

        # If not loaded from checkpoint, do full setup
        if not checkpoint_loaded:
            self._runner.start(seed=seed)

        self._start_time = time.time()
        if self.task_spec:
            self._timeout_sec = self.task_spec.init.timeout_sec
            self._max_steps = self.task_spec.init.max_steps
        else:
            self._timeout_sec = None
            self._max_steps = None

        # Multi-agent config
        if self.env_spec.multi_agent and isinstance(self.env_spec.multi_agent, dict):
            self._roles = list(self.env_spec.multi_agent.get("roles", []))
            self._turn_based = bool(self.env_spec.multi_agent.get("turn_based", False))
            self._turn_idx = 0

        # Open trajectory log
        self._traj_log = JSONLWriter(self._episode_dir / "traj.jsonl")
        self._traj_log.write({
            "event": "reset",
            "ts": self._start_time,
            "seed": seed,
            "env": self.env_spec.id,
            "task": task_id,
            "use_cache": use_cache,
            "cache_level": cache_level if use_cache else None,
            "use_savevm": use_savevm if use_cache else None,
            "checkpoint_loaded": checkpoint_loaded,
        })

        # =====================================================================
        # HOOK EXECUTION LOGIC
        #
        # Skip hooks that are BEFORE OR AT the checkpoint_level we loaded from.
        # Run hooks that are AFTER the checkpoint_level.
        #
        # Level order: pre_start < post_start < post_task
        # =====================================================================

        level_order = {"pre_start": 1, "post_start": 2, "post_task": 3}
        loaded_level_num = level_order.get(checkpoint_level, 0) if checkpoint_loaded else 0

        # === PRE_START HOOK ===
        # Skip if checkpoint_loaded and checkpoint was at pre_start or later
        if loaded_level_num < level_order["pre_start"]:
            if getattr(self.env_spec, "hooks", None) and self.env_spec.hooks.get("pre_start"):
                if self._reporter:
                    self._reporter.stage_start("pre_start_hook")
                logger.info("Running pre_start hook")
                try:
                    hook_cmd = self.env_spec.hooks['pre_start']
                    # Android uses sh instead of bash, and different paths
                    # Use longer timeout (180s) for Android hooks as game loading can take time
                    if self._platform_family() == "android":
                        self._runner.exec(f"sh {hook_cmd}", timeout=180)
                    # Windows uses PowerShell
                    elif self._platform_family() == "windows":
                        self._runner.exec(hook_cmd)
                    else:
                        self._runner.exec(f"bash -lc {hook_cmd} > /home/ga/env_setup_pre_start.log 2>&1", timeout=1800)
                    if self._reporter:
                        self._reporter.stage_done("pre_start_hook")
                except Exception as e:
                    logger.warning("pre_start hook failed: %s", e)
                    if self._reporter:
                        self._reporter.stage_fail("pre_start_hook", str(e))

        # Create checkpoint after pre_start if this is the target level
        # Also creates when we started from scratch with a higher cache_level target
        if use_cache and cache_level == "pre_start" and checkpoint_level != "pre_start":
            savevm_msg = " (with savevm)" if use_savevm else ""
            logger.info("Creating checkpoint at level=pre_start%s", savevm_msg)
            self._runner.set_checkpoint_key(cache_level, task_id, use_savevm=use_savevm)
            self._runner.create_checkpoint()

        # === DOCKERHUB AUTHENTICATION ===
        # Authenticate with DockerHub inside the guest before post_start hooks
        # that may run docker compose pull / docker run. Pre_start caches are
        # already available, so this runs after pre_start but before post_start.
        # Fails silently if Docker is not installed in the guest.
        if loaded_level_num < level_order["post_start"]:
            self._dockerhub_login_in_guest()

        # === POST_START HOOK ===
        # Skip if checkpoint_loaded and checkpoint was at post_start or later
        if loaded_level_num < level_order["post_start"]:
            if getattr(self.env_spec, "hooks", None) and self.env_spec.hooks.get("post_start"):
                if self._reporter:
                    self._reporter.stage_start("post_start_hook")
                logger.info("Running post_start hook")
                try:
                    hook_cmd = self.env_spec.hooks['post_start']
                    # Android uses sh instead of bash, and different paths
                    # Use longer timeout (180s) for Android hooks as game loading can take time
                    if self._platform_family() == "android":
                        self._runner.exec(f"sh {hook_cmd}", timeout=180)
                    # Windows uses PowerShell
                    elif self._platform_family() == "windows":
                        self._runner.exec(hook_cmd)
                    else:
                        self._runner.exec(f"bash -lc {hook_cmd} > /home/ga/env_setup_post_start.log 2>&1", timeout=1800)
                    if self._reporter:
                        self._reporter.stage_done("post_start_hook")
                except Exception as e:
                    logger.warning("post_start hook failed: %s", e)
                    if self._reporter:
                        self._reporter.stage_fail("post_start_hook", str(e))

        # Create checkpoint after post_start if this is the target level
        # Also creates when we loaded from a lower level (e.g., pre_start fallback)
        if use_cache and cache_level == "post_start" and checkpoint_level != "post_start":
            savevm_msg = " (with savevm)" if use_savevm else ""
            logger.info("Creating checkpoint at level=post_start%s", savevm_msg)
            self._runner.set_checkpoint_key(cache_level, task_id, use_savevm=use_savevm)
            self._runner.create_checkpoint()

        # === RESET SCRIPT ===
        # Always runs (not part of checkpoint levels)
        if self.env_spec.reset_script:
            self._runner.run_reset(self.env_spec.reset_script, seed=seed)
        elif getattr(self.env_spec, "hooks", None) and self.env_spec.hooks.get("reset"):
            try:
                hook_cmd = self.env_spec.hooks['reset']
                # Windows uses PowerShell
                if self._platform_family() == "windows":
                    self._runner.exec(hook_cmd)
                else:
                    self._runner.exec(f"bash -lc {hook_cmd}")
            except Exception:
                pass

        # === PRE_TASK HOOK ===
        # Skip if checkpoint_loaded and checkpoint was at post_task
        if loaded_level_num < level_order["post_task"]:
            if self.task_spec and self.task_spec.hooks and self.task_spec.hooks.pre_task:
                if self._reporter:
                    self._reporter.stage_start("pre_task_hook")
                logger.info("Running pre_task hook")
                try:
                    hook_cmd = self.task_spec.hooks.pre_task
                    # Android uses sh instead of bash, and different paths
                    # Use longer timeout (180s) for Android hooks as game loading can take time
                    if self._platform_family() == "android":
                        self._runner.exec(hook_cmd, timeout=180)
                    # Windows uses PowerShell directly (hook_cmd already contains full PowerShell command)
                    elif self._platform_family() == "windows":
                        self._runner.exec(hook_cmd, use_pty=False)
                    else:
                        # Use configurable timeout for pre_task hook (default 600s, can be overridden in task.json)
                        hook_timeout = self.task_spec.hooks.pre_task_timeout if self.task_spec.hooks else 600
                        self._runner.exec(f"bash -lc {hook_cmd} > /home/ga/task_pre_task.log 2>&1", use_pty=False, timeout=hook_timeout)
                    self._capture_observation()
                    if self._reporter:
                        self._reporter.stage_done("pre_task_hook")
                except Exception as e:
                    logger.warning("pre_task hook failed: %s", e)
                    if self._reporter:
                        self._reporter.stage_fail("pre_task_hook", str(e))

            # === TASK INIT SCRIPT ===
            if self.task_spec and self.task_spec.init.init_script:
                self._runner.run_task_init(self.task_spec.init.init_script)

            # === INIT PYAUTOGUI ACTIONS (for Windows) ===
            if self.task_spec and self.task_spec.init.init_pyautogui:
                logger.info("Running init_pyautogui actions")
                self._run_init_pyautogui(self.task_spec.init.init_pyautogui)
        # breakpoint()
        # Create checkpoint after pre_task/init if this is the target level
        # Also creates when we loaded from a lower level (e.g., post_start or pre_start fallback)
        if use_cache and cache_level == "post_task" and checkpoint_level != "post_task":
            savevm_msg = " (with savevm)" if use_savevm else ""
            logger.info("Creating checkpoint at level=post_task%s", savevm_msg)
            self._runner.set_checkpoint_key(cache_level, task_id, use_savevm=use_savevm)
            self._runner.create_checkpoint()

        # Start recording if enabled
        if self.env_spec.recording.enable and self._runner.supports_live_recording():
            self._recorder = FFmpegRecorder(self._runner)
            self._rec_handle = self._recorder.start(
                out_dir=self._episode_dir,
                fps=self.env_spec.recording.video_fps,
                resolution=self.env_spec.recording.video_resolution,
                vcodec=self.env_spec.recording.video_codec,
                vcrf=self.env_spec.recording.video_crf,
                ar=self.env_spec.recording.audio_rate,
                ac=self.env_spec.recording.audio_channels,
                acodec=self.env_spec.recording.audio_codec,
            )

        # Load dense reward function if configured
        if self.task_spec and self.task_spec.init.reward_type == "dense":
            if self.task_spec.init.reward_shaping:
                self._reward_fn = self._load_reward_fn(self.task_spec.init.reward_shaping)
            else:
                self._reward_fn = None

        # Session info
        screen_spec = next((o for o in self.env_spec.observation if o.type == "rgb_screen"), None)
        runtime_info = self._runtime_info()
        self._session_info = SessionInfo(
            env_id=self.env_spec.id,
            task_id=self.task_spec.id if self.task_spec else None,
            runner_name=self.runner_name,
            platform_family=runtime_info.platform_family,
            artifacts_dir=str(self._episode_dir) if self._episode_dir else None,
            resolution=screen_spec.resolution if screen_spec and screen_spec.resolution else None,
            fps=screen_spec.fps if screen_spec else None,
            network_enabled=self.env_spec.resources.net,
            systemd_enabled=bool(getattr(self.env_spec.security, "use_systemd", False)),
            container_name=runtime_info.container_name,
            instance_name=runtime_info.instance_name,
            vnc_port=runtime_info.vnc_port,
            vnc_url=f"vnc://localhost:{runtime_info.vnc_port}" if runtime_info.vnc_port else None,
            vnc_password=runtime_info.vnc_password,
            ssh_port=runtime_info.ssh_port,
            ssh_user=runtime_info.ssh_user,
            ssh_password=runtime_info.ssh_password,
        )
        if self._traj_log:
            self._traj_log.write({"event": "session", **self._session_info.to_dict()})
        logger.info("Session: %s", self._session_info.to_dict())

        # First observation (capture initial screen/audio as frame_00000)
        return self._capture_observation()

    def step(self, actions: List[Dict[str, Any]], wait_between_actions: float = 0.2, mark_done: bool = False) -> Tuple[Dict[str, Any], float, bool, Dict[str, Any]]:
        # Multi-agent: accept mapping role->action, else annotate turn-based role
        if isinstance(actions, dict):
            actions = [actions]
        injected_actions = 0
        control_result: Optional[Dict[str, Any]] = None
        for action_num, action in enumerate(actions):
            control = self._parse_control_action(action)
            if control is not None:
                if control["kind"] == "wait":
                    seconds = control["seconds"]
                    time.sleep(seconds)
                    control_result = {
                        "action": "wait",
                        "output": f"Waited for {seconds} seconds",
                    }
                elif control["kind"] == "screenshot":
                    control_result = {"action": "screenshot"}
                continue
            if self._roles and isinstance(action, dict) and any(r in action for r in self._roles):
                for r in self._roles:
                    a = action.get(r)
                    if a:
                        a = dict(a)
                        a["_role"] = r
                        self._runner.inject_action(a)
                        injected_actions += 1
            else:
                if self._roles and self._turn_based:
                    current_role = self._roles[self._turn_idx % max(1, len(self._roles))]
                    action = dict(action)
                    action["_role"] = current_role
                    self._turn_idx += 1
                self._runner.inject_action(action)
                injected_actions += 1
            if wait_between_actions and action_num < len(actions) - 1:
                time.sleep(wait_between_actions)
        if injected_actions:
            time.sleep(2)
        # For synchronous envs, wait for the step cycle
        if injected_actions and self.env_spec.synchronous and self.env_spec.step_cycle_ms:
            time.sleep(self.env_spec.step_cycle_ms / 1000.0)
        obs: Dict[str, Any] = self._capture_observation()

        # Log step
        if self._traj_log:
            self._traj_log.write({
                "event": "step",
                "ts": time.time(),
                "idx": self._step_idx,
                "action": actions,
            })

        reward = 0.0
        done = False
        info: Dict[str, Any] = {"step": self._step_idx}
        if actions:
            if control_result is not None and injected_actions == 0 and len(actions) == 1:
                if control_result["action"] == "screenshot":
                    control_result["output"] = obs.get("screen", {}).get("path")
                info["action_result"] = control_result
            else:
                info["action_result"] = {
                    "action": "other",
                    "output": "Executed the action",
                }
        # Dense reward shaping if configured
        if self._reward_fn is not None:
            try:
                env_info = {"env_id": self.env_spec.id, "episode_dir": str(self._episode_dir)}
                task_info = {
                    "task_id": self.task_spec.id if self.task_spec else None,
                    "metadata": self.task_spec.metadata if self.task_spec else {},
                    "task_spec": asdict(self.task_spec) if self.task_spec else {},
                }
                step_event = {"idx": self._step_idx, "action": actions, "obs": obs}
                reward = float(self._reward_fn(step_event, env_info, task_info))
            except Exception:
                reward = 0.0
        # Check termination conditions
        if self._max_steps is not None and self._step_idx + 1 >= self._max_steps:
            done = True
            info["reason"] = "max_steps"
        if self._timeout_sec is not None and self._start_time is not None:
            if time.time() - self._start_time >= self._timeout_sec:
                done = True
                info["reason"] = info.get("reason", "timeout")
        if mark_done:
            done = True
            info["reason"] = "Agent Completed"
        if done:
            summary = self._complete_episode()
            info["verifier"] = summary.get("verifier")
            reward = self._final_reward(summary, current_reward=reward)
        self._step_idx += 1
        return obs, reward, done, info

    def _parse_control_action(self, action: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        if not isinstance(action, dict):
            return None

        kind = action.get("action") or action.get("type")
        if kind == "screenshot":
            return {"kind": "screenshot"}
        if kind == "wait":
            seconds = action.get("time")
            if seconds is None:
                seconds = action.get("seconds", 1.0)
            try:
                return {"kind": "wait", "seconds": float(seconds)}
            except (TypeError, ValueError):
                return {"kind": "wait", "seconds": 1.0}
        return None

    def capture_observation(self) -> Dict[str, Any]:
        """Capture the current observation without advancing the episode."""
        return self._capture_observation()

    def set_episode_limits(
        self,
        *,
        max_steps: Optional[int] = None,
        timeout_sec: Optional[int] = None,
    ) -> None:
        """Override the active episode limits after reset."""
        self._max_steps = max_steps
        self._timeout_sec = timeout_sec

    @property
    def max_steps(self) -> Optional[int]:
        return self._max_steps

    @property
    def timeout_sec(self) -> Optional[int]:
        return self._timeout_sec

    @property
    def episode_dir(self) -> Optional[Path]:
        return self._episode_dir

    @property
    def artifacts_dir(self) -> Optional[Path]:
        return self._episode_dir

    @property
    def env_root(self) -> Optional[Path]:
        return self._env_root

    @property
    def task_root(self) -> Optional[Path]:
        return self._task_root

    @property
    def runner_name(self) -> str:
        return type(self._runner).__name__

    def get_session_info(self) -> Optional[SessionInfo]:
        return self._session_info

    def get_compatibility_profile(self) -> Dict[str, Any]:
        runner_key = infer_runner_key_from_name(self.runner_name)
        if runner_key is None:
            return {
                "runner": self.runner_name,
                "display_name": self.runner_name,
                "live_recording": self._runner.supports_live_recording(),
                "screenshot_video_assembly": bool(self.env_spec.recording.enable),
                "checkpoint_caching": self._runner.supports_checkpoint_caching(),
                "savevm": self._runner.supports_savevm(),
                "user_accounts_mode": "unknown",
                "notes": [],
            }
        return get_runner_compatibility(runner_key).to_dict()

    def apply_post_reset_setup(
        self,
        setup_code: str = "auto",
        *,
        steps: Optional[int] = None,
        env_dir: Optional[str] = None,
    ) -> bool:
        """Apply an optional standardized post-reset setup routine."""
        return apply_post_reset_setup(self, setup_code=setup_code, steps=steps, env_dir=env_dir)

    def close(self) -> None:
        if not self._finalized:
            try:
                self._complete_episode()
            except Exception:
                pass
        if self._recorder and self._rec_handle:
            try:
                self._recorder.stop(self._rec_handle)
            except Exception:
                pass
        try:
            self._ensure_recording_artifact()
        except Exception:
            pass
        self._runner.stop()
        self._recorder = None
        self._rec_handle = None
        self._episode_dir = None
        self._session_info = None
        if self._traj_log:
            self._traj_log.close()
            self._traj_log = None

    # Helpers
    def _ensure_episode_dir(self) -> None:
        base = Path(self.env_spec.recording.output_dir)
        base.mkdir(parents=True, exist_ok=True)
        ts = time.strftime("%Y%m%d_%H%M%S")
        # Since there could be a clash in episode directory_name, add a uuid to the end of the directory name
        uuid_string = str(uuid.uuid4())
        logger.debug("Creating episode directory at %s", ts)
        d = base / f"episode_{ts}_{uuid_string}"
        d.mkdir(parents=True, exist_ok=True)
        self._episode_dir = d

    def _complete_episode(self) -> Dict[str, Any]:
        if self._finalized:
            return {}
        self._run_post_task_hook()
        settle_seconds = self._post_task_settle_seconds()
        if settle_seconds > 0:
            time.sleep(settle_seconds)
        if self._episode_dir:
            try:
                self._runner.capture_screenshot(self._episode_dir / "post_verification.png")
            except Exception:
                pass
        return self._finalize_episode()

    def _final_reward(self, summary: Dict[str, Any], *, current_reward: float) -> float:
        if not self.task_spec:
            return current_reward
        reward_type = self.task_spec.init.reward_type
        verifier = summary.get("verifier", {}) or {}
        passed = bool(verifier.get("passed"))
        try:
            score = float(verifier.get("score", 100.0 if passed else 0.0))
        except Exception:
            score = 100.0 if passed else 0.0
        score = max(0.0, min(100.0, score))

        if reward_type == "dense":
            return current_reward
        if reward_type == "sparse":
            return 1.0 if passed else 0.0
        if reward_type in {"partial", "rubric"}:
            return score
        if reward_type == "continuous":
            return score / 100.0
        return current_reward

    def _run_post_task_hook(self) -> None:
        if not (self.task_spec and self.task_spec.hooks and self.task_spec.hooks.post_task):
            return
        try:
            hook_cmd = self.task_spec.hooks.post_task
            if self._platform_family() == "android":
                self._runner.exec(hook_cmd)
            elif self._platform_family() == "windows":
                self._runner.exec(hook_cmd)
            else:
                self._runner.exec(f"bash -lc {hook_cmd} > /home/ga/task_post_task.log 2>&1")
        except Exception:
            pass

    def _post_task_settle_seconds(self) -> float:
        has_post_task_hook = bool(
            self.task_spec
            and self.task_spec.hooks
            and self.task_spec.hooks.post_task
        )
        if not has_post_task_hook:
            return 0.0
        if "GYM_ANYTHING_POST_TASK_SETTLE_SEC" in os.environ:
            try:
                return max(0.0, float(os.environ["GYM_ANYTHING_POST_TASK_SETTLE_SEC"]))
            except ValueError:
                return 15.0
        if self.task_spec:
            for source in (self.task_spec.extras, self.task_spec.metadata):
                value = source.get("post_task_settle_sec") if isinstance(source, dict) else None
                if value is not None:
                    try:
                        return max(0.0, float(value))
                    except (TypeError, ValueError):
                        return 15.0
        return 15.0

    def _ensure_recording_artifact(self) -> None:
        if not self._episode_dir or not self.env_spec.recording.enable:
            return
        recording_path = self._episode_dir / "recording.mp4"
        if recording_path.exists():
            return
        assemble_step_video(
            self._episode_dir,
            fps=self.env_spec.recording.video_fps,
            vcodec=self.env_spec.recording.video_codec,
            vcrf=self.env_spec.recording.video_crf,
        )

    def _finalize_episode(self) -> Dict[str, Any]:
        if self._finalized:
            return {}
        # Capture final screenshot for potential image verification
        final_png = self._episode_dir / "final.png" if self._episode_dir else None
        if final_png:
            try:
                self._runner.capture_screenshot(final_png)
            except Exception:
                pass

        # Run verifier if task_spec provided
        summary: Dict[str, Any] = {
            "env": self.env_spec.id,
            "task": self.task_spec.id if self.task_spec else None,
            "start_ts": self._start_time,
            "end_ts": time.time(),
            "steps": self._step_idx + 1,
        }
        if self.task_spec:
            # breakpoint()
            result = self._verifier.evaluate(
                runner=self._runner,
                env_spec=self.env_spec,
                task_spec=self.task_spec,
                episode_dir=self._episode_dir,
                env_root=self._env_root,
                task_root=self._task_root,
            )
            summary["verifier"] = result
        # Write summary
        if self._episode_dir:
            def sanitize_json(obj):
                """Convert numpy types to native Python types for JSON serialization"""
                import json
                import numpy as np
                
                def convert(item):
                    if isinstance(item, np.bool_):
                        return bool(item)
                    elif isinstance(item, (np.integer, np.floating)):
                        return item.item()
                    elif isinstance(item, np.ndarray):
                        return item.tolist()
                    elif isinstance(item, dict):
                        return {k: convert(v) for k, v in item.items()}
                    elif isinstance(item, (list, tuple)):
                        return [convert(v) for v in item]
                    return item
                
                return convert(obj)
            
            (self._episode_dir / "summary.json").write_text(
                __import__("json").dumps(sanitize_json(summary), indent=2)
            )
            # Diagnostics: copy common logs from container to artifacts
            if getattr(self.env_spec, "diagnostics", False):
                logs = [
                    "/tmp/xvfb.log",
                    "/tmp/pulseaudio.log",
                    "/tmp/x11vnc.log",
                    "/tmp/gnome.log",
                    "/tmp/terminal.log",
                    "/tmp/fluxbox.log",
                    "/tmp/ffmpeg.log",

                    # All hook logs
                    "/home/ga/task_pre_task.log",
                    "/home/ga/task_post_task.log",
                    "/home/ga/env_setup_pre_start.log",
                    "/home/ga/env_setup_post_start.log",
                ]
                for lp in logs:
                    try:
                        dest = self._episode_dir / (Path(lp).name)
                        self._runner.copy_from(lp, str(dest))
                    except Exception:
                        pass
            if not self._rec_handle:
                self._ensure_recording_artifact()
        # Close trajectory log
        if self._traj_log:
            self._traj_log.write({"event": "finalize", "ts": time.time()})
            self._traj_log.close()
            self._traj_log = None
        self._finalized = True
        return summary

    def _load_reward_fn(self, ref: str):
        # Support "file.py::func" relative to task_root or "pkg.mod:func" or "file.py" (compute_reward)
        import importlib
        import importlib.util
        if "::" in ref:
            file, func = ref.split("::", 1)
            if not self._task_root:
                raise ValueError("task_root not set for file-based reward_shaping")
            path = self._task_root / file
            spec = importlib.util.spec_from_file_location("task_reward", path)
            if not spec or not spec.loader:
                raise ImportError(f"cannot import reward from {path}")
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)  # type: ignore[attr-defined]
            return getattr(mod, func)
        if ":" in ref:
            mod_name, func = ref.split(":", 1)
            mod = importlib.import_module(mod_name)
            return getattr(mod, func)
        # Assume a file path with default name compute_reward
        if self._task_root:
            from importlib.util import spec_from_file_location, module_from_spec
            path = self._task_root / ref
            spec = spec_from_file_location("task_reward", path)
            if not spec or not spec.loader:
                raise ImportError(f"cannot import reward from {path}")
            mod = module_from_spec(spec)
            spec.loader.exec_module(mod)  # type: ignore[attr-defined]
            return getattr(mod, "compute_reward")
        raise ValueError("Invalid reward_shaping reference and no task_root set")

    def _run_init_pyautogui(self, actions: list) -> None:
        """Execute PyAutoGUI initialization actions for Windows tasks.

        Actions format (each is a dict):
        - {"type": "keys", "keys": ["win", "r"]} - Press key combination
        - {"type": "text", "text": "notepad"} - Type text
        - {"type": "click", "x": 640, "y": 400} - Click at position
        - {"type": "wait", "seconds": 1.5} - Wait for seconds
        """
        import time

        # Check if runner has PyAutoGUI client
        pyautogui_client = getattr(self._runner, '_pyautogui_client', None)
        if not pyautogui_client:
            logger.warning("No PyAutoGUI client available for init_pyautogui")
            return

        for action in actions:
            try:
                action_type = action.get("type")
                if action_type == "keys":
                    keys = action.get("keys", [])
                    pyautogui_client.hotkey(*keys)
                elif action_type == "text":
                    text = action.get("text", "")
                    interval = action.get("interval", 0.08)
                    pyautogui_client.write(text, interval=interval)
                elif action_type == "click":
                    x = action.get("x", 640)
                    y = action.get("y", 400)
                    pyautogui_client.click(x, y)
                elif action_type == "wait":
                    seconds = action.get("seconds", 1)
                    time.sleep(seconds)
                else:
                    logger.warning("Unknown init_pyautogui action type: %s", action_type)
            except Exception as e:
                logger.warning("init_pyautogui action failed: %s", e)

    def _dockerhub_login_in_guest(self) -> None:
        """Authenticate with DockerHub inside the guest VM/container.

        Reads DOCKERHUB_USERNAME and DOCKERHUB_TOKEN from the host environment
        (typically loaded from .env via python-dotenv) and runs `docker login`
        inside the guest. This prevents DockerHub rate-limiting during
        docker compose pull / docker run in post_start hooks.

        Fails silently if:
        - Credentials are not set in the host environment
        - Docker is not installed in the guest
        - The guest is a Windows or Android environment
        - The login command fails for any reason
        """
        username = os.environ.get("DOCKERHUB_USERNAME", "")
        token = os.environ.get("DOCKERHUB_TOKEN", "")
        if not username or not token:
            return
        # Skip for non-Linux guests (Windows/Android don't use Docker-in-Docker)
        if self._platform_family() in ("windows", "android"):
            return
        try:
            self._runner.exec(
                f'echo "{token}" | docker login -u "{username}" --password-stdin 2>/dev/null',
                timeout=30,
            )
            logger.debug("DockerHub authentication successful in guest")
        except Exception:
            # Docker not installed in guest, or login failed — continue silently
            pass

    def _capture_observation(self) -> Dict[str, Any]:
        # Capture screen and audio per configured observation specs
        obs: Dict[str, Any] = {}
        screen_spec = next((o for o in self.env_spec.observation if o.type == "rgb_screen"), None)
        if screen_spec and self._episode_dir:
            frame_path = self._episode_dir / f"frame_{self._step_idx:05d}.png"
            try:
                if self._runner.capture_screenshot(frame_path):
                    # breakpoint()
                    item: Dict[str, Any] = {"path": str(frame_path)}
                    if screen_spec.resolution:
                        item["resolution"] = list(screen_spec.resolution)
                    if screen_spec.inline:
                        with open(frame_path, "rb") as fh:
                            item["png_b64"] = base64.b64encode(fh.read()).decode("ascii")
                    obs["screen"] = item
            except Exception:
                pass
        audio_spec = next((o for o in self.env_spec.observation if o.type == "audio_waveform"), None)
        if audio_spec:
            dur_ms = audio_spec.chunk_duration_ms or 200
            try:
                raw = self._runner.capture_audio_raw(
                    dur_ms / 1000.0, audio_spec.sample_rate or 16000, audio_spec.channels or 1
                )
                if raw:
                    obs["audio"] = {
                        "rate": audio_spec.sample_rate or 16000,
                        "channels": audio_spec.channels or 1,
                        "num_samples": len(raw) // 2,
                        "s16le_b64": base64.b64encode(raw).decode("ascii"),
                    }
            except Exception:
                pass
        # UI tree (textual) if requested
        ui_spec = next((o for o in self.env_spec.observation if o.type == "ui_tree"), None)
        if ui_spec:
            try:
                ui_text = self._runner.capture_ui_tree()
                if ui_text:
                    obs["ui_tree"] = {"text": ui_text}
            except Exception:
                pass
        if not obs:
            obs = self._runner.capture_observation()
        return obs

    # State management
    def save_state(self, host_snapshot_path: Optional[os.PathLike] = None) -> Optional[Path]:
        if self.env_spec.supports_save_restore in ("snapshot", "custom"):
            c_tar = self._runner.save_state(self.env_spec.save_paths)
            if host_snapshot_path:
                host_snapshot_path = Path(host_snapshot_path)
            else:
                host_snapshot_path = (self._episode_dir or Path(".")) / "snapshot.tar"
            self._runner.copy_from(c_tar, str(host_snapshot_path))
            return host_snapshot_path
        return None

    def load_state(self, host_snapshot_path: os.PathLike) -> None:
        c_path = self._runner.put_file(str(host_snapshot_path))
        self._runner.load_state(c_path)

    # Roots for resolving verifier paths
    def set_roots(self, env_root: Optional[os.PathLike], task_root: Optional[os.PathLike]) -> None:
        self._env_root = Path(env_root) if env_root else None
        self._task_root = Path(task_root) if task_root else None

    # Controls & helpers (M4)
    def pause_recording(self) -> None:
        if self._recorder and self._rec_handle:
            try:
                self._recorder.stop(self._rec_handle)
            except Exception:
                pass
            self._rec_handle = None

    def resume_recording(self) -> None:
        if self._recorder and not self._rec_handle and self._episode_dir:
            self._rec_handle = self._recorder.start(
                out_dir=self._episode_dir,
                fps=self.env_spec.recording.video_fps,
                resolution=self.env_spec.recording.video_resolution,
                vcodec=self.env_spec.recording.video_codec,
                vcrf=self.env_spec.recording.video_crf,
                ar=self.env_spec.recording.audio_rate,
                ac=self.env_spec.recording.audio_channels,
                acodec=self.env_spec.recording.audio_codec,
            )

    def copy_to_env(self, host_src: str, container_dst: str) -> None:
        self._runner.copy_to(host_src, container_dst)

    def copy_from_env(self, container_src: str, host_dst: str) -> None:
        self._runner.copy_from(container_src, host_dst)
