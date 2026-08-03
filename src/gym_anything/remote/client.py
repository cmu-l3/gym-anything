"""
Remote Gym-Anything Environment Client

A transparent wrapper for GymAnythingEnv that executes on a remote server.
Provides the same interface as GymAnythingEnv but communicates via HTTP.

Usage:
    # Instead of:
    from gym_anything import from_config
    env = from_config(env_dir, task_id)
    
    # Use:
    from gym_anything.remote import RemoteGymEnv
    env = RemoteGymEnv.from_config(
        remote_url="http://remote-server:5000",
        env_dir=env_dir,
        task_id=task_id
    )
    
    # All other code remains unchanged!
"""

from __future__ import annotations

import json
import logging
import os
import random
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

import requests

logger = logging.getLogger(__name__)

# Transient failure retry policy. Tuned for a flaky master/worker link (5xx
# from the master when no healthy worker is momentarily available, dropped
# connections, idle-timeout reads on long resets, etc.). 4xx and other
# requests.exceptions are not retried.
_RETRYABLE_STATUSES = frozenset({500, 502, 503, 504})
_DEFAULT_RETRY_ATTEMPTS = int(os.environ.get("GYM_ANYTHING_REMOTE_RETRY_ATTEMPTS", "5"))
_DEFAULT_RETRY_BASE_SEC = float(os.environ.get("GYM_ANYTHING_REMOTE_RETRY_BASE_SEC", "1.0"))
_DEFAULT_RETRY_MAX_SEC = float(os.environ.get("GYM_ANYTHING_REMOTE_RETRY_MAX_SEC", "30.0"))

from gym_anything.contracts import SessionInfo
from gym_anything.config.loading import _load_envspec, _load_taskspec
from gym_anything.specs import EnvSpec, TaskSpec
from gym_anything.utils.yaml import load_structured_file


_REMOTE_VERIFIER_ENV_KEYS = (
    "GYM_ANYTHING_VERIFIER_MODE",
    "GYM_ANYTHING_VLM_CHECKLIST_MODEL",
    "GYM_ANYTHING_VLM_CHECKLIST_BACKEND",
    "GYM_ANYTHING_VLM_CHECKLIST_BASE_URL",
    "GYM_ANYTHING_VLM_CHECKLIST_API_KEY",
    "GYM_ANYTHING_VLM_CHECKLIST_CHECKLIST",
    "GYM_ANYTHING_VLM_CHECKLIST_CHECKLIST_PATH",
    "GYM_ANYTHING_VLM_CHECKLIST_MAX_RETRIES",
    "GYM_ANYTHING_VLM_CHECKLIST_TEMPERATURE",
    "GYM_ANYTHING_VLM_CHECKLIST_TOP_P",
    "GYM_ANYTHING_VLM_CHECKLIST_MAX_TOKENS",
    "GYM_ANYTHING_VLM_CHECKLIST_MAX_FRAMES",
    "GYM_ANYTHING_VLM_CHECKLIST_FRAME_STRATEGY",
    "GYM_ANYTHING_VLM_CHECKLIST_COMPLETION_THRESHOLD",
    "GYM_ANYTHING_VLM_CHECKLIST_INTEGRITY_THRESHOLD",
    "VLM_BACKEND",
    "VLM_MODEL",
    "VLM_BASE_URL",
    "VLM_API_KEY",
    "VLM_MAX_RETRIES",
    "VLM_TIMEOUT",
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "GEMINI_API_KEY",
)


def _clean_verifier_env(values: Optional[Dict[str, Any]]) -> Dict[str, str]:
    if not isinstance(values, dict):
        return {}
    return {str(key): str(value) for key, value in values.items() if value is not None}


def _capture_verifier_env() -> Dict[str, str]:
    return {
        key: value
        for key in _REMOTE_VERIFIER_ENV_KEYS
        if (value := os.environ.get(key)) not in (None, "")
    }


class RemoteGymEnv:
    """Remote environment client that mirrors GymAnythingEnv interface.
    
    This class provides a transparent wrapper around a remote Gym-Anything
    environment. All method calls are forwarded to the remote server via HTTP,
    and the interface is identical to GymAnythingEnv.
    """
    
    def __init__(self, remote_url: str, env_spec: Optional[Union[EnvSpec, Dict[str, Any]]] = None,
                 task_spec: Optional[Union[TaskSpec, Dict[str, Any]]] = None,
                 env_dir: Optional[str] = None, task_id: Optional[str] = None,
                 timeout: int = 300, worker_reset_policy: Optional[str] = "core",
                 verifier_env: Optional[Dict[str, Any]] = None,
                 fast_io: bool = False):
        """Initialize remote environment client.
        
        Args:
            remote_url: URL of the remote server (e.g., "http://localhost:5000")
            env_spec: Environment specification (dict or EnvSpec object)
            task_spec: Task specification (dict or TaskSpec object)
            env_dir: Path to environment directory (for from_config usage)
            task_id: Task ID (for from_config usage)
            timeout: Request timeout in seconds (default: 300)
            worker_reset_policy: Worker-local post-reset policy. Defaults to
                "core" so remote reset matches local reset behavior.
            verifier_env: Optional per-environment verifier/VLM overrides sent
                to the worker. Defaults to the current process verifier env.
            fast_io: Request runner-native low-latency I/O paths.
        """
        self.remote_url = remote_url.rstrip('/')
        self.timeout = timeout
        self.env_id: Optional[str] = None
        self._episode_dir: Optional[Path] = None
        self._cache_dir: Optional[Path] = None
        self._session_info: Optional[SessionInfo] = None
        self._max_steps_override: Optional[int] = None
        self._timeout_sec_override: Optional[int] = None
        self._closed = False
        self.worker_reset_policy = worker_reset_policy
        self.fast_io = bool(fast_io)
        self.verifier_env = (
            _capture_verifier_env()
            if verifier_env is None
            else _clean_verifier_env(verifier_env)
        )
        
        # Store specs for reference
        self.env_spec = env_spec
        self.task_spec = task_spec
        if env_dir and self.env_spec is None:
            self.env_spec, self.task_spec = self._load_local_config_specs(env_dir, task_id)
        
        # Create environment on remote server
        self._create_remote_environment(env_spec, task_spec, env_dir, task_id)
        
        # Setup local cache
        self._setup_cache()
        
    def _setup_cache(self):
        """Setup local cache directory for downloaded files."""
        cache_root = Path.home() / ".gym_anything_cache"
        cache_root.mkdir(parents=True, exist_ok=True)
        
        self._cache_dir = cache_root / self.env_id
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        
    def _create_remote_environment(self, env_spec, task_spec, env_dir, task_id):
        """Create environment on remote server."""
        # Prepare request data
        data = {}
        
        if env_dir:
            data["env_dir"] = env_dir
            if task_id:
                data["task_id"] = task_id
        else:
            if env_spec:
                if isinstance(env_spec, dict):
                    data["env_spec"] = env_spec
                else:
                    # Convert EnvSpec to dict
                    from dataclasses import asdict
                    data["env_spec"] = asdict(env_spec)
            
            if task_spec:
                if isinstance(task_spec, dict):
                    data["task_spec"] = task_spec
                else:
                    # Convert TaskSpec to dict
                    from dataclasses import asdict
                    data["task_spec"] = asdict(task_spec)

        if self.verifier_env:
            data["verifier_env"] = self.verifier_env
        if self.fast_io:
            data["fast_io"] = True

        # Hint the master at which runner this env needs so it can route to a
        # worker that advertises support. Best-effort: when the spec doesn't
        # set ``runner`` explicitly the master falls back to runner-agnostic
        # routing.
        runner_hint = self._infer_runner_hint()
        if runner_hint:
            data["runner"] = runner_hint

        # Send request (with transient-error retries)
        response = self._http_with_retries(
            "POST",
            f"{self.remote_url}/envs/create",
            json=data,
        )

        result = response.json()
        self.env_id = result["env_id"]

    def _infer_runner_hint(self) -> Optional[str]:
        """Pull an explicit ``runner`` value off the loaded EnvSpec, if any."""
        spec = self.env_spec
        if spec is None:
            return None
        if isinstance(spec, dict):
            value = spec.get("runner")
        else:
            value = getattr(spec, "runner", None)
        if isinstance(value, str) and value:
            return value
        return None

    def _load_local_config_specs(
        self,
        env_dir: Union[str, os.PathLike],
        task_id: Optional[str],
    ) -> Tuple[Optional[EnvSpec], Optional[TaskSpec]]:
        """Best-effort local spec load for client-side metadata."""
        env_dir = Path(env_dir)
        env_spec_path = next(
            (path for path in (env_dir / "env.yaml", env_dir / "env.yml", env_dir / "env.json") if path.exists()),
            None,
        )
        if env_spec_path is None:
            return None, None

        try:
            env_spec = _load_envspec(env_spec_path)
        except Exception:
            env_spec = None

        task_spec = None
        if task_id:
            task_spec_path = next(
                (
                    path
                    for path in (
                        env_dir / "tasks" / task_id / "task.yaml",
                        env_dir / "tasks" / task_id / "task.yml",
                        env_dir / "tasks" / task_id / "task.json",
                    )
                    if path.exists()
                ),
                None,
            )
            if task_spec_path is not None:
                try:
                    task_spec = _load_taskspec(task_spec_path)
                except Exception:
                    task_spec = None

        return env_spec, task_spec
        
    def _http_with_retries(self, method: str, url: str, **kwargs) -> requests.Response:
        """Issue an HTTP request, retrying transient failures with exponential
        backoff + full jitter. Retries on connection errors, timeouts, and
        5xx responses (500/502/503/504). 4xx errors are surfaced immediately.

        Caveat: /envs/create and /envs/<id>/step are not strictly idempotent;
        a retry after a partial success may produce a duplicate side effect.
        That is preferable to losing the whole run on a transient master/worker
        hiccup; tune attempts via GYM_ANYTHING_REMOTE_RETRY_ATTEMPTS=0 to
        disable.
        """
        if 'timeout' not in kwargs:
            kwargs['timeout'] = self.timeout

        attempts = max(1, _DEFAULT_RETRY_ATTEMPTS)
        last_exc: Optional[BaseException] = None
        for attempt in range(1, attempts + 1):
            try:
                response = requests.request(method, url, **kwargs)
                if response.status_code in _RETRYABLE_STATUSES and attempt < attempts:
                    body = (response.text or "")[:200]
                    delay = min(_DEFAULT_RETRY_MAX_SEC,
                                _DEFAULT_RETRY_BASE_SEC * (2 ** (attempt - 1)))
                    delay = random.uniform(0, delay)
                    logger.warning(
                        "remote %s %s -> HTTP %d (attempt %d/%d); retrying in %.1fs: %s",
                        method, url, response.status_code, attempt, attempts, delay, body,
                    )
                    time.sleep(delay)
                    continue
                response.raise_for_status()
                return response
            except (
                requests.exceptions.ConnectionError,
                requests.exceptions.Timeout,
                requests.exceptions.ChunkedEncodingError,
            ) as exc:
                last_exc = exc
                if attempt >= attempts:
                    break
                delay = min(_DEFAULT_RETRY_MAX_SEC,
                            _DEFAULT_RETRY_BASE_SEC * (2 ** (attempt - 1)))
                delay = random.uniform(0, delay)
                logger.warning(
                    "remote %s %s -> %s (attempt %d/%d); retrying in %.1fs",
                    method, url, type(exc).__name__, attempt, attempts, delay,
                )
                time.sleep(delay)
                continue
            except requests.exceptions.HTTPError as exc:
                # 4xx (or 5xx on the final attempt) — do not retry further.
                raise RuntimeError(f"Remote request failed: {exc}") from exc
            except requests.exceptions.RequestException as exc:
                raise RuntimeError(f"Remote request failed: {exc}") from exc

        raise RuntimeError(
            f"Remote request failed after {attempts} attempts: {last_exc}"
        ) from last_exc

    def _request(self, method: str, endpoint: str, **kwargs) -> requests.Response:
        """Make HTTP request to remote server with retries on transient errors."""
        if self._closed:
            raise RuntimeError("Environment has been closed")
        url = f"{self.remote_url}{endpoint}"
        return self._http_with_retries(method, url, **kwargs)
    
    # ========================================================================
    # Main Gym Interface
    # ========================================================================
    
    def reset(
        self,
        seed: Optional[int] = None,
        use_cache: bool = False,
        cache_level: str = "pre_start",
        use_savevm: bool = False,
    ) -> Dict[str, Any]:
        """Reset the environment.
        
        Args:
            seed: Random seed
            use_cache: Whether to use checkpoint caching
            cache_level: Checkpoint level to use when caching is enabled
            use_savevm: Whether to request QEMU savevm/loadvm checkpointing
            
        Returns:
            Observation dict
        """
        response = self._request(
            "POST",
            f"/envs/{self.env_id}/reset",
            json={
                "seed": seed,
                "use_cache": use_cache,
                "cache_level": cache_level,
                "use_savevm": use_savevm,
                "post_reset_policy": self.worker_reset_policy,
            }
        )
        
        result = response.json()
        obs = result["observation"]
        
        # Update episode dir
        self._update_episode_dir()
        self.get_session_info()

        return obs
    
    def step(
        self,
        actions: List[Dict[str, Any]],
        wait_between_actions: float = 0.2,
        mark_done: bool = False,
        *,
        capture_observation: bool = True,
        settle_after_actions: bool = True,
    ) -> Tuple[Dict[str, Any], float, bool, Dict[str, Any]]:
        """Execute actions in the environment.
        
        Args:
            actions: List of action dictionaries
            wait_between_actions: Wait time between actions in seconds
            mark_done: Whether to mark episode as done
            capture_observation: Whether to capture the normal post-action observation
            settle_after_actions: Whether to apply the normal post-action delays
            
        Returns:
            Tuple of (observation, reward, done, info)
        """
        response = self._request(
            "POST",
            f"/envs/{self.env_id}/step",
            json={
                "actions": actions,
                "wait_between_actions": wait_between_actions,
                "mark_done": mark_done,
                "capture_observation": capture_observation,
                "settle_after_actions": settle_after_actions,
            }
        )
        
        result = response.json()
        obs = result["observation"]
        reward = result["reward"]
        done = result["done"]
        info = result["info"]
        
        return obs, reward, done, info
    
    def close(self) -> None:
        """Close the environment and cleanup resources."""
        if self._closed:
            return
        
        try:
            self._request("POST", f"/envs/{self.env_id}/close")
        except Exception:
            pass  # Best effort cleanup
        finally:
            self._closed = True
            self._episode_dir = None
            self._session_info = None
    
    def capture_observation(self) -> Dict[str, Any]:
        """Capture current observation without stepping.
        
        Returns:
            Observation dict
        """
        response = self._request(
            "POST",
            f"/envs/{self.env_id}/capture_observation"
        )
        
        result = response.json()
        return result["observation"]

    def capture_screenshot_image(self):
        """Remote screenshot object capture is not available over JSON."""
        raise NotImplementedError("capture_screenshot_image requires a local GymAnythingEnv")

    def _capture_observation(self) -> Dict[str, Any]:
        """Compatibility shim for older callers using the private method."""
        return self.capture_observation()
    
    # ========================================================================
    # File Management
    # ========================================================================
    
    def fetch_path(self, remote_path: str, local_path: Optional[str] = None) -> str:
        """Fetch a file from the remote environment.
        
        Args:
            remote_path: Path to file on remote server
            local_path: Optional local path to save file. If None, saves to cache.
            
        Returns:
            Local path to downloaded file
        """
        # Determine local save path
        if local_path is None:
            # Save to cache with same relative structure
            remote_path_obj = Path(remote_path)
            local_path = self._cache_dir / remote_path_obj.name
        else:
            local_path = Path(local_path)
        
        # Create parent directory
        local_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Download file
        response = self._request(
            "GET",
            f"/envs/{self.env_id}/fetch_path",
            params={"path": remote_path},
            stream=True
        )
        
        # Save to local file
        with open(local_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        return str(local_path)
    
    def _update_episode_dir(self):
        """Update local episode directory information."""
        try:
            response = self._request("GET", f"/envs/{self.env_id}/episode_dir")
            result = response.json()
            remote_episode_dir = result.get("episode_dir")
            
            if remote_episode_dir:
                # Store remote path for reference
                self._episode_dir = Path(remote_episode_dir)
        except Exception:
            pass  # Non-critical

    @property
    def episode_dir(self) -> Optional[Path]:
        return self._episode_dir

    @property
    def artifacts_dir(self) -> Optional[Path]:
        return self._episode_dir

    @property
    def runner_name(self) -> Optional[str]:
        if self._session_info is None:
            return None
        return self._session_info.runner_name

    @property
    def max_steps(self) -> Optional[int]:
        if self._max_steps_override is not None:
            return self._max_steps_override
        task_spec = self.task_spec
        if task_spec is None:
            return None
        return getattr(getattr(task_spec, "init", None), "max_steps", None)

    @property
    def timeout_sec(self) -> Optional[int]:
        if self._timeout_sec_override is not None:
            return self._timeout_sec_override
        task_spec = self.task_spec
        if task_spec is None:
            return None
        return getattr(getattr(task_spec, "init", None), "timeout_sec", None)

    def get_session_info(self) -> Optional[SessionInfo]:
        """Fetch session metadata from the remote server when available."""
        if not hasattr(self, "_session_info"):
            self._session_info = None
        try:
            response = self._request("GET", f"/envs/{self.env_id}/session_info")
            result = response.json()
            payload = result.get("session")
            if not payload:
                return self._session_info
            self._session_info = SessionInfo.from_dict(payload)
            if self._session_info.artifacts_dir:
                self._episode_dir = Path(self._session_info.artifacts_dir)
        except Exception:
            pass
        return self._session_info
    
    # ========================================================================
    # State Management
    # ========================================================================
    
    def save_state(self, host_snapshot_path: Optional[os.PathLike] = None) -> Optional[Path]:
        """Save environment state to snapshot.
        
        Args:
            host_snapshot_path: Optional path for snapshot file
            
        Returns:
            Path to snapshot file (on remote server)
        """
        response = self._request(
            "POST",
            f"/envs/{self.env_id}/save_state",
            json={"host_snapshot_path": str(host_snapshot_path) if host_snapshot_path else None}
        )
        
        result = response.json()
        snapshot_path = result.get("snapshot_path")
        
        return Path(snapshot_path) if snapshot_path else None
    
    def load_state(self, host_snapshot_path: os.PathLike) -> None:
        """Load environment state from snapshot.
        
        Args:
            host_snapshot_path: Path to snapshot file
        """
        response = self._request(
            "POST",
            f"/envs/{self.env_id}/load_state",
            json={"host_snapshot_path": str(host_snapshot_path)}
        )
        
        result = response.json()
        if result.get("status") != "loaded":
            raise RuntimeError("Failed to load state")

    def set_episode_limits(
        self,
        *,
        max_steps: Optional[int] = None,
        timeout_sec: Optional[int] = None,
    ) -> None:
        """Override active episode limits on the remote environment."""
        self._request(
            "POST",
            f"/envs/{self.env_id}/episode_limits",
            json={"max_steps": max_steps, "timeout_sec": timeout_sec},
        )
        self._max_steps_override = max_steps
        self._timeout_sec_override = timeout_sec
    
    # ========================================================================
    # Recording Controls
    # ========================================================================
    
    def pause_recording(self) -> None:
        """Pause environment recording."""
        self._request("POST", f"/envs/{self.env_id}/pause_recording")
    
    def resume_recording(self) -> None:
        """Resume environment recording."""
        self._request("POST", f"/envs/{self.env_id}/resume_recording")
    
    # ========================================================================
    # File Operations
    # ========================================================================
    
    def copy_to_env(self, host_src: str, container_dst: str) -> None:
        """Copy file to environment.
        
        Note: This is limited for remote execution. The host_src must be
        accessible on the remote server.
        
        Args:
            host_src: Source path (on remote server)
            container_dst: Destination path in container
        """
        response = self._request(
            "POST",
            f"/envs/{self.env_id}/copy_to_env",
            json={"host_src": host_src, "container_dst": container_dst}
        )
        
        result = response.json()
        if result.get("status") != "copied":
            raise RuntimeError("Failed to copy file to environment")
    
    def copy_from_env(self, container_src: str, host_dst: str) -> None:
        """Copy file from environment.
        
        Note: This is limited for remote execution. The host_dst will be
        on the remote server.
        
        Args:
            container_src: Source path in container
            host_dst: Destination path (on remote server)
        """
        response = self._request(
            "POST",
            f"/envs/{self.env_id}/copy_from_env",
            json={"container_src": container_src, "host_dst": host_dst}
        )
        
        result = response.json()
        if result.get("status") != "copied":
            raise RuntimeError("Failed to copy file from environment")
    
    # ========================================================================
    # Compatibility Methods
    # ========================================================================
    
    def set_roots(self, env_root: Optional[os.PathLike], task_root: Optional[os.PathLike]) -> None:
        """Set roots for resolving verifier paths.
        
        Note: This is a no-op for remote environments as roots are set on the server.
        """
        pass  # No-op for remote environments
    
    # ========================================================================
    # Class Methods
    # ========================================================================
    
    @classmethod
    def from_config(cls, remote_url: str, env_dir: Union[str, os.PathLike],
                    task_id: Optional[str] = None, timeout: int = 300,
                    worker_reset_policy: Optional[str] = "core",
                    verifier_env: Optional[Dict[str, Any]] = None,
                    fast_io: bool = False) -> RemoteGymEnv:
        """Create remote environment from config directory.
        
        This mirrors the gym_anything.api.from_config() interface.
        
        Args:
            remote_url: URL of remote server
            env_dir: Path to environment directory
            task_id: Optional task ID
            timeout: Request timeout in seconds
            worker_reset_policy: Worker-local post-reset policy
            verifier_env: Optional per-environment verifier/VLM overrides
            fast_io: Request runner-native low-latency I/O paths.
            
        Returns:
            RemoteGymEnv instance
        """
        return cls(
            remote_url=remote_url,
            env_dir=str(env_dir),
            task_id=task_id,
            timeout=timeout,
            worker_reset_policy=worker_reset_policy,
            verifier_env=verifier_env,
            fast_io=fast_io,
        )
    
    @classmethod
    def make(cls, remote_url: str, env: Union[str, os.PathLike, Dict[str, Any], EnvSpec],
             task: Optional[Union[str, os.PathLike, Dict[str, Any], TaskSpec]] = None,
             timeout: int = 300, worker_reset_policy: Optional[str] = "core",
             verifier_env: Optional[Dict[str, Any]] = None,
             fast_io: bool = False) -> RemoteGymEnv:
        """Create remote environment from spec.
        
        This mirrors the gym_anything.api.make() interface.
        
        Args:
            remote_url: URL of remote server
            env: Environment spec (path, dict, or EnvSpec)
            task: Task spec (path, dict, or TaskSpec)
            timeout: Request timeout in seconds
            worker_reset_policy: Worker-local post-reset policy
            verifier_env: Optional per-environment verifier/VLM overrides
            fast_io: Request runner-native low-latency I/O paths.
            
        Returns:
            RemoteGymEnv instance
        """
        # Load specs if they are paths
        env_spec = env
        if isinstance(env, (str, os.PathLike)):
            env_spec = load_structured_file(Path(env))
        
        task_spec = task
        if isinstance(task, (str, os.PathLike)):
            task_spec = load_structured_file(Path(task))
        
        return cls(
            remote_url=remote_url,
            env_spec=env_spec,
            task_spec=task_spec,
            timeout=timeout,
            worker_reset_policy=worker_reset_policy,
            verifier_env=verifier_env,
            fast_io=fast_io,
        )
    
    def __repr__(self) -> str:
        return f"RemoteGymEnv(env_id={self.env_id}, remote_url={self.remote_url})"
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.close()
        return False
