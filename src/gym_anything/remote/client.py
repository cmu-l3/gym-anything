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
import os
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

import requests

from gym_anything.contracts import SessionInfo
from gym_anything.specs import EnvSpec, TaskSpec
from gym_anything.utils.yaml import load_structured_file


class RemoteGymEnv:
    """Remote environment client that mirrors GymAnythingEnv interface.
    
    This class provides a transparent wrapper around a remote Gym-Anything
    environment. All method calls are forwarded to the remote server via HTTP,
    and the interface is identical to GymAnythingEnv.
    """
    
    def __init__(self, remote_url: str, env_spec: Optional[Union[EnvSpec, Dict[str, Any]]] = None,
                 task_spec: Optional[Union[TaskSpec, Dict[str, Any]]] = None,
                 env_dir: Optional[str] = None, task_id: Optional[str] = None,
                 timeout: int = 300, worker_reset_policy: Optional[str] = "core"):
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
        """
        self.remote_url = remote_url.rstrip('/')
        self.timeout = timeout
        self.env_id: Optional[str] = None
        self._episode_dir: Optional[Path] = None
        self._cache_dir: Optional[Path] = None
        self._session_info: Optional[SessionInfo] = None
        self._closed = False
        self.worker_reset_policy = worker_reset_policy
        
        # Store specs for reference
        self.env_spec = env_spec
        self.task_spec = task_spec
        
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
        
        # Send request
        response = requests.post(
            f"{self.remote_url}/envs/create",
            json=data,
            timeout=self.timeout
        )
        response.raise_for_status()
        
        result = response.json()
        self.env_id = result["env_id"]
        
    def _request(self, method: str, endpoint: str, **kwargs) -> requests.Response:
        """Make HTTP request to remote server with error handling."""
        if self._closed:
            raise RuntimeError("Environment has been closed")
        
        url = f"{self.remote_url}{endpoint}"
        
        # Add default timeout if not specified
        if 'timeout' not in kwargs:
            kwargs['timeout'] = self.timeout
        
        try:
            response = requests.request(method, url, **kwargs)
            response.raise_for_status()
            return response
        except requests.exceptions.RequestException as e:
            raise RuntimeError(f"Remote request failed: {e}") from e
    
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
    
    def step(self, actions: List[Dict[str, Any]], wait_between_actions: float = 0.2,
             mark_done: bool = False) -> Tuple[Dict[str, Any], float, bool, Dict[str, Any]]:
        """Execute actions in the environment.
        
        Args:
            actions: List of action dictionaries
            wait_between_actions: Wait time between actions in seconds
            mark_done: Whether to mark episode as done
            
        Returns:
            Tuple of (observation, reward, done, info)
        """
        response = self._request(
            "POST",
            f"/envs/{self.env_id}/step",
            json={
                "actions": actions,
                "wait_between_actions": wait_between_actions,
                "mark_done": mark_done
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
        task_spec = self.task_spec
        if task_spec is None:
            return None
        return getattr(getattr(task_spec, "init", None), "max_steps", None)

    @property
    def timeout_sec(self) -> Optional[int]:
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
                    worker_reset_policy: Optional[str] = "core") -> RemoteGymEnv:
        """Create remote environment from config directory.
        
        This mirrors the gym_anything.api.from_config() interface.
        
        Args:
            remote_url: URL of remote server
            env_dir: Path to environment directory
            task_id: Optional task ID
            timeout: Request timeout in seconds
            worker_reset_policy: Worker-local post-reset policy
            
        Returns:
            RemoteGymEnv instance
        """
        return cls(
            remote_url=remote_url,
            env_dir=str(env_dir),
            task_id=task_id,
            timeout=timeout,
            worker_reset_policy=worker_reset_policy,
        )
    
    @classmethod
    def make(cls, remote_url: str, env: Union[str, os.PathLike, Dict[str, Any], EnvSpec],
             task: Optional[Union[str, os.PathLike, Dict[str, Any], TaskSpec]] = None,
             timeout: int = 300, worker_reset_policy: Optional[str] = "core") -> RemoteGymEnv:
        """Create remote environment from spec.
        
        This mirrors the gym_anything.api.make() interface.
        
        Args:
            remote_url: URL of remote server
            env: Environment spec (path, dict, or EnvSpec)
            task: Task spec (path, dict, or TaskSpec)
            timeout: Request timeout in seconds
            worker_reset_policy: Worker-local post-reset policy
            
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
