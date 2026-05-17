"""Edit-existing-env driver for the expert console.

Sibling to ``method.py`` (which runs the full creation+audit loop for
a brand-new env). This driver targets an env that already exists and
asks the agent to apply expert feedback in place — without rebuilding
from scratch.

Two routes:
  - target=CREATOR  -> reads env_creation_notes/expert_feedback.md and
                       edits scripts/install_*.sh, scripts/setup_*.sh,
                       config/, and env.json as needed.
  - target=AUDIT    -> reads audit_expert_feedback.md and runs an
                       audit-only pass with the expert's note prepended
                       to the audit checklist. Produces an updated
                       audits/audit_<env>.md.

Both modes are single-session, three phases (read feedback → edit/audit
→ blind nudge). The same Claude Code subprocess pattern as method.py /
edit_task.py — no reimplementation of pipeline logic.
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
from typing import List, Literal, Optional


CLAUDE_TIMEOUT = 7200
DISALLOWED_TOOLS = "AskUserQuestion,EnterPlanMode,ExitPlanMode,Task(Plan)"

Route = Literal["creator", "audit"]


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
            print(f"\n[edit_env] Timeout after {timeout}s — assuming done, killing.")
    finally:
        if pgid is not None:
            _kill_process_group(pgid)


def _packaged_memory_dir() -> Path:
    return Path(__file__).resolve().parent / "memory"


def _feedback_path(memory_dir: Path, route: Route) -> str:
    if route == "creator":
        return (memory_dir / "env_creation_notes" / "expert_feedback.md").as_posix()
    return (memory_dir / "audit_expert_feedback.md").as_posix()


def _read_prompt(memory_dir: Path, route: Route) -> str:
    fb = _feedback_path(memory_dir, route)
    if route == "creator":
        notes_intro = (memory_dir / "env_creation_notes" / "prompt.md").as_posix()
        return (
            f"please read @{fb} carefully — this is expert feedback from a "
            f"domain expert that you MUST follow. Also read @{notes_intro} "
            f"so you have the env contract in mind. "
            f"Do not enter plan mode or ask me for any input at any time."
        )
    audit_prompt = (memory_dir / "audit_prompt.md").as_posix()
    return (
        f"please read @{fb} carefully — this is expert feedback from a "
        f"domain expert that you MUST treat as additional audit checklist "
        f"items. Also read @{audit_prompt} for the standard checklist. "
        f"Do not enter plan mode or ask me for any input at any time."
    )


def _edit_prompt(env_dir: str, route: Route) -> str:
    env_root = f"benchmarks/cua_world/environments/{env_dir}"
    if route == "creator":
        return (
            f"Now refactor the existing env at @{env_root}/ based on the expert "
            f"feedback you just read. Scan the expert feedback for entries that "
            f"apply to env `{env_dir}` (matching env_dir or marked GLOBAL).\n\n"
            f"HARD CONSTRAINTS:\n"
            f"  - You MUST edit files inside {env_root}/ in place. Do NOT "
            f"create a new env folder. Do NOT touch other envs.\n"
            f"  - You MUST keep the env id in env.json stable.\n"
            f"  - If the feedback says 'use real data', that means real data "
            f"FROM REAL SOURCES — not built-in demo modules, not synthetic "
            f"Python lists. Replace the seeding logic in scripts/setup_*.sh "
            f"to download / pull from a public source and cite the URL.\n"
            f"  - DO NOT modify task folders under {env_root}/tasks/ in this "
            f"pass — that's the edit_task driver's job. This pass is about "
            f"the env itself: install/setup scripts, config/, env.json.\n"
            f"  - After your edits, run the env (use the gym-anything runner) "
            f"and verify the post_start state matches the feedback. Save "
            f"evidence under evidence_docs/.\n\n"
            f"Files you may need to edit:\n"
            f"  - {env_root}/env.json                       (resources, hooks)\n"
            f"  - {env_root}/scripts/install_*.sh           (install software + deps)\n"
            f"  - {env_root}/scripts/setup_*.sh             (configure + seed data)\n"
            f"  - {env_root}/config/                        (data fixtures)\n"
            f"  - {env_root}/README.md                      (rewrite to match)\n"
            f"\n"
            f"(Unrelated Context: remember to use the visual_grounding MCP tool "
            f"to interact with the running environment.)"
        )
    # audit route
    audits_file = f"audits/audit_{env_dir}.md"
    return (
        f"Now audit the existing env at @{env_root}/ against the expert "
        f"feedback you just read PLUS the standard checklist. Find every "
        f"way the env violates the expert's guidance and the standard "
        f"checklist items. Write the full audit report to {audits_file} "
        f"(replacing any existing file). Cite specific files and lines, "
        f"and reference the expert_feedback.md entry timestamps that "
        f"triggered each finding. Do NOT modify the env itself in this "
        f"pass — only produce the audit report."
    )


def _nudge_prompt(env_dir: str, route: Route) -> str:
    env_root = f"benchmarks/cua_world/environments/{env_dir}"
    if route == "creator":
        return (
            f"reread the expert feedback you read earlier. The env at "
            f"@{env_root}/ is not yet fully addressing the feedback. Go "
            f"through each requirement and confirm it is reflected in the "
            f"scripts and config. If anything is missing, add it now — but "
            f"DO NOT create new env folders or touch task folders. "
            f"(Unrelated Context: remember to use the visual_grounding MCP "
            f"tool to interact with the running environment.)"
        )
    return (
        f"reread the expert feedback you read earlier. The audit you "
        f"wrote to audits/audit_{env_dir}.md may have missed items. Go "
        f"through each entry in expert_feedback that applies to this env "
        f"or is GLOBAL, and confirm every concern is reflected in your "
        f"audit. Append findings if anything was missed."
    )


def run(
    target_env_dir: str,
    *,
    route: Route,
    workspace: Path,
    logs_dir: Path,
    memory_dir: Optional[Path] = None,
    claude_bin: Optional[str] = None,
    model: Optional[str] = None,
    start_idx: int = 0,
    session_id: Optional[str] = None,
    timeout: int = CLAUDE_TIMEOUT,
) -> str:
    """Run the env editor / focused auditor. Returns the session id."""
    if route not in ("creator", "audit"):
        raise ValueError(f"route must be 'creator' or 'audit'; got {route!r}")

    binary = _resolve_bin(claude_bin, "CLAUDE_BIN", "claude")
    memory = (memory_dir or _packaged_memory_dir()).resolve()
    env_root = (
        workspace
        / "benchmarks"
        / "cua_world"
        / "environments"
        / target_env_dir
    )
    if not env_root.is_dir():
        raise RuntimeError(
            f"Env directory does not exist: {env_root}. Use the creation_audit "
            f"driver to create new envs."
        )

    logs_dir.mkdir(parents=True, exist_ok=True)
    session_id = session_id or str(uuid.uuid4())

    print(f"Session ID: {session_id}")
    log_path = logs_dir / f"{target_env_dir}__{route}.txt"
    log_path.write_text(
        f"Session ID: {session_id}\n"
        f"Target Env Directory: {target_env_dir}\n"
        f"Route: {route}\n"
        f"Start Index: {start_idx}\n"
        f"Memory dir: {memory}\n"
        f"Feedback file: {_feedback_path(memory, route)}\n"
    )

    def append_log(line: str) -> None:
        with log_path.open("a") as fh:
            fh.write(line + "\n")

    extra_model_args: List[str] = []
    if model:
        extra_model_args = ["--model", model]

    # --- Step 1: Read feedback + supporting context ---
    if not start_idx > 0:
        print("\n=== Step 1: Read Expert Feedback ===")
        run_claude(
            binary,
            [
                "-p",
                _read_prompt(memory, route),
                "--dangerously-skip-permissions",
                "--session-id",
                session_id,
                "--disallowedTools",
                DISALLOWED_TOOLS,
                *extra_model_args,
            ],
            cwd=workspace,
            timeout=timeout,
        )
        append_log("Step 1 (Read Feedback) Completed")
    else:
        print("Resuming from previous session, skipping step 1")

    # --- Step 2: Edit env in place (or write audit report) ---
    if not start_idx > 1:
        phase = "Edit Env" if route == "creator" else "Audit Env"
        print(f"\n=== Step 2: {phase} ===")
        run_claude(
            binary,
            [
                "-p",
                _edit_prompt(target_env_dir, route),
                "--dangerously-skip-permissions",
                "--resume",
                session_id,
                "--disallowedTools",
                DISALLOWED_TOOLS,
                *extra_model_args,
            ],
            cwd=workspace,
            timeout=timeout,
        )
        append_log(f"Step 2 ({phase}) Completed")
    else:
        print("Resuming from previous session, skipping step 2")

    # --- Step 3: Blind nudge ---
    if not start_idx > 2:
        print("\n=== Step 3: Nudge ===")
        run_claude(
            binary,
            [
                "-p",
                _nudge_prompt(target_env_dir, route),
                "--dangerously-skip-permissions",
                "--resume",
                session_id,
                "--disallowedTools",
                DISALLOWED_TOOLS,
                *extra_model_args,
            ],
            cwd=workspace,
            timeout=timeout,
        )
        append_log("Step 3 (Nudge) Completed")
    else:
        print("Resuming from previous session, skipping step 3")

    print(f"\n=== Edit Env Complete ({route}) ===")
    print(f"Session ID: {session_id}")
    print(f"Env Directory: {target_env_dir}")
    return session_id


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Edit one existing env in place, or run a focused audit.",
    )
    parser.add_argument("target_env_dir", help="Env folder name (e.g. odoo_hr_env)")
    parser.add_argument(
        "--route",
        choices=("creator", "audit"),
        default="creator",
        help="creator = edit scripts/config; audit = only write audit report",
    )
    parser.add_argument("--start-idx", type=int, default=0)
    parser.add_argument("--session-id", default=None)
    parser.add_argument("--workspace", type=Path, default=Path.cwd())
    parser.add_argument("--logs-dir", type=Path, default=None)
    parser.add_argument("--claude-bin", default=None)
    parser.add_argument("--model", default=None)
    parser.add_argument("--timeout-sec", type=int, default=CLAUDE_TIMEOUT)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    workspace = args.workspace.resolve()
    logs_dir = (args.logs_dir or workspace / "edit_env_logs").resolve()
    run(
        target_env_dir=args.target_env_dir,
        route=args.route,
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
