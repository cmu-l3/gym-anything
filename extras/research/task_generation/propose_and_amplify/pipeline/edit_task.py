"""Edit-one-existing-task driver for the expert console.

Sibling to ``propose_cc.py``. Where the proposer always *creates* 5 new
hard tasks, this driver scopes Claude Code to a **single existing
task** and rewrites it in place per the latest expert feedback. It
explicitly forbids creating new task folders.

Three phases (mirrors propose_cc shape):

  1. Read ``task_creation_notes/expert_feedback.md`` and only the
     relevant cross-cutting notes the agent needs.
  2. Inspect the target task (description, setup script, verifier,
     checklist) and the env it lives in.
  3. Edit the task files in place: ``task.json`` if the description
     needs revision, ``setup_task.sh`` if the data sources need to
     change, ``verifier.py`` + ``vlm_checklist.json`` to match. A
     blind-nudge round catches anything skipped.

The session id is returned so the launcher can resume if needed.
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


CLAUDE_TIMEOUT = 7200  # 2h per invocation, matches propose_cc

DISALLOWED_TOOLS = "AskUserQuestion,EnterPlanMode,ExitPlanMode,Task(Plan)"


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
            print(f"\n[edit_task] Timeout after {timeout}s — assuming done, killing.")
    finally:
        if pgid is not None:
            _kill_process_group(pgid)


def _packaged_notes_dir() -> Path:
    here = Path(__file__).resolve().parent
    method_dir = here.parent
    return method_dir / "memory" / "task_creation_notes"


def _read_phase_prompt(notes_ref: str, expert_ref: str) -> str:
    return (
        f"please read @{expert_ref} carefully — this is expert feedback from "
        f"a domain expert that you MUST follow. Also read @{notes_ref}/00_getting_started.md "
        f"and @{notes_ref}/01_core_principles.md for task quality requirements. "
        f"Do not enter plan mode or ask me for any input at any time."
    )


def _edit_phase_prompt(target_env_dir: str, target_task: str) -> str:
    task_dir = f"benchmarks/cua_world/environments/{target_env_dir}/tasks/{target_task}"
    return (
        f"Now refactor the existing task at @{task_dir}/ based on the expert "
        f"feedback you just read. Scan the expert_feedback.md for entries that "
        f"apply to env `{target_env_dir}` (matching env_dir or marked global). "
        f"\n\n"
        f"HARD CONSTRAINTS:\n"
        f"  - You MUST edit files inside {task_dir}/ in place. Do NOT create "
        f"a new task folder. Do NOT touch other tasks.\n"
        f"  - You MUST keep the task id in task.json stable (the env_id and the "
        f"folder name stay the same).\n"
        f"  - If the feedback says 'use real data', that means real data "
        f"FROM REAL SOURCES — not Odoo demo records, not synthetic Python "
        f"lists. Download, cite the source URL, and seed the application "
        f"properly. If the env uses demo data fixtures the application ships "
        f"with, replace them with real-data fixtures the task pre-seeds.\n"
        f"  - The verifier and the vlm_checklist must match the new task. "
        f"Update both.\n"
        f"  - Validate by running the setup script (use the gym-anything "
        f"runner) and verify the starting state matches the description.\n"
        f"\n"
        f"Files you may need to edit:\n"
        f"  - {task_dir}/task.json          (description, difficulty, metadata)\n"
        f"  - {task_dir}/setup_task.sh      (data sourcing + seeding)\n"
        f"  - {task_dir}/export_result.sh   (often unchanged)\n"
        f"  - {task_dir}/verifier.py        (must match new task)\n"
        f"  - {task_dir}/vlm_checklist.json (must match new task)\n"
        f"  - {task_dir}/validated_pi.json  (privileged info for VLM)\n"
        f"  - {task_dir}/README.md          (rewrite to match)\n"
        f"\n"
        f"(Unrelated Context: remember to use the visual_grounding MCP tool "
        f"to interact with the running environment.)"
    )


def _nudge_phase_prompt(target_env_dir: str, target_task: str) -> str:
    task_dir = f"benchmarks/cua_world/environments/{target_env_dir}/tasks/{target_task}"
    return (
        f"reread the expert feedback you read earlier. The task at @{task_dir}/ "
        f"is not yet fully addressing the feedback. Go through each requirement "
        f"in the feedback and confirm it is reflected in the task files. If "
        f"anything is missing, add it now — but DO NOT create new task folders, "
        f"only edit the existing one. Also make sure the verifier and "
        f"vlm_checklist match the new task description. "
        f"(Unrelated Context: remember to use the visual_grounding MCP tool "
        f"to interact with the running environment, and verify screenshots "
        f"after running setup to ensure the task is set up correctly.)"
    )


def run(
    target_env_dir: str,
    target_task: str,
    *,
    workspace: Path,
    logs_dir: Path,
    notes_dir: Optional[Path] = None,
    claude_bin: Optional[str] = None,
    model: str = "sonnet",
    start_idx: int = 0,
    session_id: Optional[str] = None,
    timeout: int = CLAUDE_TIMEOUT,
) -> str:
    """Run the task editor. Returns the session id."""
    binary = _resolve_bin(claude_bin, "CLAUDE_BIN", "claude")
    notes = (notes_dir or _packaged_notes_dir()).resolve()
    notes_ref = notes.as_posix()
    expert_ref = (notes / "expert_feedback.md").as_posix()
    task_dir_abs = (
        workspace
        / "benchmarks"
        / "cua_world"
        / "environments"
        / target_env_dir
        / "tasks"
        / target_task
    )
    if not task_dir_abs.is_dir():
        raise RuntimeError(
            f"Task directory does not exist: {task_dir_abs}. "
            f"Cannot edit a task that hasn't been created yet — use the "
            f"propose driver to create new tasks."
        )

    logs_dir.mkdir(parents=True, exist_ok=True)
    session_id = session_id or str(uuid.uuid4())

    print(f"Session ID: {session_id}")
    log_path = logs_dir / f"{target_env_dir}__{target_task}.txt"
    log_path.write_text(
        f"Session ID: {session_id}\n"
        f"Target Env Directory: {target_env_dir}\n"
        f"Target Task: {target_task}\n"
        f"Start Index: {start_idx}\n"
        f"Notes dir: {notes_ref}\n"
        f"Expert feedback file: {expert_ref}\n"
    )

    def append_log(line: str) -> None:
        with log_path.open("a") as fh:
            fh.write(line + "\n")

    # --- Step 1: Read expert feedback + core notes ---
    if not start_idx > 0:
        print("\n=== Step 1: Read Expert Feedback + Core Notes ===")
        run_claude(
            binary,
            [
                "-p",
                _read_phase_prompt(notes_ref, expert_ref),
                "--dangerously-skip-permissions",
                "--session-id",
                session_id,
                "--disallowedTools",
                DISALLOWED_TOOLS,
                "--model",
                model,
            ],
            cwd=workspace,
            timeout=timeout,
        )
        append_log("Step 1 (Read Feedback + Notes) Completed")
    else:
        print("Resuming from previous session, skipping step 1")

    # --- Step 2: Edit the target task in place ---
    if not start_idx > 1:
        print(f"\n=== Step 2: Edit Task '{target_task}' ===")
        run_claude(
            binary,
            [
                "-p",
                _edit_phase_prompt(target_env_dir, target_task),
                "--dangerously-skip-permissions",
                "--resume",
                session_id,
                "--disallowedTools",
                DISALLOWED_TOOLS,
                "--model",
                model,
            ],
            cwd=workspace,
            timeout=timeout,
        )
        append_log("Step 2 (Edit Task) Completed")
    else:
        print("Resuming from previous session, skipping step 2")

    # --- Step 3: Blind nudge to catch anything skipped ---
    if not start_idx > 2:
        print("\n=== Step 3: Nudge - Complete All Phases ===")
        run_claude(
            binary,
            [
                "-p",
                _nudge_phase_prompt(target_env_dir, target_task),
                "--dangerously-skip-permissions",
                "--resume",
                session_id,
                "--disallowedTools",
                DISALLOWED_TOOLS,
                "--model",
                model,
            ],
            cwd=workspace,
            timeout=timeout,
        )
        append_log("Step 3 (Nudge) Completed")
    else:
        print("Resuming from previous session, skipping step 3")

    print(f"\n=== Task Edit Complete ===")
    print(f"Session ID: {session_id}")
    print(f"Env Directory: {target_env_dir}")
    print(f"Task: {target_task}")
    return session_id


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Edit one existing task in place (Claude Code).",
    )
    parser.add_argument("target_env_dir", help="Env folder name (e.g. odoo_hr_env)")
    parser.add_argument("target_task", help="Task folder name to edit")
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
    logs_dir = (args.logs_dir or workspace / "edit_task_logs").resolve()
    run(
        target_env_dir=args.target_env_dir,
        target_task=args.target_task,
        workspace=workspace,
        logs_dir=logs_dir,
        claude_bin=args.claude_bin,
        model=args.model,
        start_idx=args.start_idx,
        session_id=args.session_id,
        timeout=args.timeout_sec,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
