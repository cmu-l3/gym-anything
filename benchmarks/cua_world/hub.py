"""CUA-World tasks as dataset rows for training-stack adapters.

Produces the row shape consumed by `gym_anything.integrations.verifiers`
(`prompt` / `info` / `task`). Plain data only: no third-party dependencies,
so the module is importable wherever the benchmark package is.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Union

from .registry import get_tasks_for_environment, resolve_environment_dir


def build_task_rows(
    env_names: Union[str, List[str]],
    split: str = "all",
    surface: str = "raw",
    task_ids: Optional[List[str]] = None,
    max_examples: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """Build dataset rows for the given benchmark environments.

    Args:
        env_names: benchmark environment name(s), e.g. "gimp_env" or
            ["gimp_env", "libreoffice_calc_env"].
        split: task split ("all", "train", "test", or a named split).
        surface: "raw" or "verified".
        task_ids: optional whitelist of task ids.
        max_examples: cap on rows.

    Each row carries the task's natural-language prompt and an `info` dict
    with an absolute `env_dir`, so consumers never depend on the working
    directory.
    """
    if isinstance(env_names, str):
        env_names = [env_names]

    rows: List[Dict[str, Any]] = []
    for env_name in env_names:
        env_dir = Path(resolve_environment_dir(env_name)).resolve()
        tasks = get_tasks_for_environment(env_name, split=split, surface=surface)
        for task_id in sorted(tasks):
            if task_ids and task_id not in task_ids:
                continue
            task_json_path = env_dir / "tasks" / task_id / "task.json"
            if not task_json_path.exists():
                continue
            task = json.loads(task_json_path.read_text())
            nl = task.get("natural_language")
            desc = (
                (nl.get("prompt") if isinstance(nl, dict) else nl)
                or task.get("description")
                or ""
            )
            if not desc:
                continue
            rows.append(
                {
                    "prompt": [{"role": "user", "content": desc}],
                    "info": {
                        "env_dir": str(env_dir),
                        "env_name": env_name,
                        "task_id": task_id,
                        "seed": 0,
                    },
                    "task": f"{env_name}/{task_id}",
                }
            )
    if not rows:
        raise ValueError(
            f"No tasks found for env_names={env_names} split={split!r} "
            f"surface={surface!r} task_ids={task_ids}"
        )
    if max_examples is not None:
        rows = rows[:max_examples]
    return rows
