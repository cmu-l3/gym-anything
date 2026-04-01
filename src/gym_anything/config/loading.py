from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Dict, Optional, Union

from ..env import GymAnythingEnv
from ..security import load_secret_env
from ..specs import EnvSpec, TaskSpec
from ..utils.merge import deep_merge_env_dict
from ..utils.yaml import load_structured_file
from .presets import load_preset_env_dict
from .validators import validate_env_spec, validate_task_spec


def _resolve_security_runtime(spec: EnvSpec, *, base_dir: Optional[Path] = None) -> EnvSpec:
    if spec.security.secrets_ref:
        spec.security.resolved_env = load_secret_env(spec.security.secrets_ref, base_dir=base_dir)
    return spec


def _load_envspec(path_or_obj: Union[str, os.PathLike, Dict[str, Any], EnvSpec]) -> EnvSpec:
    if isinstance(path_or_obj, EnvSpec):
        return _resolve_security_runtime(path_or_obj)
    if isinstance(path_or_obj, (str, os.PathLike)):
        path = Path(path_or_obj)
        data = load_structured_file(path)
        # Compose with base preset if provided
        if isinstance(data, dict) and data.get("base"):
            base = load_preset_env_dict(data["base"])  # raises if unknown
            data = deep_merge_env_dict(base, data)
        return _resolve_security_runtime(EnvSpec.from_dict(data), base_dir=path.parent)
    if isinstance(path_or_obj, dict):
        d = path_or_obj
        if d.get("base"):
            base = load_preset_env_dict(d["base"])  # raises if unknown
            d = deep_merge_env_dict(base, d)
        return _resolve_security_runtime(EnvSpec.from_dict(d))
    raise TypeError("Unsupported env spec input; expected path, dict, or EnvSpec", path_or_obj)


def _load_taskspec(path_or_obj: Optional[Union[str, os.PathLike, Dict[str, Any], TaskSpec]]) -> Optional[TaskSpec]:
    if path_or_obj is None:
        return None
    if isinstance(path_or_obj, TaskSpec):
        return path_or_obj
    if isinstance(path_or_obj, (str, os.PathLike)):
        data = load_structured_file(Path(path_or_obj))
        return TaskSpec.from_dict(data)
    if isinstance(path_or_obj, dict):
        return TaskSpec.from_dict(path_or_obj)
    raise TypeError("Unsupported task spec input; expected path, dict, or TaskSpec")


def make(
    env: Union[str, os.PathLike, Dict[str, Any], EnvSpec],
    task: Optional[Union[str, os.PathLike, Dict[str, Any], TaskSpec]] = None,
    overrides: Optional[Dict[str, Any]] = None,
) -> GymAnythingEnv:
    """Create an environment instance from spec.

    - `env`: EnvSpec as dict/path/instance.
    - `task`: TaskSpec as dict/path/instance (optional).
    - `overrides`: shallow overrides applied to EnvSpec at runtime (e.g. toggling net).
    """
    env_spec = _load_envspec(env)
    if overrides:
        env_spec = env_spec.merge_overrides(overrides)

    task_spec = _load_taskspec(task)

    validate_env_spec(env_spec)
    if task_spec is not None:
        validate_task_spec(task_spec)

    return GymAnythingEnv(env_spec=env_spec, task_spec=task_spec)


def from_config(
    env_dir: Union[str, os.PathLike],
    task_id: Optional[str] = None,
) -> GymAnythingEnv:
    """Load `env.yaml|yml|json` (and optional `tasks/<task_id>/task.yaml|yml|json`) from a folder.

    If `task_id` is omitted and there is exactly one task folder, that task is used.
    """
    env_dir = Path(env_dir)
    env_spec_path: Optional[Path] = None
    for candidate in (env_dir / "env.yaml", env_dir / "env.yml", env_dir / "env.json"):
        if candidate.exists():
            env_spec_path = candidate
            break
    if env_spec_path is None:
        raise FileNotFoundError(f"No env.yaml, env.yml, or env.json found in {env_dir}")

    # Resolve task file
    task_spec_path: Optional[Path] = None
    if task_id:
        for candidate in (
            env_dir / "tasks" / task_id / "task.yaml",
            env_dir / "tasks" / task_id / "task.yml",
            env_dir / "tasks" / task_id / "task.json",
        ):
            if candidate.exists():
                task_spec_path = candidate
                break
        if task_spec_path is None:
            raise FileNotFoundError(f"Task '{task_id}' not found under {env_dir}/tasks")
    else:
        tasks_dir = env_dir / "tasks"
        if tasks_dir.exists() and tasks_dir.is_dir():
            candidates = [p for p in tasks_dir.glob("*/task.*") if p.suffix in (".yaml", ".yml", ".json")]
            if len(candidates) == 1:
                task_spec_path = candidates[0]

    env = make(env_spec_path, task_spec_path)
    # Attach roots for verifiers and assets resolution
    env.set_roots(env_root=env_dir, task_root=(task_spec_path.parent if task_spec_path else None))
    return env
