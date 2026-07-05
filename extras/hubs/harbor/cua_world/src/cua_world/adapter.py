"""Adapter class for generating Harbor tasks from CUA-World-Long.

CUA-World-Long is the flagship benchmark of Gym-Anything: 200+ long-horizon
computer-use tasks, one per software, each running in a real desktop VM and
graded by the task's own programmatic verifier. The adapter enumerates the
benchmark's ``long_horizon`` split through the gym-anything registry and
renders one Harbor task directory per task from ``task-template/``.

Generated tasks are self-contained: the task image installs gym-anything at a
pinned ref, boots the task's guest VM via QEMU inside the container (KVM
required), and grades in-container through the task's real verifier pipeline.
See the README for runtime requirements (KVM, the shared image-cache volume).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple

TEMPLATE_DIR = Path(__file__).resolve().parent / "task-template"

BENCHMARK = "cua_world"
SPLIT = "long_horizon"
ORG = "cua-world"

# Parity subset (``--split parity``). We select and document the subset
# (the adapter guide's representative-subset mechanism); the parity plan
# built on it (agents, models, run counts) is agreed with the Harbor team
# before any runs. Populated when that selection is made.
PARITY_TASK_NAMES: List[str] = []

# Uniform protocol budgets for every task (the paper's model-side protocol):
# 500 steps and a 6-hour agent window. The per-task limits inside each
# task.json are not the benchmark protocol and are deliberately not used.
MAX_STEPS = 500
AGENT_TIMEOUT_SEC = 21600.0
VERIFIER_TIMEOUT_SEC = 1800.0
BUILD_TIMEOUT_SEC = 7200.0


class CuaWorldAdapter:
    def __init__(
        self,
        output_dir: Path,
        limit: int | None = None,
        overwrite: bool = False,
        task_ids: list[str] | None = None,
        split: str = "long",
        gym_anything_ref: str = "main",
    ):
        self.output_dir = Path(output_dir)
        self.limit = limit
        self.overwrite = overwrite
        self.task_ids = task_ids
        self.split = split
        self.gym_anything_ref = gym_anything_ref

    # -- enumeration -------------------------------------------------------

    def iter_tasks(self) -> List[Tuple[str, str]]:
        """(env_name, task_id) pairs of the CUA-World-Long split."""
        from gym_anything.registry import load_environment_task_splits

        splits = load_environment_task_splits(BENCHMARK)
        pairs = [
            (env_name, task_id)
            for env_name, env_splits in sorted(splits.items())
            for task_id in env_splits.get(SPLIT, [])
        ]
        if self.split == "parity":
            if not PARITY_TASK_NAMES:
                raise SystemExit(
                    "The parity subset is not defined yet (see the README "
                    "parity section for how it will be selected)."
                )
            wanted = set(PARITY_TASK_NAMES)
            pairs = [p for p in pairs if _task_name(*p) in wanted]
        if self.task_ids:
            wanted = set(self.task_ids)
            pairs = [p for p in pairs if _task_name(*p) in wanted]
        if self.limit is not None:
            pairs = pairs[: self.limit]
        return pairs

    # -- generation ---------------------------------------------------------

    def run(self) -> List[Path]:
        pairs = self.iter_tasks()
        if not pairs:
            raise SystemExit("No tasks selected; check --task-ids / --split.")
        written = []
        for env_name, task_id in pairs:
            out_dir = self.output_dir / _task_name(env_name, task_id)
            if out_dir.exists() and not self.overwrite:
                continue
            written.append(self.generate_task(env_name, task_id, out_dir))
        print(f"Generated {len(written)} task(s) in {self.output_dir}")
        return written

    def generate_task(self, env_name: str, task_id: str, out_dir: Path) -> Path:
        from gym_anything.registry import resolve_environment_dir

        source_dir = resolve_environment_dir(env_name, BENCHMARK) / "tasks" / task_id
        task_json = json.loads((source_dir / "task.json").read_text())
        description = str(task_json.get("description") or "").strip()
        if not description:
            raise ValueError(f"{env_name}/{task_id} has no description")
        tags = task_json.get("tags") or task_json.get("metadata", {}).get("tags") or []

        substitutions = {
            "__TASK_NAME__": f"{ORG}/{_task_name(env_name, task_id)}",
            "__TASK_DESCRIPTION__": _toml_string(description),
            "__INSTRUCTION__": description,
            "__ENV_NAME__": env_name,
            "__TASK_ID__": task_id,
            "__MAX_STEPS__": str(MAX_STEPS),
            "__AGENT_TIMEOUT_SEC__": f"{AGENT_TIMEOUT_SEC:.1f}",
            "__VERIFIER_TIMEOUT_SEC__": f"{VERIFIER_TIMEOUT_SEC:.1f}",
            "__BUILD_TIMEOUT_SEC__": f"{BUILD_TIMEOUT_SEC:.1f}",
            "__TAGS__": ", ".join(_toml_string(str(t)) for t in tags),
            "__GYM_ANYTHING_REF__": self.gym_anything_ref,
        }
        _render_tree(TEMPLATE_DIR, out_dir, substitutions)
        (out_dir / "tests" / "test.sh").chmod(0o755)
        (out_dir / "solution" / "solve.sh").chmod(0o755)
        return out_dir


def _task_name(env_name: str, task_id: str) -> str:
    return f"{env_name}__{task_id}"


def _toml_string(value: str) -> str:
    # JSON string escaping is a valid TOML basic string for these fields.
    return json.dumps(value)


def _render_tree(template_dir: Path, out_dir: Path, substitutions: Dict[str, str]) -> None:
    for template_path in sorted(template_dir.rglob("*")):
        if not template_path.is_file():
            continue
        target = out_dir / template_path.relative_to(template_dir)
        target.parent.mkdir(parents=True, exist_ok=True)
        content = template_path.read_text()
        for marker, value in substitutions.items():
            content = content.replace(marker, value)
        target.write_text(content)
