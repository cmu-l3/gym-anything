from __future__ import annotations

import abc
from typing import Any, Dict, Optional

from ...contracts import PlatformFamily, RunnerRuntimeInfo
from ...specs import EnvSpec


class BaseRunner(abc.ABC):
    """Abstract runtime runner interface.

    Implementations (e.g., DockerRunner) are responsible for starting/stopping the
    environment, injecting actions (mouse/keyboard/voice/api_call), and capturing
    observations for configured modalities.
    """

    def __init__(self, spec: EnvSpec):
        self.spec = spec
        self._reporter = None
        self._fast_io = False

    def set_reporter(self, reporter) -> None:
        self._reporter = reporter

    def _report_start(self, key: str, detail: str = "") -> None:
        if self._reporter:
            self._reporter.stage_start(key, detail)

    def _report_done(self, key: str, detail: str = "") -> None:
        if self._reporter:
            self._reporter.stage_done(key, detail)

    def _report_update(self, key: str, detail: str) -> None:
        if self._reporter:
            self._reporter.stage_update(key, detail)

    def _report_skip(self, key: str, reason: str = "") -> None:
        if self._reporter:
            self._reporter.stage_skip(key, reason)

    def _report_fail(self, key: str, error: str) -> None:
        if self._reporter:
            self._reporter.stage_fail(key, error)

    def _report_log(self, message: str) -> None:
        if self._reporter:
            self._reporter.log(message)

    @abc.abstractmethod
    def start(self, seed: Optional[int] = None) -> None:
        ...

    @abc.abstractmethod
    def stop(self) -> None:
        ...

    @abc.abstractmethod
    def run_reset(self, reset_script: str, seed: Optional[int] = None) -> None:
        ...

    @abc.abstractmethod
    def run_task_init(self, init_script: str) -> None:
        ...

    @abc.abstractmethod
    def inject_action(self, action: Dict[str, Any]) -> None:
        ...

    @abc.abstractmethod
    def capture_observation(self) -> Dict[str, Any]:
        ...

    # --- class-level facts (queried by doctor/CLI; never centrally tabled) ---

    @classmethod
    def doctor_status(cls) -> Dict[str, Any]:
        """Host availability for this runner: {"available", "reason", "deps"}.

        Default is optimistic with an honest reason; runners with real host
        dependencies override this so doctor and worker preflight can probe
        them.
        """
        return {
            "available": True,
            "reason": "no doctor probe declared by this runner",
            "deps": {},
        }

    @classmethod
    def cache_components(cls) -> list:
        """Rows for `gym-anything cache`: {"name","category","paths","desc"}."""
        return []

    @classmethod
    def install_plan(cls):
        """An installers.InstallPlan for this runner's host deps, or None."""
        return None

    @classmethod
    def validate_options(cls, spec: EnvSpec) -> list:
        """Validate spec.runner_options; return a list of error strings.

        Called after runner selection, before anything starts, so a typo in
        runner-specific configuration fails at spec load rather than at
        world boot. The default accepts anything.
        """
        return []

    # --- episode participation ---

    def on_episode_start(self, context: Dict[str, Any]) -> None:
        """Receive the episode context (episode_dir, env_id, task_id, seed).

        Called at the start of every reset, before the world starts. Default
        no-op; worlds that persist artifacts or key state per-episode use
        this instead of guessing paths.
        """

    def supports_time_control(self) -> bool:
        """True when this world owns time: `wait` control actions are
        forwarded to inject_action instead of sleeping host wall-clock."""
        return False

    def supports_live_recording(self) -> bool:
        return False

    def supports_checkpoint_caching(self) -> bool:
        return False

    def supports_savevm(self) -> bool:
        return False

    def supports_fast_io(self) -> bool:
        return False

    def acks_input_delivery(self) -> bool:
        """True when inject_action returns only after the guest has actually
        received the input. Callers that would otherwise pace actions with a
        sleep can drop it; a runner that fires and forgets must keep it."""
        return False

    def set_fast_io(self, enabled: bool) -> None:
        self._fast_io = bool(enabled)

    def default_exec_env(self) -> Dict[str, str]:
        return dict(getattr(self.spec.security, "resolved_env", {}) or {})

    def merge_exec_env(self, env: Optional[Dict[str, str]] = None) -> Dict[str, str]:
        merged = self.default_exec_env()
        if env:
            merged.update(env)
        return merged

    def get_platform_family(self) -> PlatformFamily:
        os_type = getattr(self.spec, "os_type", None)
        if os_type in {"linux", "windows", "android", "macos"}:
            return os_type
        if getattr(self, "is_android", False):
            return "android"
        if getattr(self, "is_windows", False):
            return "windows"
        if getattr(self, "is_macos", False):
            return "macos"
        return "linux"

    def get_runtime_info(self) -> RunnerRuntimeInfo:
        vnc_port = (
            getattr(self, "vnc_port", None)
            or getattr(self, "vnc_host_port", None)
            or getattr(self, "_vnc_port", None)
        )
        vnc_password = (
            getattr(self, "vnc_password", None)
            or getattr(self, "_vnc_password", None)
            or getattr(getattr(self.spec, "vnc", None), "password", None)
        )
        return RunnerRuntimeInfo(
            platform_family=self.get_platform_family(),
            container_name=getattr(self, "container_name", None),
            instance_name=getattr(self, "instance_name", None),
            vnc_port=vnc_port,
            vnc_password=vnc_password,
            vnc_url=getattr(self, "vnc_url", None),
            ssh_port=getattr(self, "ssh_port", None),
            ssh_user=getattr(self, "_ssh_user", None),
            ssh_password=getattr(self, "_ssh_password", None),
        )

    # Optional utility for recorders to execute commands inside the runtime
    def exec(self, cmd: str, env: Optional[Dict[str, str]] = None, user: Optional[str] = None, use_pty: bool = True, timeout: int = 600) -> int:
        raise NotImplementedError

    # Path mapping (host -> runtime). For DockerRunner, maps to bind-mount path.
    def to_container_path(self, host_path):
        return host_path

    # Optional: asynchronous exec helper used by recorders/streamers
    def exec_async(self, cmd: str, env: Optional[Dict[str, str]] = None, stdout=None, stderr=None):
        raise NotImplementedError

    # Optional: copy a file into the runtime and return its container path
    def put_file(self, host_path) -> str:
        raise NotImplementedError

    # Optional: capture stdout/stderr of a command run inside the runtime
    def exec_capture(self, cmd: str) -> str:
        raise NotImplementedError

    # Optional: binary capture
    def exec_capture_bytes(self, cmd: str) -> bytes:
        raise NotImplementedError

    # Optional: capture a single screenshot PNG into a host path
    def capture_screenshot(self, host_path) -> bool:
        raise NotImplementedError

    # Optional: capture a screenshot as an in-process Python image object.
    def capture_screenshot_image(self):
        raise NotImplementedError

    # Optional: capture short audio chunk as raw s16le bytes
    def capture_audio_raw(self, duration_sec: float, rate: int, channels: int) -> bytes:
        raise NotImplementedError

    # Optional: copy host file to container and back
    def copy_to(self, host_src: str, container_dst: str) -> None:
        raise NotImplementedError

    def copy_from(self, container_src: str, host_dst: str) -> None:
        raise NotImplementedError

    # Optional: UI tree capture
    def capture_ui_tree(self) -> str:
        return ""

    # Optional: save/restore snapshot
    def save_state(self, save_paths: Optional[list[str]]) -> str:
        raise NotImplementedError

    def load_state(self, snapshot_container_path: str) -> None:
        raise NotImplementedError

    # Optional: checkpoint support
    def set_checkpoint_key(self, cache_level: str, task_id: Optional[str] = None, use_savevm: bool = False) -> None:
        """Set the runner-specific checkpoint key for caching."""
        pass

    def checkpoint_exists(self) -> bool:
        """Check whether the configured checkpoint exists."""
        return False

    def create_checkpoint(self) -> bool:
        """Create the configured checkpoint."""
        return False

    def start_from_checkpoint(self, seed: Optional[int] = None) -> bool:
        """Start from the configured checkpoint."""
        return False
