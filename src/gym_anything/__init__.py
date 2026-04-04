"""gym_anything package public API.

This package provides a unified interface to wrap arbitrary software as a
Gym-like environment with consistent observation/action modalities and
recording. See `make` and `from_config` to construct environments.
"""

from .api import make, from_config
from .compatibility import get_runner_compatibility, get_runner_compatibility_matrix
from .contracts import PlatformFamily, RunnerRuntimeInfo, SessionInfo
from .specs import EnvSpec, TaskSpec
from .env import GymAnythingEnv
from .remote import RemoteGymEnv
from .vlm import query_vlm

__all__ = [
    "make",
    "from_config",
    "get_runner_compatibility",
    "get_runner_compatibility_matrix",
    "PlatformFamily",
    "RunnerRuntimeInfo",
    "SessionInfo",
    "EnvSpec",
    "TaskSpec",
    "GymAnythingEnv",
    "RemoteGymEnv",
    "query_vlm",
]
