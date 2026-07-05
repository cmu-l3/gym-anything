"""Compile gym-anything benchmark tasks into Harbor task directories.

A compiled task has the standard Harbor shape::

    <out>/<env_name>__<task_id>/
    ├── instruction.md                    # task.json description
    ├── task.toml                         # Harbor TaskConfig (schema 1.3)
    ├── environment/
    │   ├── Dockerfile                    # generic runtime (QEMU-in-container)
    │   ├── docker-compose.yaml           # KVM passthrough + image cache volume
    │   └── gym-anything.json             # task identity / boot config
    └── tests/test.sh                     # grades via the in-container runtime

The tasks run two ways from the same directory:

* **Standard Harbor path** (any docker-capable backend with KVM): the
  Dockerfile boots the task's guest via QEMU inside the container (the
  ModalRunner sandbox shape, see ``container``), and ``tests/test.sh``
  runs the task's real grading pipeline in the container. Requires the shared
  image-cache volume once per host: ``docker volume create
  harbor-gym-anything-cache`` (the OSWorld adapter uses the same pattern).
* **gym-anything backend fast path** (``--env
  gym_anything.integrations.harbor:GymAnythingEnvironment``): the backend
  boots the guest directly through the local runner stack, ignores the
  Dockerfile, and intercepts the verifier invocation to grade host-side.

This module deliberately imports neither ``harbor`` nor anything heavier than
the gym-anything registry, so compilation (and its tests) run everywhere.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from ...registry import get_tasks_for_environment, resolve_environment_dir

_UNSET: Dict[str, Any] = {"__unset__": True}

_TEST_SH = """#!/bin/bash
# Grades the episode via the in-container gym-anything runtime: runs the
# task's real pipeline (post_task export hook + verifier.py) against the
# guest VM and writes /logs/verifier/reward.json for Harbor's Verifier.
# On the gym-anything custom backend this script is not executed: the
# backend intercepts the invocation and runs the same pipeline host-side.
exec python -m gym_anything.integrations.harbor.container finalize \\
  --reward-path /logs/verifier/reward.json \\
  --verifier-path /logs/verifier/verifier.json
"""

_SOLVE_SH = """#!/usr/bin/env bash
set -euo pipefail

# cua-world tasks are interactive GUI tasks graded by per-task verifiers
# against live application state; no scripted oracle solution is shipped.
# This follows the precedent of the OSWorld and TheAgentCompany adapters.
echo "cua-world does not ship oracle solve scripts." >&2
exit 1
"""

_DOCKERFILE = """# Generic runtime for gym-anything Harbor tasks: QEMU inside the container
# boots the task's guest VM (the same shape gym-anything's ModalRunner
# sandbox uses). This file is identical across tasks; the task identity
# lives in gym-anything.json.
FROM python:3.12-slim-bookworm

RUN apt-get update && apt-get install --no-install-recommends -y \\
        git \\
        qemu-system-x86 \\
        qemu-utils \\
        wget \\
        curl \\
        ca-certificates \\
        genisoimage \\
        openssh-client \\
        procps \\
        unzip \\
        zstd \\
        tini \\
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG GYM_ANYTHING_REF={ref}
RUN pip install --no-cache-dir \\
    "gym-anything{extras} @ git+https://github.com/cmu-l3/gym-anything@${{GYM_ANYTHING_REF}}"

COPY gym-anything.json /harbor-task/gym-anything.json

ENV GYM_ANYTHING_QEMU_CACHE=/gym-anything-cache/qemu \\
    GA_HARBOR_PORT=7317 \\
    GA_HARBOR_RUNNER=qemu

ENTRYPOINT ["tini", "-s", "--", "python", "-m", "gym_anything.integrations.harbor.container", "serve"]
"""

_DOCKER_COMPOSE = """# Mirrors the OSWorld adapter's runtime shape: KVM passthrough plus a shared
# cache volume so the guest image is provisioned once per host and reused
# across trials. Create the volume once:
#   docker volume create harbor-gym-anything-cache
services:
  main:
    command: []
    devices:
      - /dev/kvm
    environment:
      GA_HARBOR_PORT: "7317"
      GA_HARBOR_RUNNER: qemu
      GYM_ANYTHING_QEMU_CACHE: /gym-anything-cache/qemu
    volumes:
      - gym-anything-cache:/gym-anything-cache
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:7317/health >/dev/null"]
      interval: 10s
      timeout: 5s
      retries: 720
      start_period: 2400s
    stop_grace_period: 2m

volumes:
  gym-anything-cache:
    external: true
    name: harbor-gym-anything-cache
"""

_DEFAULT_KEYWORDS = ["computer-use", "gui", "gym-anything"]

# Default grading: the VLM checklist (a VLM judges the trajectory against
# each task's vlm_checklist.json). The programmatic verifiers read live,
# agent-mutable application state for some tasks, so the prime hub shell
# made the same choice for the same reason. Set "mode" to None to restore
# each task's declared (usually programmatic) mode.
_DEFAULT_VERIFIER = {
    "mode": "vlm_checklist",
    "vlm_backend": "local",
    "vlm_base_url": "https://generativelanguage.googleapis.com/v1beta/openai/",
    "vlm_model": "gemini-3.5-flash",
    "vlm_api_key_var": "GEMINI_API_KEY",
}


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

[verifier.env]
GEMINI_API_KEY = "${{GEMINI_API_KEY:-}}"

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
    gym_anything_ref: str = "main",
    pip_extras: str = "",
    verifier: Optional[Dict[str, Any]] = _UNSET,  # type: ignore[assignment]
) -> Path:
    """Compile one benchmark task into a Harbor task directory.

    ``build_timeout_sec`` defaults high because the first boot of an
    environment provisions it; later boots load from the cache volume.
    ``gym_anything_ref`` pins the gym-anything git ref installed into the
    task image; ``pip_extras`` adds extras (e.g. ``"benchmark"`` for the
    full verifier dependency corpus — core deps already cover PIL/numpy).
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
    if verifier is not _UNSET:
        if verifier:
            ga_config["verifier"] = dict(verifier)
    else:
        ga_config["verifier"] = dict(_DEFAULT_VERIFIER)
    (out_dir / "environment" / "gym-anything.json").write_text(
        json.dumps(ga_config, indent=2) + "\n"
    )

    extras = f"[{pip_extras}]" if pip_extras else ""
    (out_dir / "environment" / "Dockerfile").write_text(
        _DOCKERFILE.format(ref=gym_anything_ref, extras=extras)
    )
    (out_dir / "environment" / "docker-compose.yaml").write_text(_DOCKER_COMPOSE)

    solution_dir = out_dir / "solution"
    solution_dir.mkdir(exist_ok=True)
    solve_path = solution_dir / "solve.sh"
    solve_path.write_text(_SOLVE_SH)
    solve_path.chmod(0o755)

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
