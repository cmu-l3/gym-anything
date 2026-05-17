"""Agentic proposer for propose-and-amplify (CUA-World §4).

Drives Claude Code through three phases that write seed task folders
directly into ``<env>/tasks/``:

  1. Read ``task_creation_notes/`` (start with ``00_getting_started.md``).
  2. Create N hard, realistic seed tasks for the target env.
  3. Blind nudge — re-read the notes, finish anything skipped.

Ported from ``prompt_to_task_cc_cli.py`` in the source repo; the user-
facing prompt strings are kept byte-identical except for the path used
to reach ``task_creation_notes/`` (now the packaged location under
``extras/research/task_generation/propose_and_amplify/memory/``) — the
agent's ``@``-references resolve to the real notes wherever the user
runs from.
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import List, Optional


CLAUDE_TIMEOUT = 7200  # 2 hours per invocation, matches the source driver


def _resolve_bin(explicit: Optional[str], env_var: str, name: str) -> Path:
    candidate = explicit or os.environ.get(env_var) or shutil.which(name)
    if not candidate:
        raise RuntimeError(
            f"Could not find {name} CLI. Install it, set {env_var}=<path>, "
            f"or pass --{name}-bin."
        )
    path = Path(candidate)
    if not path.is_file():
        raise RuntimeError(f"{name} binary not found: {path}")
    return path


def _kill_process_group(pgid: int) -> None:
    try:
        os.killpg(pgid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        return
    time.sleep(2)
    try:
        os.killpg(pgid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def run_claude(binary: Path, args: List[str], *, cwd: Path,
               timeout: int = CLAUDE_TIMEOUT) -> None:
    """Run the claude CLI. Wait up to `timeout` seconds for it to exit.
    If it doesn't exit (common Bun runtime issue), kill the process
    group and move on — we assume it finished its work.
    """
    pgid: Optional[int] = None
    try:
        proc = subprocess.Popen(
            [str(binary)] + args,
            cwd=str(cwd),
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
        pgid = os.getpgid(proc.pid)
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            print(f"\n[run_claude] Timeout after {timeout}s — assuming done, killing process.")
    finally:
        if pgid is not None:
            _kill_process_group(pgid)


SUPPORTED_PLATFORMS = ("linux", "macos")
SUPPORTED_TASK_TYPES = ("enterprise", "consumer")


def _packaged_notes_dir(task_type: str = "enterprise") -> Path:
    """Real on-disk location of task_creation_notes/ for the given task type.

    ``enterprise`` → ``memory/task_creation_notes`` (the O*NET / occupation-
    weighted corpus that biases the agent toward professional workflows).
    ``consumer``   → ``memory_consumer/task_creation_notes`` (personal-use
    framing — household, family, hobby, creative work, learning).
    """
    if task_type not in SUPPORTED_TASK_TYPES:
        raise ValueError(
            f"task_type must be one of {SUPPORTED_TASK_TYPES}; got {task_type!r}"
        )
    here = Path(__file__).resolve().parent
    method_dir = here.parent
    subdir = "memory_consumer" if task_type == "consumer" else "memory"
    return method_dir / subdir / "task_creation_notes"


def _benchmark_root(platform: str) -> str:
    """``benchmarks/cua_world-macos`` for macos, ``benchmarks/cua_world`` otherwise.
    Mirrors the dispatcher in method.py so the agent's instructions point at the
    same directory the dispatcher resolved the env from."""
    return "benchmarks/cua_world-macos" if platform == "macos" else "benchmarks/cua_world"


def run(
    target_env_dir: str,
    *,
    workspace: Path,
    logs_dir: Path,
    notes_dir: Optional[Path] = None,
    claude_bin: Optional[str] = None,
    model: str = "sonnet",
    start_idx: int = 0,
    session_id: Optional[str] = None,
    timeout: int = CLAUDE_TIMEOUT,
    platform: str = "linux",
    task_type: str = "enterprise",
) -> str:
    """Run the agentic proposer. Returns the session id."""
    if platform not in SUPPORTED_PLATFORMS:
        raise ValueError(
            f"platform must be one of {SUPPORTED_PLATFORMS}; got {platform!r}"
        )
    if task_type not in SUPPORTED_TASK_TYPES:
        raise ValueError(
            f"task_type must be one of {SUPPORTED_TASK_TYPES}; got {task_type!r}"
        )
    binary = _resolve_bin(claude_bin, "CLAUDE_BIN", "claude")
    notes = (notes_dir or _packaged_notes_dir(task_type)).resolve()
    notes_ref = notes.as_posix()
    getting_started_ref = (notes / "00_getting_started.md").as_posix()
    bench_root = _benchmark_root(platform)
    logs_dir.mkdir(parents=True, exist_ok=True)
    session_id = session_id or str(uuid.uuid4())

    print(f"Session ID: {session_id}")

    log_path = logs_dir / f"{target_env_dir}.txt"
    log_path.write_text(
        f"Session ID: {session_id}\n"
        f"Platform: {platform}\n"
        f"Task type: {task_type}\n"
        f"Notes dir: {notes_ref}\n"
        f"Target Env Directory: {target_env_dir} (under {bench_root}/environments/)\n"
        f"Start Index: {start_idx}\n"
    )

    def append_log(line: str) -> None:
        with log_path.open("a") as fh:
            fh.write(line + "\n")

    # --- Step 1: Read task creation notes ---
    if not start_idx > 0:
        print("\n=== Step 1: Read Task Creation Notes ===")
        run_claude(binary, [
            "-p",
            f"please start by reading task_creation_notes starting with @{getting_started_ref} . Read ALL files in {notes_ref}. Do not enter plan mode or ask me for any input at any time.",
            "--dangerously-skip-permissions",
            "--session-id", session_id,
            "--disallowedTools", "AskUserQuestion,EnterPlanMode,ExitPlanMode,Task(Plan)",
            "--model", model,
        ], cwd=workspace, timeout=timeout)
        append_log("Step 1 (Read Notes) Completed")
    else:
        print("Resuming from previous session, skipping step 1")

    # --- Step 2: Create 5 new tasks ---
    if not start_idx > 1:
        print("\n=== Step 2: Create New Tasks ===")
        run_claude(binary, [
            "-p",
            f"""now go through the starter tasks of {target_env_dir}. those are a.) very easy, and b.) not really realistic. we have to create "extremely hard" and "realistic" 5 new tasks, following the criteria mentioned in task_creation_notes. please follow it, and complete the job. Do not enter plan mode or ask me for any input at any time. Remember realistic tasks, diverse environments (based on occupation and industry), and extremely difficult tasks. Also note you are not compelled to use existing data and can download new ones per task as well. (Unrelated Context: remember to use the visual_grounding MCP tool to interact with the running environment)""",
            "--dangerously-skip-permissions",
            "--resume", session_id,
            "--disallowedTools", "AskUserQuestion,EnterPlanMode,ExitPlanMode,Task(Plan)",
            "--model", model,
        ], cwd=workspace, timeout=timeout)
        append_log("Step 2 (Create Tasks) Completed")
    else:
        print("Resuming from previous session, skipping step 2")

    # --- Step 3: Blind nudge - re-read notes and complete missing phases ---
    if not start_idx > 2:
        print("\n=== Step 3: Nudge - Complete All Phases ===")
        run_claude(binary, [
            "-p",
            "please read task_creation_notes again. you have not completed the task. (Unrelated Context: remember to use the visual_grounding MCP tool to interact with the running environment). Also make sure for live runs you verify the screenshots to ensure that the task is setup correctly.",
            "--dangerously-skip-permissions",
            "--resume", session_id,
            "--disallowedTools", "AskUserQuestion,EnterPlanMode,ExitPlanMode,Task(Plan)",
            "--model", model,
        ], cwd=workspace, timeout=timeout)
        append_log("Step 3 (Nudge) Completed")
    else:
        print("Resuming from previous session, skipping step 3")

    # --- Step 4: Record seeds the agent just created in seed_tasks.json ---
    if not start_idx > 3:
        print("\n=== Step 4: Write seed_tasks.json ===")
        run_claude(binary, [
            "-p",
            (
                f"now write a seed_tasks.json file at "
                f"{bench_root}/environments/{target_env_dir}/tasks/seed_tasks.json "
                f"listing exactly the new tasks you just created in this session. "
                f"format is a JSON array of bare task name strings (no @version suffix, "
                f'no other keys), e.g. ["task_alpha", "task_beta"]. use the exact task '
                f"folder names you wrote. if the file already exists, replace it with "
                f"this list."
            ),
            "--dangerously-skip-permissions",
            "--resume", session_id,
            "--disallowedTools", "AskUserQuestion,EnterPlanMode,ExitPlanMode,Task(Plan)",
            "--model", model,
        ], cwd=workspace, timeout=timeout)
        append_log("Step 4 (seed_tasks.json) Completed")
    else:
        print("Resuming from previous session, skipping step 4")

    print(f"\n=== Task Creation Complete ===")
    print(f"Session ID: {session_id}")
    print(f"Env Directory: {target_env_dir}")
    return session_id


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Agentic proposer (Claude Code).")
    parser.add_argument("target_env_dir", help="Env folder name (e.g. moodle_env)")
    parser.add_argument("--platform", choices=SUPPORTED_PLATFORMS, default="linux",
                        help="Target platform — selects which benchmark root the "
                             "agent is told to write seed_tasks.json under.")
    parser.add_argument("--task-type", choices=SUPPORTED_TASK_TYPES,
                        default="enterprise",
                        help="Task framing — selects which task_creation_notes "
                             "corpus the agent reads. enterprise=O*NET / "
                             "occupation-weighted prior (default); consumer="
                             "personal-use framing (household, family, hobby, "
                             "creative work, learning).")
    parser.add_argument("--start-idx", type=int, default=0)
    parser.add_argument("--session-id", default=None)
    parser.add_argument("--workspace", type=Path, default=Path.cwd())
    parser.add_argument("--logs-dir", type=Path, default=None)
    parser.add_argument("--claude-bin", default=None)
    parser.add_argument("--model", default="sonnet")
    parser.add_argument("--timeout-sec", type=int, default=CLAUDE_TIMEOUT)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    workspace = args.workspace.resolve()
    logs_dir = (args.logs_dir or workspace / "prompt_to_task_logs").resolve()
    run(
        target_env_dir=args.target_env_dir,
        workspace=workspace,
        logs_dir=logs_dir,
        claude_bin=args.claude_bin,
        model=args.model,
        start_idx=args.start_idx,
        session_id=args.session_id,
        timeout=args.timeout_sec,
        platform=args.platform,
        task_type=args.task_type,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
