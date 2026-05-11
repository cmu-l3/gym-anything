"""Stage 1: Walk benchmarks/cua_world/environments/ and emit one record per task.

Output shape (one JSONL line per task):

    {
        "task_id": "<task folder name>",
        "env_id": "<env folder name>",
        "env_spec": {... env.json ...},
        "task_spec": {... task.json ...},
        "task_root": "<absolute path>",
        "env_root": "<absolute path>",
        "has_setup_script": bool,
        "has_verifier": bool,
        "has_vlm_checklist": bool,
        "has_export_script": bool,
        "readme": "<task README content if present, else null>"
    }

A small fraction of `task.json` files in the corpus are pre-existing
corruption (truncated strings, etc.). Those are recorded in
data/skipped.jsonl with the parse error and skipped, not silently dropped.
Hard-fail conditions: any broken env.json, or task skip rate >5%.

The point of preserving the raw specs is that downstream stages (gdp_join,
enrich, build_index) can pull whatever they need without re-walking the tree.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional, Tuple

from .jsonio import write_jsonl
from .paths import DATA_DIR, ENV_DIR, RAW_TASKS

logger = logging.getLogger(__name__)

SKIPPED_PATH = DATA_DIR / "skipped.jsonl"
SKIP_RATE_LIMIT = 0.05  # hard-fail if more than this fraction of tasks are unreadable


class CorpusError(RuntimeError):
    """Raised when corpus integrity is too poor to proceed."""


def _load_json_strict(path: Path) -> Dict[str, Any]:
    """Load JSON or raise — caller decides whether to fail or skip."""
    if not path.is_file():
        raise FileNotFoundError(f"missing {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def _read_text(path: Path, max_chars: int = 8000) -> Optional[str]:
    if not path.is_file():
        return None
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    return text[:max_chars]


def iter_envs(env_dir: Path = ENV_DIR) -> Iterator[Path]:
    if not env_dir.is_dir():
        raise RuntimeError(f"environments dir not found: {env_dir}")
    for child in sorted(env_dir.iterdir()):
        if not child.is_dir():
            continue
        if child.name.startswith((".", "_")):
            continue
        if (child / "env.json").is_file():
            yield child


def iter_tasks(env_root: Path) -> Iterator[Path]:
    tasks_dir = env_root / "tasks"
    if not tasks_dir.is_dir():
        return
    for child in sorted(tasks_dir.iterdir()):
        if not child.is_dir():
            continue
        if child.name.startswith((".", "_")):
            continue
        if (child / "task.json").is_file():
            yield child


def build_record(env_root: Path, env_spec: Dict[str, Any], task_root: Path) -> Dict[str, Any]:
    task_spec = _load_json_strict(task_root / "task.json")
    readme = _read_text(task_root / "README.md")
    return {
        "task_id": task_root.name,
        "env_id": env_root.name,
        "env_spec": env_spec,
        "task_spec": task_spec,
        "task_root": str(task_root),
        "env_root": str(env_root),
        "has_setup_script": (task_root / "setup_task.sh").is_file(),
        "has_verifier": (task_root / "verifier.py").is_file(),
        "has_vlm_checklist": (task_root / "vlm_checklist.json").is_file(),
        "has_export_script": (task_root / "export_result.sh").is_file(),
        "readme": readme,
    }


def run(env_dir: Optional[Path] = None, output: Optional[Path] = None) -> int:
    """Walk all envs and tasks, emit one JSONL record per task. Returns count.

    Broken env.json → hard fail. Broken task.json → recorded in skipped.jsonl
    and skipped. If task skip rate exceeds SKIP_RATE_LIMIT the function raises.
    """
    if env_dir is None:
        env_dir = ENV_DIR
    if output is None:
        output = RAW_TASKS
    n_envs = 0
    records: List[Dict[str, Any]] = []
    skipped: List[Dict[str, Any]] = []
    total_seen = 0

    for env_root in iter_envs(env_dir):
        n_envs += 1
        try:
            env_spec = _load_json_strict(env_root / "env.json")
        except json.JSONDecodeError as exc:
            raise CorpusError(
                f"env.json is invalid JSON: {env_root}/env.json — {exc}"
            ) from exc

        for task_root in iter_tasks(env_root):
            total_seen += 1
            try:
                records.append(build_record(env_root, env_spec, task_root))
            except json.JSONDecodeError as exc:
                skipped.append({
                    "env_id": env_root.name,
                    "task_id": task_root.name,
                    "path": str(task_root / "task.json"),
                    "error": f"{type(exc).__name__}: {exc}",
                })
            except FileNotFoundError as exc:
                skipped.append({
                    "env_id": env_root.name,
                    "task_id": task_root.name,
                    "path": str(task_root),
                    "error": f"{type(exc).__name__}: {exc}",
                })

    n_kept = write_jsonl(output, records)
    skipped_path = output.parent / "skipped.jsonl"
    write_jsonl(skipped_path, skipped)

    skip_rate = (len(skipped) / total_seen) if total_seen else 0.0
    logger.info(
        "Ingest: %d tasks across %d envs kept; %d skipped (%.2f%%) → %s",
        n_kept, n_envs, len(skipped), skip_rate * 100, output,
    )
    if skipped:
        logger.warning(
            "Skipped tasks listed in %s. First 3: %s",
            skipped_path,
            [s["path"] for s in skipped[:3]],
        )
    if skip_rate > SKIP_RATE_LIMIT:
        raise CorpusError(
            f"Task skip rate {skip_rate*100:.2f}% exceeds {SKIP_RATE_LIMIT*100:.0f}%. "
            f"See {skipped_path} and fix the corpus before re-indexing."
        )
    return n_kept


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    print(run())
