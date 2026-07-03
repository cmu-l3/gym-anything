"""Training-hub binding for any benchmark following the core layout contract.

`build_task_rows` turns a benchmark (see `gym_anything.registry` for the
folder contract) into the dataset rows consumed by `verifiers.py`; it is
plain data with no third-party dependencies. `load_benchmark_environment` is
the canonical `load_environment` surface, and `make_hub_loader` derives a
publishable shell's `load_environment` from it, so a hub package is a
declaration (benchmark name, env id, defaults) rather than code.

`env_args` is built by introspecting the canonical signature, so every
behavior-affecting kwarg is carried automatically and worker re-instantiation
(prime-rl calls `load_environment(**env_args)`) is faithful by construction.
"""

from __future__ import annotations

import inspect
import json
import os
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Union

from ..registry import (
    get_tasks_for_environment,
    list_environments,
    resolve_benchmark_root,
)


def build_task_rows(
    benchmark: Union[str, Path],
    env_names: Union[str, List[str]] = "all",
    split: str = "all",
    surface: str = "raw",
    task_ids: Optional[List[str]] = None,
    max_examples: Optional[int] = None,
    seed: int = 0,
) -> List[Dict[str, Any]]:
    """Build dataset rows for benchmark environments.

    Args:
        benchmark: benchmark root path or package name (e.g. "cua_world").
        env_names: environment name(s), or "all" for every environment that
            has tasks in the requested split/surface.
        split: task split ("all", "train", "test", or a named split).
        surface: "raw" or "verified".
        task_ids: optional whitelist of task ids.
        max_examples: cap on rows.
        seed: reset seed carried in each row's `info`.

    Each row carries the task's natural-language prompt and an `info` dict
    with an absolute `env_dir`, so consumers never depend on the working
    directory.
    """
    root = resolve_benchmark_root(benchmark)
    if env_names == "all":
        env_names = list_environments(root, split=split, surface=surface)
    elif isinstance(env_names, str):
        env_names = [env_names]

    rows: List[Dict[str, Any]] = []
    for env_name in env_names:
        env_dir = (root / "environments" / env_name).resolve()
        tasks = get_tasks_for_environment(env_name, root, split=split, surface=surface)
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
                        "seed": seed,
                    },
                    "task": f"{env_name}/{task_id}",
                }
            )
    if not rows:
        raise ValueError(
            f"No tasks found for benchmark={benchmark!r} env_names={env_names} "
            f"split={split!r} surface={surface!r} task_ids={task_ids}"
        )
    if max_examples is not None:
        rows = rows[:max_examples]
    return rows


def load_benchmark_environment(
    benchmark: Union[str, Path],
    env_names: Union[str, List[str]] = "all",
    split: str = "all",
    surface: str = "raw",
    task_ids: Optional[List[str]] = None,
    max_examples: Optional[int] = None,
    seed: int = 0,
    runner: Optional[str] = None,
    remote_url: Optional[str] = None,
    agent: Optional[str] = None,
    agent_args: Optional[Dict[str, Any]] = None,
    max_turns: int = 15,
    use_cache: bool = True,
    cache_level: str = "post_start",
    use_savevm: bool = False,
    verifier_mode: Optional[str] = None,
    vlm_backend: Optional[str] = None,
    vlm_model: Optional[str] = None,
    vlm_base_url: Optional[str] = None,
    vlm_api_key_var: Optional[str] = None,
    env_id: Optional[str] = None,
    **kwargs: Any,
):
    """Load any gym-anything benchmark as a verifiers Environment.

    Args:
        benchmark: benchmark root path or package name (e.g. "cua_world").
        env_names: environment name(s), or "all" for the whole benchmark.
        split / surface / task_ids / max_examples / seed: dataset selection
            (see `build_task_rows`).
        runner: gym-anything runner ("modal" boots VMs on Modal cloud;
            "qemu_native"/"docker"/... run locally if the host supports
            them; None lets the host auto-select).
        remote_url: run envs on a gym-anything remote cluster
            (master/worker) instead of in-process; `runner` is then ignored
            and the worker picks its own.
        agent: reference agent class name, REQUIRED, exactly as `--agent`
            locally (e.g. "Qwen3VLAgent"). Prime-rl drives this actual agent,
            reusing its system prompt and parser; the framework does the
            sampling. Must be an OpenAI-compatible agent (drivable).
        agent_args: the agent's own args dict, exactly as `--agent_args`
            (model, temperature, decoding_params, ...).
        max_turns: model-turn budget per rollout.
        use_cache / cache_level / use_savevm: gym-anything checkpoint knobs.
        verifier_mode: override the task's success mode for every task, e.g.
            "vlm_checklist" to grade with a VLM against each task's
            vlm_checklist.json instead of its programmatic verifier.py.
            None keeps each task's declared mode (usually "program").
        vlm_backend / vlm_model / vlm_base_url: VLM grader config when
            verifier_mode="vlm_checklist". Use vlm_backend="local" with an
            OpenAI-compatible vlm_base_url to route to any provider with a
            model like "google/gemini-3.5-flash".
        vlm_api_key_var: name of an env var holding the VLM API key (its
            value is read from the process env and passed to the grader).
        env_id: verifiers environment id (defaults to the benchmark name).
    """
    # Everything a worker needs to faithfully re-instantiate this environment,
    # captured from the actual call before any local mutation.
    env_args = _bound_env_args(load_benchmark_environment, locals())
    env_args.update(kwargs)

    from .verifiers import build_agent_env

    verifier_overrides: Dict[str, str] = {}
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
        benchmark,
        env_names=env_names,
        split=split,
        surface=surface,
        task_ids=task_ids,
        max_examples=max_examples,
        seed=seed,
    )
    return build_agent_env(
        rows,
        agent=agent,
        agent_args=agent_args,
        runner=runner,
        remote_url=remote_url,
        max_turns=max_turns,
        use_cache=use_cache,
        cache_level=cache_level,
        use_savevm=use_savevm,
        verifier_overrides=verifier_overrides or None,
        env_id=env_id or Path(str(benchmark)).name.replace("_", "-"),
        env_args=env_args,
        **kwargs,
    )


# Keys the verifiers framework passes itself when re-instantiating
# (vf.load_environment(env_id, **env_args)); carrying them in env_args
# collides at the call site.
_FRAMEWORK_RESERVED = {"env_id"}


def _bound_env_args(fn: Callable[..., Any], local_vars: Dict[str, Any]) -> Dict[str, Any]:
    """Capture every explicit parameter of `fn` from its locals, JSON-safely."""
    args: Dict[str, Any] = {}
    for name, param in inspect.signature(fn).parameters.items():
        if param.kind is inspect.Parameter.VAR_KEYWORD or name in _FRAMEWORK_RESERVED:
            continue
        value = local_vars[name]
        args[name] = str(value) if isinstance(value, Path) else value
    return args


def make_hub_loader(
    benchmark: Union[str, Path],
    env_id: Optional[str] = None,
    **defaults: Any,
) -> Callable[..., Any]:
    """Derive a hub package's `load_environment` from the canonical loader.

    The returned function accepts the full `load_benchmark_environment`
    surface; `defaults` seed hub-facing defaults that callers can override.
    Because workers re-instantiate via `load_environment(**env_args)` and
    `env_args` includes `benchmark`, the pinned benchmark yields to an
    explicit one so reconstruction is always faithful.
    """

    def load_environment(**kwargs: Any):
        merged = {**defaults, **kwargs}
        target = merged.pop("benchmark", benchmark)
        merged.setdefault("env_id", env_id)
        return load_benchmark_environment(target, **merged)

    load_environment.__doc__ = load_benchmark_environment.__doc__
    return load_environment


__all__ = [
    "build_task_rows",
    "load_benchmark_environment",
    "make_hub_loader",
]
