"""CUA-World on the Prime Intellect Environments Hub.

Thin publishable shell: binds the CUA-World benchmark
(`benchmarks.cua_world.hub`) to the generic verifiers adapter
(`gym_anything.integrations.verifiers`). All rollout logic lives in the
gym-anything library; this module only wires the dataset and hub-facing
defaults.

Usage:
    vf-eval cua-world -m <vision-model> -n 1 -r 1 \
        -a '{"env_names": ["gimp_env"], "task_ids": ["horizontal_mirror"]}'
"""

from __future__ import annotations

import os
from typing import Any


def load_environment(
    env_names: list[str] | str = "gimp_env",
    split: str = "all",
    surface: str = "raw",
    task_ids: list[str] | None = None,
    max_examples: int | None = None,
    runner: str | None = "modal",
    remote_url: str | None = None,
    coordinate_mode: str = "norm1000",
    max_turns: int = 15,
    keep_recent_screenshots: int = 3,
    use_cache: bool = True,
    cache_level: str = "post_start",
    use_savevm: bool = False,
    verifier_mode: str | None = None,
    vlm_backend: str | None = None,
    vlm_model: str | None = None,
    vlm_base_url: str | None = None,
    vlm_api_key_var: str | None = None,
    **kwargs: Any,
):
    """CUA-World computer-use environment.

    Args:
        env_names: benchmark environment name(s), e.g. "gimp_env" or
            ["gimp_env", "libreoffice_calc_env"].
        split: task split ("all", "train", "test", or a named split).
        surface: "raw" or "verified".
        task_ids: optional whitelist of task ids.
        max_examples: cap on dataset rows.
        runner: gym-anything runner ("modal" boots VMs on Modal cloud;
            "qemu_native"/"docker"/... run locally if the host supports
            them; None lets the host auto-select).
        remote_url: run envs on a gym-anything remote cluster
            (master/worker) instead of in-process; `runner` is then ignored
            and the worker picks its own.
        coordinate_mode: "norm1000" (0-1000 normalized) or "pixel".
        max_turns: model-turn budget per rollout.
        keep_recent_screenshots: screenshots kept in context (older ones
            are replaced with placeholders to bound context growth).
        use_cache / cache_level / use_savevm: gym-anything checkpoint knobs.
        verifier_mode: override the task's success mode for every task, e.g.
            "vlm_checklist" to grade with a VLM against each task's
            vlm_checklist.json instead of its programmatic verifier.py.
            None keeps each task's declared mode (usually "program").
        vlm_backend / vlm_model / vlm_base_url: VLM grader config when
            verifier_mode="vlm_checklist". Use vlm_backend="local" with an
            OpenAI-compatible vlm_base_url to route to any provider (e.g.
            Prime Inference) with model like "google/gemini-3.5-flash".
        vlm_api_key_var: name of an env var holding the VLM API key (its
            value is read from the client env and passed to the grader).
    """
    from benchmarks.cua_world.hub import build_task_rows
    from gym_anything.integrations.verifiers import build_computer_env

    if isinstance(env_names, str):
        env_names = [env_names]

    verifier_overrides: dict[str, str] = {}
    if verifier_mode:
        verifier_overrides["GYM_ANYTHING_VERIFIER_MODE"] = verifier_mode
    if vlm_backend:
        verifier_overrides["VLM_BACKEND"] = vlm_backend
    if vlm_model:
        verifier_overrides["VLM_MODEL"] = vlm_model
    if vlm_base_url:
        verifier_overrides["VLM_BASE_URL"] = vlm_base_url
    if vlm_api_key_var:
        key_val = os.environ.get(vlm_api_key_var, "")
        if key_val:
            verifier_overrides["VLM_API_KEY"] = key_val

    rows = build_task_rows(
        env_names,
        split=split,
        surface=surface,
        task_ids=task_ids,
        max_examples=max_examples,
    )
    return build_computer_env(
        rows,
        runner=runner,
        remote_url=remote_url,
        coordinate_mode=coordinate_mode,
        max_turns=max_turns,
        keep_recent_screenshots=keep_recent_screenshots,
        use_cache=use_cache,
        cache_level=cache_level,
        use_savevm=use_savevm,
        verifier_overrides=verifier_overrides or None,
        env_id="cua-world",
        env_args={
            "env_names": env_names,
            "split": split,
            "surface": surface,
            "task_ids": task_ids,
            "runner": runner,
            "remote_url": remote_url,
            "coordinate_mode": coordinate_mode,
            "max_turns": max_turns,
            "verifier_mode": verifier_mode,
        },
        **kwargs,
    )
