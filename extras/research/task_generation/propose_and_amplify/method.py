"""Propose-and-Amplify task generation driver (CUA-World §4).

Three sequential stages, run end-to-end by default:

  1. propose — agentic Claude Code authors a small set of hard, realistic
               seed tasks and writes the task folders directly into the
               env's tasks/ directory.
  2. amplify — non-agentic Gemini expands the seeds into many more tasks.
               Two internal passes (matches the original code):
                 (a) README pass:  generate task spec markdown
                                   (pipeline.main_any_app_enhanced)
                 (b) files pass:   fill in setup_task.sh / verifier.py /
                                   export_result.sh / README.md
                                   (pipeline.main_files_any_app_enhanced)
  3. extract — write the final task folders under <env>/tasks/ from the
               files-pass pickle.

Stages share artifacts via pickle files in <output-dir>/<env_dir>/.

Invoked through:

    gym-anything-extras research task_generation propose_and_amplify \
        --software "Moodle" --env-dir moodle_env

Run a single stage with --stage <name>.
"""

from __future__ import annotations

import argparse
import json
import os
import pickle
import subprocess
import sys
from pathlib import Path
from typing import List, Optional

from extras.research.task_generation.propose_and_amplify.pipeline import (
    edit_task,
    propose_cc,
)
from extras.research.task_generation.propose_and_amplify.pipeline.extract_tasks import (
    # Robust (4-fallback) name extractor that matches what the extract
    # stage uses to convert pickles to task folders. Returns the bare
    # name (no `@N` suffix). Using this here keeps seed_tasks.json
    # consistent with what `extract` will actually write to disk.
    extract_task_name_from_response,
)


HERE = Path(__file__).resolve().parent
PIPELINE_DIR = HERE / "pipeline"
MEMORY_DIR = HERE / "memory"

DEFAULT_AMPLIFIER_MODEL = "gemini-3-pro-preview"
DEFAULT_PROPOSER_MODEL = "sonnet"  # passed to claude --model in the cc proposer
DEFAULT_AMPLIFY_COUNT = 75
DEFAULT_TIMEOUT_SEC = 7200


# ---------------------------------------------------------------------------
# Workspace + env resolution
# ---------------------------------------------------------------------------


def _default_workspace() -> Path:
    candidate = HERE.parents[3]
    return candidate if (candidate / "src" / "gym_anything").is_dir() else Path.cwd()


def _resolve_env_folder(env_dir: str, workspace: Path) -> Path:
    path = Path(env_dir)
    if path.is_absolute() and path.is_dir():
        return path
    candidate = workspace / "benchmarks" / "cua_world" / "environments" / env_dir
    if candidate.is_dir():
        return candidate
    candidate2 = workspace / env_dir
    if candidate2.is_dir():
        return candidate2
    raise FileNotFoundError(
        f"Cannot resolve --env-dir {env_dir!r}: not absolute, not under "
        f"{workspace / 'benchmarks/cua_world/environments'}, and not under "
        f"{workspace}. Pass an absolute path or check the env name."
    )


# ---------------------------------------------------------------------------
# Subprocess helper
# ---------------------------------------------------------------------------


def _run_subprocess(cmd: List[str], cwd: Path) -> int:
    print(f"[propose_and_amplify] $ {' '.join(cmd)}")
    proc = subprocess.run(cmd, cwd=str(cwd))
    return proc.returncode


# ---------------------------------------------------------------------------
# File-naming helpers (must match pipeline scripts' output_prefix logic)
# ---------------------------------------------------------------------------


def _slug(s: str) -> str:
    return s.replace(" ", "_")


def _model_slug(model: str) -> str:
    return model.replace("/", "-")


def _readme_prefix(amplifier_model: str, software: str) -> str:
    """Mirrors main_any_app_enhanced.get_output_prefix."""
    return f"enhanced_{_model_slug(amplifier_model)}_{_slug(software)}"


def _files_prefix(amplifier_model: str, software: str) -> str:
    """Mirrors main_files_any_app_enhanced.get_output_prefix when --step1_model
    is not set, the file generator names its output as
    enhanced_files_<model>_<software>."""
    return f"enhanced_files_{_model_slug(amplifier_model)}_{_slug(software)}"


# ---------------------------------------------------------------------------
# Stage runners
# ---------------------------------------------------------------------------


def _stage_propose(args: argparse.Namespace, env_folder: Path,
                   output_dir: Path) -> int:
    """Agentic Claude Code proposer. Writes task folders directly into
    <env>/tasks/."""
    propose_cc.run(
        target_env_dir=env_folder.name,
        workspace=Path(args.workspace_resolved),
        logs_dir=output_dir / "propose_logs",
        claude_bin=args.claude_bin,
        model=args.proposer_model,
        start_idx=args.propose_start_idx,
        session_id=args.session_id,
        timeout=args.timeout_sec,
    )
    return 0


def _stage_amplify(args: argparse.Namespace, env_folder: Path,
                   output_dir: Path) -> int:
    """Non-agentic Gemini amplifier, three passes:
       (a) README pass produces the task spec markdown.
       (b) Files pass fills in setup_task.sh / verifier.py / etc.
       (c) Snapshot pass writes the generated task names into
           <env>/tasks/seed_tasks.json so subsequent amplify runs see
           them as seeds.
    """
    workspace = Path(args.workspace_resolved)
    readme_prefix = _readme_prefix(args.amplifier_model, args.software)
    questions_pkl = output_dir / f"{readme_prefix}_questions.pkl"
    messages_pkl = output_dir / f"{readme_prefix}_messages.pkl"
    files_prefix = _files_prefix(args.amplifier_model, args.software)
    files_pkl = output_dir / f"{files_prefix}_questions.pkl"

    # (a) README pass
    rc = _run_subprocess(
        [
            sys.executable, "-m",
            "extras.research.task_generation.propose_and_amplify.pipeline.main_any_app_enhanced",
            "--software_name", args.software,
            "--env_folder", str(env_folder),
            "--max_questions", str(args.amplify_count),
            "--model", args.amplifier_model,
            "--output_dir", str(output_dir),
            "--temperature", str(args.temperature),
            "--max_thinking_tokens", str(args.max_thinking_tokens),
        ],
        cwd=workspace,
    )
    if rc != 0:
        return rc

    # (b) Files pass
    rc = _run_subprocess(
        [
            sys.executable, "-m",
            "extras.research.task_generation.propose_and_amplify.pipeline.main_files_any_app_enhanced",
            "--software_name", args.software,
            "--env_folder", str(env_folder),
            "--messages_file", str(messages_pkl),
            "--questions_file", str(questions_pkl),
            "--model", args.amplifier_model,
            "--output_dir", str(output_dir),
            "--num_workers", str(args.num_workers),
            "--temperature", str(args.temperature),
        ],
        cwd=workspace,
    )
    if rc != 0:
        return rc

    # (c) Snapshot the amplifier's generated task names into
    # <env>/tasks/seed_tasks.json. We prefer the files-pass pickle
    # because that reflects the final task set; fall back to the
    # README-pass pickle if the files pass left no record (e.g.
    # because a step1_model prefix was used).
    pkl_for_names = files_pkl if files_pkl.exists() else questions_pkl
    write_seed_tasks_json(env_folder, pkl_for_names)
    return 0


def _extract_task_names(pickle_path: Path) -> List[str]:
    """Read a questions pickle and pull out task names in order, deduped.

    Uses the same robust extractor as the ``extract`` stage so that
    every name we record corresponds to a task folder ``extract`` will
    actually write. Returns bare names (no ``@N`` suffix), matching the
    format of existing ``seed_tasks.json`` files in the corpus.
    """
    if not pickle_path.exists():
        return []
    with pickle_path.open("rb") as fh:
        data = pickle.load(fh)
    names: List[str] = []
    for item in data:
        if not isinstance(item, str):
            continue
        name = extract_task_name_from_response(item)
        if name and name not in names:
            names.append(name)
    return names


def write_seed_tasks_json(env_folder: Path, questions_pkl: Path) -> Path:
    """Write the amplifier's generated task names to
    <env>/tasks/seed_tasks.json. Merges with any existing entries so a
    re-run never drops previously-recorded seeds.

    Returns the path that was written.
    """
    new_names = _extract_task_names(questions_pkl)
    seed_path = env_folder / "tasks" / "seed_tasks.json"
    existing: List[str] = []
    if seed_path.exists():
        try:
            loaded = json.loads(seed_path.read_text(encoding="utf-8"))
            if isinstance(loaded, list):
                existing = [n for n in loaded if isinstance(n, str)]
        except (json.JSONDecodeError, OSError):
            existing = []

    merged = list(existing)
    for name in new_names:
        if name not in merged:
            merged.append(name)

    seed_path.parent.mkdir(parents=True, exist_ok=True)
    seed_path.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
    print(f"[propose_and_amplify] wrote {len(merged)} seed names to {seed_path}")
    return seed_path


def _stage_extract(args: argparse.Namespace, env_folder: Path,
                   output_dir: Path) -> int:
    """Write task folders under <env>/tasks/ from the files-pass pickle."""
    files_prefix = _files_prefix(args.amplifier_model, args.software)
    cmd = [
        sys.executable, "-m",
        "extras.research.task_generation.propose_and_amplify.pipeline.extract_tasks",
        "--questions_file",
        str(output_dir / f"{files_prefix}_questions.pkl"),
        "--output_dir", str(env_folder / "tasks"),
    ]
    if args.overwrite:
        cmd.append("--overwrite")
    return _run_subprocess(cmd, cwd=Path(args.workspace_resolved))


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


_STAGES = ("propose", "amplify", "extract")
_EDIT_STAGE = "edit"  # not part of _STAGES; invoked only via --stage edit


def run_pipeline(args: argparse.Namespace) -> int:
    workspace = (args.workspace or _default_workspace()).resolve()
    args.workspace_resolved = str(workspace)
    env_folder = _resolve_env_folder(args.env_dir, workspace).resolve()

    # --- Edit mode short-circuits the pipeline ---------------------------
    if args.stage == _EDIT_STAGE:
        if not args.target_task:
            raise ValueError("--stage edit requires --target-task <task_name>")
        logs_dir = (
            Path(args.output_dir).resolve()
            if args.output_dir
            else workspace / "edit_task_logs"
        )
        logs_dir.mkdir(parents=True, exist_ok=True)
        print(
            f"\n=== Edit Task: {args.software} ({env_folder.name} / "
            f"{args.target_task}) ==="
        )
        print(f"Workspace : {workspace}")
        print(f"Env folder: {env_folder}")
        print(f"Logs dir  : {logs_dir}")
        print(f"Editor    : claude code (model={args.proposer_model})")
        edit_task.run(
            target_env_dir=env_folder.name,
            target_task=args.target_task,
            workspace=workspace,
            logs_dir=logs_dir,
            claude_bin=args.claude_bin,
            model=args.proposer_model,
            start_idx=args.propose_start_idx,
            session_id=args.session_id,
            timeout=args.timeout_sec,
        )
        print(
            f"\n=== Edit Task complete: task at "
            f"{env_folder / 'tasks' / args.target_task} ==="
        )
        return 0

    output_dir = (
        Path(args.output_dir).resolve()
        if args.output_dir else
        workspace / "task_generation_runs" / env_folder.name
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    plan = _STAGES if args.stage == "all" else (args.stage,)
    print(f"\n=== Propose-and-Amplify: {args.software} ({env_folder.name}) ===")
    print(f"Workspace : {workspace}")
    print(f"Env folder: {env_folder}")
    print(f"Output dir: {output_dir}")
    print(f"Stages    : {', '.join(plan)}")
    print(f"Proposer  : claude code (model={args.proposer_model})")
    print(f"Amplifier : {args.amplifier_model}")

    for stage in plan:
        print(f"\n----- stage: {stage} -----")
        if stage == "propose":
            rc = _stage_propose(args, env_folder, output_dir)
        elif stage == "amplify":
            rc = _stage_amplify(args, env_folder, output_dir)
        elif stage == "extract":
            rc = _stage_extract(args, env_folder, output_dir)
        else:  # unreachable; argparse constrains it
            raise ValueError(f"Unknown stage: {stage}")

        if rc != 0:
            print(f"[propose_and_amplify] stage {stage} exited with code {rc}; stopping.")
            return rc

    print(f"\n=== Propose-and-Amplify complete: tasks under {env_folder / 'tasks'} ===")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="gym-anything-extras research task_generation propose_and_amplify",
        description=(
            "Generate task folders for an existing gym-anything environment. "
            "Step 1 (propose): agentic Claude Code writes seed tasks into the env. "
            "Step 2 (amplify): non-agentic Gemini expands them, generating "
            "task READMEs then implementation files. "
            "Step 3 (extract): writes task folders under <env>/tasks/."
        ),
    )
    p.add_argument("--software", required=True,
                   help="Human-readable software name (e.g. 'Moodle')")
    p.add_argument("--env-dir", required=True,
                   help="Env folder name under benchmarks/cua_world/environments/, "
                        "or absolute path")
    p.add_argument("--stage", choices=("all", *_STAGES, _EDIT_STAGE), default="all",
                   help="Which stage to run (default: all). Use 'edit' to "
                        "refactor an existing task in place; requires "
                        "--target-task.")
    p.add_argument("--target-task", default=None,
                   help="Existing task folder name (under <env>/tasks/) to "
                        "edit. Required with --stage edit.")

    # Proposer (agentic, Claude Code)
    p.add_argument("--proposer-model", default=DEFAULT_PROPOSER_MODEL,
                   help=f"Model passed to claude --model (default: {DEFAULT_PROPOSER_MODEL})")
    p.add_argument("--claude-bin", default=None,
                   help="Path to claude CLI (default: $CLAUDE_BIN or PATH)")
    p.add_argument("--session-id", default=None,
                   help="Resume an existing Claude Code session")
    p.add_argument("--propose-start-idx", type=int, default=0,
                   help="Resume the proposer from this internal phase index "
                        "(0=read notes, 1=create tasks, 2=blind nudge)")
    p.add_argument("--timeout-sec", type=int, default=DEFAULT_TIMEOUT_SEC,
                   help=f"Per-agent-invocation timeout (default: {DEFAULT_TIMEOUT_SEC})")

    # Amplifier (non-agentic, Gemini)
    p.add_argument("--amplifier-model", default=DEFAULT_AMPLIFIER_MODEL,
                   help=f"Non-agentic amplifier model (default: {DEFAULT_AMPLIFIER_MODEL})")
    p.add_argument("--amplify-count", type=int, default=DEFAULT_AMPLIFY_COUNT,
                   help=f"Amplified tasks to generate (default: {DEFAULT_AMPLIFY_COUNT})")
    p.add_argument("--temperature", type=float, default=1.0)
    p.add_argument("--max-thinking-tokens", type=int, default=16384)
    p.add_argument("--num-workers", type=int, default=4,
                   help="Parallel workers for the files pass (default: 4)")

    # Extract
    p.add_argument("--overwrite", action="store_true",
                   help="Overwrite existing task folders during extract")

    # Paths
    p.add_argument("--workspace", type=Path, default=None,
                   help="gym-anything repo root (default: auto-detect)")
    p.add_argument("--output-dir", type=Path, default=None,
                   help="Where stage pickles + logs go "
                        "(default: <workspace>/task_generation_runs/<env>)")
    return p


def run(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    return run_pipeline(args)


if __name__ == "__main__":
    raise SystemExit(run())
