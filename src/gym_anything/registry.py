"""Benchmark-folder discovery: environments, tasks, and splits.

This module is the core contract for benchmark layout. A *benchmark root* is
any folder shaped like:

    <root>/
      environments/<env_name>/env.json          # EnvSpec (see specs.py)
      environments/<env_name>/tasks/<task_id>/  # task.json + setup + verifier.py
      splits/<env_name>_split.json              # optional named task splits
      splits/verified.json                      # optional verified-task surface

Split files carry ``env_folder`` plus ``train_tasks`` / ``test_tasks`` /
``all_tasks`` lists; any other ``<name>_tasks`` key (or an
``additional_splits`` mapping) defines a named split. ``verified.json`` maps
environment names to human-verified task ids (``{"by_environment": {...}}``)
and defines the ``verified`` surface. Environments without a split file get
their splits synthesized from the task folders on disk.

Anything that follows this shape — a repo checkout, an installed wheel, or a
third-party package — is enumerable here and therefore consumable by every
downstream surface (CLI batch runs, agent evaluation, training-hub adapters)
without benchmark-specific binding code.

A benchmark is referenced by root path or by name; names resolve to the
``benchmarks.<name>`` package (falling back to a top-level ``<name>``
package), so installed copies work without a repo checkout.
"""

from __future__ import annotations

import importlib
import json
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, MutableMapping, Optional, Union

# Reserved split name: every task folder physically present under
# ``<env>/tasks/``, regardless of split-file curation or surface. This is the
# escape hatch for running tasks that exist on disk but were never listed in a
# split file. Always reflects the directory, so split files cannot override it.
DISK_SPLIT = "disk"


def resolve_benchmark_root(benchmark: Union[str, Path]) -> Path:
    """Resolve a benchmark reference (path or package name) to its root folder."""
    candidate = Path(benchmark)
    if candidate.is_dir() and (candidate / "environments").is_dir():
        return candidate.resolve()
    last_error: Optional[Exception] = None
    for module_name in (f"benchmarks.{benchmark}", str(benchmark)):
        try:
            module = importlib.import_module(module_name)
        except ImportError as e:
            last_error = e
            continue
        root = Path(module.__file__).resolve().parent
        if (root / "environments").is_dir():
            return root
        last_error = ValueError(f"{module_name} has no environments/ folder at {root}")
    raise ValueError(
        f"Cannot resolve benchmark {benchmark!r}: not a benchmark root path and no "
        f"importable benchmark package found ({last_error})"
    )


def _dedupe_preserve_order(values: Iterable[str]) -> List[str]:
    ordered: List[str] = []
    seen = set()
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        ordered.append(value)
    return ordered


def resolve_environment_key(env_ref: Union[str, Path]) -> str:
    path = Path(env_ref)
    return path.name if path.parts else str(env_ref)


def _load_json(path: Path) -> Mapping[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def _load_verified_tasks_by_environment(splits_root: Path) -> Dict[str, List[str]]:
    verified_path = splits_root / "verified.json"
    if not verified_path.exists():
        return {}
    data = _load_json(verified_path)
    by_environment = data.get("by_environment", {})
    if not isinstance(by_environment, dict):
        return {}
    normalized: Dict[str, List[str]] = {}
    for env_name, task_ids in by_environment.items():
        if isinstance(env_name, str) and isinstance(task_ids, list):
            normalized[env_name] = _dedupe_preserve_order(str(task_id) for task_id in task_ids)
    return normalized


def _extract_additional_splits(data: Mapping[str, object]) -> Dict[str, List[str]]:
    additional: Dict[str, List[str]] = {}

    declared = data.get("additional_splits", {})
    if isinstance(declared, dict):
        for split_name, task_ids in declared.items():
            if isinstance(split_name, str) and isinstance(task_ids, list):
                additional[split_name] = _dedupe_preserve_order(str(task_id) for task_id in task_ids)

    for key, value in data.items():
        if key in {"env_folder", "train_ratio", "train_tasks", "test_tasks", "all_tasks", "additional_splits"}:
            continue
        if key.endswith("_tasks") and isinstance(value, list):
            split_name = key[: -len("_tasks")]
            additional[split_name] = _dedupe_preserve_order(str(task_id) for task_id in value)

    return additional


def _load_split_definition(path: Path) -> tuple[str, Dict[str, List[str]]]:
    data = _load_json(path)
    env_folder = data.get("env_folder")
    if not isinstance(env_folder, str) or not env_folder:
        raise ValueError(f"Split file {path} is missing a valid env_folder")

    env_name = Path(env_folder).name
    train_tasks = _dedupe_preserve_order(str(task_id) for task_id in data.get("train_tasks", []) if isinstance(task_id, str))
    test_tasks = _dedupe_preserve_order(str(task_id) for task_id in data.get("test_tasks", []) if isinstance(task_id, str))

    raw_all_tasks = data.get("all_tasks", [])
    if isinstance(raw_all_tasks, list):
        all_tasks = _dedupe_preserve_order(str(task_id) for task_id in raw_all_tasks if isinstance(task_id, str))
    else:
        all_tasks = []
    if not all_tasks:
        all_tasks = _dedupe_preserve_order(train_tasks + test_tasks)

    splits = {
        "all": all_tasks,
        "train": train_tasks,
        "test": test_tasks,
    }
    splits.update(_extract_additional_splits(data))
    return env_name, splits


def _discover_environment_tasks(environments_root: Path) -> Dict[str, List[str]]:
    discovered: Dict[str, List[str]] = {}
    if not environments_root.is_dir():
        return discovered
    for env_dir in sorted(environments_root.iterdir()):
        if not env_dir.is_dir():
            continue
        tasks_dir = env_dir / "tasks"
        if not tasks_dir.exists():
            continue
        task_ids = sorted(task_dir.name for task_dir in tasks_dir.iterdir() if task_dir.is_dir())
        if task_ids:
            discovered[env_dir.name] = task_ids
    return discovered


def _filter_to_supported_surface(task_ids: Iterable[str], supported: set[str]) -> List[str]:
    return [task_id for task_id in task_ids if task_id in supported]


def _resolve_roots(
    benchmark: Optional[Union[str, Path]],
    splits_root: Optional[Path],
    environments_root: Optional[Path],
) -> tuple[Path, Path]:
    if splits_root is not None and environments_root is not None:
        return Path(splits_root), Path(environments_root)
    if benchmark is None:
        raise ValueError("Provide a benchmark (root path or package name) or explicit roots")
    root = resolve_benchmark_root(benchmark)
    return (
        Path(splits_root) if splits_root is not None else root / "splits",
        Path(environments_root) if environments_root is not None else root / "environments",
    )


def resolve_environment_dir(
    env_ref: Union[str, Path],
    benchmark: Optional[Union[str, Path]] = None,
    *,
    environments_root: Optional[Path] = None,
) -> Path:
    """Resolve an environment reference (name or path) to its folder."""
    candidate = Path(env_ref)
    if candidate.exists():
        return candidate.resolve()
    if environments_root is None:
        if benchmark is None:
            raise ValueError("Provide a benchmark (root path or package name) or environments_root")
        environments_root = resolve_benchmark_root(benchmark) / "environments"
    return (Path(environments_root) / resolve_environment_key(env_ref)).resolve()


def load_environment_task_splits(
    benchmark: Optional[Union[str, Path]] = None,
    *,
    surface: str = "raw",
    splits_root: Optional[Path] = None,
    environments_root: Optional[Path] = None,
) -> Dict[str, Dict[str, List[str]]]:
    """Map every environment in a benchmark to its named task splits."""
    if surface not in {"raw", "verified"}:
        raise ValueError(f"surface must be 'raw' or 'verified', got {surface!r}")

    splits_root, environments_root = _resolve_roots(benchmark, splits_root, environments_root)

    registry: MutableMapping[str, Dict[str, List[str]]] = {}
    if splits_root.is_dir():
        for split_path in sorted(splits_root.glob("*_split.json")):
            env_name, split_data = _load_split_definition(split_path)
            registry[env_name] = split_data

    discovered_tasks = _discover_environment_tasks(environments_root)
    for env_name, task_ids in discovered_tasks.items():
        if env_name in registry:
            if not registry[env_name].get("all"):
                registry[env_name]["all"] = list(task_ids)
            continue
        registry[env_name] = {
            "all": list(task_ids),
            "train": list(task_ids),
            "test": [],
        }

    verified_by_environment = _load_verified_tasks_by_environment(splits_root)
    for env_name, split_data in list(registry.items()):
        supported_tasks = set(verified_by_environment.get(env_name, []))
        split_names = list(split_data.keys())
        if "verified" not in split_names:
            split_names.append("verified")

        filtered: Dict[str, List[str]] = {}
        for split_name in split_names:
            if split_name == "verified":
                base_values = split_data.get("all", [])
                verified_values = _filter_to_supported_surface(base_values, supported_tasks)
                if len(verified_values) != len(supported_tasks):
                    remaining = sorted(supported_tasks.difference(verified_values))
                    verified_values.extend(remaining)
                filtered[split_name] = verified_values
                continue

            values = split_data.get(split_name, [])
            if surface == "verified":
                filtered[split_name] = _filter_to_supported_surface(values, supported_tasks)
            else:
                filtered[split_name] = list(values)

        if surface == "verified":
            filtered["verified"] = list(filtered.get("all", filtered["verified"]))
            if not filtered["all"]:
                del registry[env_name]
                continue

        registry[env_name] = filtered

    for env_name, task_ids in verified_by_environment.items():
        if env_name in registry:
            continue
        registry[env_name] = {
            "all": list(task_ids) if surface == "verified" else [],
            "train": list(task_ids) if surface == "verified" else [],
            "test": [],
            "verified": list(task_ids),
        }

    # Reserved 'disk' split: the literal directory listing, surface-independent.
    # Reflects every task folder on disk even if it is absent from the split file.
    for env_name in registry:
        registry[env_name][DISK_SPLIT] = list(discovered_tasks.get(env_name, []))

    return {env_name: registry[env_name] for env_name in sorted(registry)}


def list_environments(
    benchmark: Optional[Union[str, Path]] = None,
    *,
    split: str = "all",
    surface: str = "raw",
    splits_root: Optional[Path] = None,
    environments_root: Optional[Path] = None,
) -> List[str]:
    """Environment names in a benchmark that have at least one task in `split`."""
    registry = load_environment_task_splits(
        benchmark,
        surface=surface,
        splits_root=splits_root,
        environments_root=environments_root,
    )
    return [env_name for env_name, splits in registry.items() if splits.get(split)]


def get_tasks_for_environment(
    env_ref: Union[str, Path],
    benchmark: Optional[Union[str, Path]] = None,
    *,
    split: str = "all",
    surface: str = "raw",
    splits_root: Optional[Path] = None,
    environments_root: Optional[Path] = None,
) -> List[str]:
    env_key = resolve_environment_key(env_ref)
    registry = load_environment_task_splits(
        benchmark,
        surface=surface,
        splits_root=splits_root,
        environments_root=environments_root,
    )
    if env_key not in registry:
        raise KeyError(f"Unknown environment key: {env_key}")
    if split not in registry[env_key]:
        available = ", ".join(sorted(registry[env_key]))
        raise KeyError(f"Unknown split '{split}' for {env_key}; available splits: {available}")
    return list(registry[env_key][split])


__all__ = [
    "DISK_SPLIT",
    "get_tasks_for_environment",
    "list_environments",
    "load_environment_task_splits",
    "resolve_benchmark_root",
    "resolve_environment_dir",
    "resolve_environment_key",
]
