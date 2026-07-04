"""Compile gym-anything benchmark tasks into Harbor task directories.

A compiled task has the standard Harbor shape::

    <out>/<env_name>__<task_id>/
    ├── instruction.md                    # task.json description
    ├── task.toml                         # Harbor TaskConfig (schema 1.3)
    ├── environment/gym-anything.json     # boot config for GymAnythingEnvironment
    └── tests/test.sh                     # contract marker (see below)

The tasks are runnable only on the gym-anything backend
(``harbor run ... --env gym_anything.integrations.harbor:GymAnythingEnvironment``).
That environment intercepts the Verifier's ``test.sh`` invocation and runs the
task's real grading pipeline (post_task hook + verifier.py) on the host, so
``tests/test.sh`` is a marker that fails loudly if the task is executed on an
environment type that cannot grade it.

This module deliberately imports neither ``harbor`` nor anything heavier than
the gym-anything registry, so compilation (and its tests) run everywhere.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from ..registry import get_tasks_for_environment, resolve_environment_dir

_TEST_SH = """#!/bin/bash
# Contract marker for gym-anything Harbor tasks.
#
# When this task runs on the gym-anything Harbor backend
# (--env gym_anything.integrations.harbor:GymAnythingEnvironment), the backend
# intercepts this script's invocation and runs the task's real grading
# pipeline (post_task export hook + verifier.py) on the host, writing
# /logs/verifier/reward.json itself. This script only executes if the task was
# started on an environment type that cannot grade it.
echo "cua-world tasks must run on the gym-anything Harbor backend:" >&2
echo "  --env gym_anything.integrations.harbor:GymAnythingEnvironment" >&2
exit 1
"""

_DEFAULT_KEYWORDS = ["computer-use", "gui", "gym-anything"]


def _toml_string(value: str) -> str:
    # JSON string escaping is a valid TOML basic string for the fields we emit.
    return json.dumps(value)


def _render_task_toml(
    *,
    name: str,
    description: str,
    keywords: List[str],
    build_timeout_sec: int,
    agent_timeout_sec: int,
    verifier_timeout_sec: int,
    metadata: Dict[str, Any],
) -> str:
    keyword_list = ", ".join(_toml_string(k) for k in keywords)
    metadata_lines = "\n".join(
        f"{key} = {_toml_string(str(value))}" for key, value in metadata.items()
    )
    return f"""schema_version = "1.3"

[task]
name = {_toml_string(name)}
description = {_toml_string(description)}
keywords = [{keyword_list}]

[environment]
build_timeout_sec = {build_timeout_sec}

[agent]
timeout_sec = {agent_timeout_sec}

[verifier]
timeout_sec = {verifier_timeout_sec}

[metadata.gym_anything]
{metadata_lines}
"""


def compile_task(
    env_name: str,
    task_id: str,
    out_root: Path | str,
    *,
    benchmark: str = "cua_world",
    org: str = "cua-world",
    env_dir: Optional[Path | str] = None,
    cache_level: str = "post_start",
    use_cache: bool = True,
    runner: Optional[str] = None,
    seed: int = 0,
    build_timeout_sec: int = 3600,
    agent_timeout_sec: int = 1800,
    verifier_timeout_sec: int = 1800,
) -> Path:
    """Compile one benchmark task into a Harbor task directory.

    ``build_timeout_sec`` defaults high because the first boot of an
    environment provisions it; later boots load from checkpoint.
    """
    resolved_env_dir = (
        Path(env_dir) if env_dir else resolve_environment_dir(env_name, benchmark)
    )
    task_dir = resolved_env_dir / "tasks" / task_id
    task_json_path = task_dir / "task.json"
    task_json = json.loads(task_json_path.read_text())
    description = str(task_json.get("description") or "").strip()
    if not description:
        raise ValueError(f"Task {env_name}/{task_id} has no description in {task_json_path}")

    slug = f"{env_name}__{task_id}"
    out_dir = Path(out_root) / slug
    (out_dir / "environment").mkdir(parents=True, exist_ok=True)
    (out_dir / "tests").mkdir(exist_ok=True)

    (out_dir / "instruction.md").write_text(description + "\n")

    ga_config: Dict[str, Any] = {
        "benchmark": benchmark,
        "env_name": env_name,
        "task_id": task_id,
        "cache_level": cache_level,
        "use_cache": use_cache,
        "seed": seed,
    }
    if runner:
        ga_config["runner"] = runner
    (out_dir / "environment" / "gym-anything.json").write_text(
        json.dumps(ga_config, indent=2) + "\n"
    )

    test_path = out_dir / "tests" / "test.sh"
    test_path.write_text(_TEST_SH)
    test_path.chmod(0o755)

    (out_dir / "task.toml").write_text(
        _render_task_toml(
            name=f"{org}/{slug}",
            description=description,
            keywords=_DEFAULT_KEYWORDS,
            build_timeout_sec=build_timeout_sec,
            agent_timeout_sec=agent_timeout_sec,
            verifier_timeout_sec=verifier_timeout_sec,
            metadata={
                "benchmark": benchmark,
                "env_name": env_name,
                "task_id": task_id,
            },
        )
    )
    return out_dir


def compile_environment(
    env_name: str,
    out_root: Path | str,
    *,
    benchmark: str = "cua_world",
    task_ids: Optional[List[str]] = None,
    split: str = "all",
    **task_kwargs: Any,
) -> List[Path]:
    """Compile every task of a benchmark environment (or a named split)."""
    ids = task_ids or get_tasks_for_environment(env_name, benchmark, split=split)
    return [
        compile_task(env_name, task_id, out_root, benchmark=benchmark, **task_kwargs)
        for task_id in ids
    ]


__all__ = ["compile_task", "compile_environment"]
