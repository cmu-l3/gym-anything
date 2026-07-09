"""
Creation–Audit loop for converting a target software application into a
gym-anything environment, as described in §3 / Appendix E of the CUA-World
paper (Aggarwal et al., 2026).

The pipeline drives a coding+computer-use agent (Claude Code by default,
or Codex CLI as an alternative) through three phases for a single software:

  1. Initial attempt   — agent reads the creation prompt and authors
                         scripts/{install,setup}.sh, env.json, tasks/,
                         and produces evidence_docs/.
  2. Blind nudge ×N    — re-prompts the agent to recheck the creation
                         prompt; recovers omissions caused by context fatigue.
  3. Audit rounds ×M   — an independent agent reads the evidence against
                         the audit checklist and writes audit_<env>.md;
                         the creation agent then ingests that audit and
                         fixes issues.

This module is part of `gym-anything-extras` (research category) and depends
on the gym-anything library only by reading/writing files that conform to
the env.json / task.json contract. It does not import or modify any
gym_anything runtime code.

Invoked through:

    gym-anything-extras research software_as_env creation_audit \
        --software "Moodle" --env-dir moodle_env

or directly:

    python -m extras.research.software_as_env.creation_audit.method \
        --software "Moodle" --env-dir moodle_env
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


DEFAULT_TIMEOUT_SEC = 7200  # 2 hours per agent invocation
DISALLOWED_TOOLS = "AskUserQuestion,EnterPlanMode,ExitPlanMode,Task(Plan)"
DEFAULT_BLIND_NUDGES = 1
DEFAULT_AUDIT_ROUNDS = 2


# ---------------------------------------------------------------------------
# Process control
# ---------------------------------------------------------------------------


def _kill_process_group(pgid: int) -> None:
    """SIGTERM then SIGKILL an entire process group, ignoring already-dead pids."""
    try:
        os.killpg(pgid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        return
    time.sleep(2)
    try:
        os.killpg(pgid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


def _run_agent(
    binary: Path,
    args: List[str],
    timeout: int,
    cwd: Path,
    capture_stdout: bool = False,
) -> Optional[str]:
    """Run the agent CLI. If it doesn't exit (Bun runtime quirk), kill the
    process group after `timeout` seconds — we assume the agent finished.
    """
    pgid: Optional[int] = None
    stdout_data: Optional[str] = None
    try:
        proc = subprocess.Popen(
            [str(binary)] + args,
            cwd=str(cwd),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE if capture_stdout else None,
            stderr=subprocess.STDOUT if capture_stdout else None,
            start_new_session=True,
            text=True,
        )
        pgid = os.getpgid(proc.pid)
        try:
            if capture_stdout:
                stdout_data, _ = proc.communicate(timeout=timeout)
            else:
                proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            print(f"[creation_audit] agent did not exit after {timeout}s — assuming done, killing.")
            if capture_stdout and proc.stdout is not None:
                stdout_data = proc.stdout.read()
    finally:
        if pgid is not None:
            _kill_process_group(pgid)
    return stdout_data


# ---------------------------------------------------------------------------
# Backend wrappers
# ---------------------------------------------------------------------------


def _resolve_bin(explicit: Optional[str], env_var: str, name: str) -> Path:
    """Pick the agent binary in priority order: --flag > env var > PATH."""
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


def _claude_invoke(
    binary: Path,
    prompt: str,
    *,
    session_id: Optional[str],
    resume: bool,
    workspace: Path,
    timeout: int,
) -> None:
    args = ["-p", prompt, "--dangerously-skip-permissions",
            "--disallowedTools", DISALLOWED_TOOLS]
    if session_id is None:
        raise ValueError("Claude backend requires a session_id")
    args += (["--resume", session_id] if resume else ["--session-id", session_id])
    _run_agent(binary, args, timeout, cwd=workspace)


def _codex_invoke(
    binary: Path,
    prompt: str,
    *,
    session_id: Optional[str],
    resume: bool,
    workspace: Path,
    timeout: int,
) -> None:
    # Codex CLI argv layout: codex --yolo exec [resume <id>] "<prompt>"
    args = ["--yolo", "exec"]
    if session_id and resume:
        args += ["resume", session_id]
    args += [prompt]
    _run_agent(binary, args, timeout, cwd=workspace)


def _codex_new_session(binary: Path, workspace: Path, timeout: int = 60) -> str:
    """Bootstrap a Codex session and capture its session id from stdout."""
    out = _run_agent(
        binary, ["--yolo", "exec", "hi"], timeout, cwd=workspace, capture_stdout=True
    )
    if not out:
        raise RuntimeError("Codex did not return any output for session bootstrap")
    return out.strip()


# ---------------------------------------------------------------------------
# Pipeline phases
# ---------------------------------------------------------------------------


SUPPORTED_PLATFORMS = ("linux", "macos")


def _benchmark_root(platform: str) -> str:
    """Top-level benchmark dir for the chosen target platform.

    Linux envs live under benchmarks/cua_world/. macOS envs live under
    benchmarks/cua_world-macos/ (built on UseComputerRunner + the
    use.computer fleet — see env_creation_notes/12_macos_environments.md).
    """
    return "benchmarks/cua_world-macos" if platform == "macos" else "benchmarks/cua_world"


def _creation_prompt_path(memory_dir: Path, platform: str) -> str:
    """Per-platform creation prompt. Linux uses prompt.md; macOS uses
    prompt_macos.md (which references 12_macos_environments.md, base="macos",
    UseComputerRunner, /Users/lume/workspace paths, etc.)."""
    if platform == "macos":
        return (memory_dir / "env_creation_notes" / "prompt_macos.md").as_posix()
    return (memory_dir / "env_creation_notes" / "prompt.md").as_posix()


def _audit_prompt_path(memory_dir: Path, platform: str) -> str:
    """Per-platform audit prompt. macOS variant has the cua_world-macos path."""
    if platform == "macos":
        return (memory_dir / "audit_prompt_macos.md").as_posix()
    return (memory_dir / "audit_prompt.md").as_posix()


def _initial_prompt(software: str, env_dir: str, memory_dir: Path, platform: str) -> str:
    return (
        f"read @{_creation_prompt_path(memory_dir, platform)} and follow the prompt. "
        f"target application is {software} and target env directory is {env_dir}. "
        f"Do not enter plan mode (although you are strongly encouraged to plan "
        f"before making code edits), or ask me for any input at any time. "
        f"All information is already present in the prompt file."
    )


def _nudge_prompt(memory_dir: Path, platform: str) -> str:
    return (
        f"reread @{_creation_prompt_path(memory_dir, platform)}. "
        f"you haven't completed the task yet. (Unrelated Context: remember to "
        f"use the visual_grounding MCP tool to interact with the running "
        f"environment)"
    )


def _audit_explore_prompt() -> str:
    return "deep explore this repository to understand what it is about, " \
           "how each individual components work, etc"


def _audit_run_prompt(env_dir: str, audits_dir: Path, memory_dir: Path, platform: str) -> str:
    audit_file_rel = (audits_dir / f"audit_{env_dir}.md").as_posix()
    target_dir = f"{_benchmark_root(platform)}/environments/{env_dir}"
    return (
        f"read @{_audit_prompt_path(memory_dir, platform)} and follow the prompt. "
        f"target env directory is @{target_dir}. "
        f"Note: save file is {audit_file_rel}"
    )


def _audit_feedback_prompt(audit_text: str) -> str:
    return (
        f"An independent audit of your progress was performed. Here is the "
        f"audit: {audit_text}. Please fix the issues. (Unrelated Context: "
        f"remember to use the visual_grounding MCP tool to interact with the "
        f"running environment)"
    )


def run_creation_audit(
    *,
    software: str,
    env_dir: str,
    backend: str,
    platform: str,
    blind_nudges: int,
    audit_rounds: int,
    start_idx: int,
    session_id: Optional[str],
    workspace: Path,
    memory_dir: Path,
    audits_dir: Path,
    logs_dir: Path,
    claude_bin: Optional[str],
    codex_bin: Optional[str],
    timeout_sec: int,
) -> int:
    if platform not in SUPPORTED_PLATFORMS:
        raise ValueError(f"--platform must be one of {SUPPORTED_PLATFORMS}, got {platform!r}")
    audits_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    if backend == "cc":
        binary = _resolve_bin(claude_bin, "CLAUDE_BIN", "claude")
        invoke = lambda prompt, *, resume: _claude_invoke(
            binary, prompt, session_id=session_id, resume=resume,
            workspace=workspace, timeout=timeout_sec,
        )
        if session_id is None:
            session_id = str(uuid.uuid4())
    elif backend == "codex":
        binary = _resolve_bin(codex_bin, "CODEX_BIN", "codex")
        if session_id is None:
            session_id = _codex_new_session(binary, workspace)
        invoke = lambda prompt, *, resume: _codex_invoke(
            binary, prompt, session_id=session_id, resume=resume,
            workspace=workspace, timeout=timeout_sec,
        )
    else:
        raise ValueError(f"Unknown backend: {backend!r}; expected 'cc' or 'codex'")

    log_path = logs_dir / f"{env_dir}.txt"
    log_path.write_text(
        f"Session ID: {session_id}\n"
        f"Backend: {backend}\n"
        f"Platform: {platform}\n"
        f"Target Application: {software}\n"
        f"Target Env Directory: {env_dir} (under {_benchmark_root(platform)}/environments/)\n"
        f"Workspace: {workspace}\n"
        f"Audits Dir: {audits_dir}\n"
        f"Start Index: {start_idx}\n"
        f"Blind Nudges: {blind_nudges}\n"
        f"Audit Rounds: {audit_rounds}\n"
    )

    def append_log(line: str) -> None:
        with log_path.open("a") as fh:
            fh.write(line + "\n")

    # Phase 1: initial creation pass
    if start_idx <= 0:
        print("\n=== Initial Attempt ===")
        invoke(_initial_prompt(software, env_dir, memory_dir, platform), resume=False)
        append_log("Initial Attempt Completed")
    else:
        print(f"Resuming from index {start_idx}, skipping initial attempt")

    # Phase 2: blind nudges
    for i in range(blind_nudges):
        phase_idx = i + 1
        if start_idx > phase_idx:
            print(f"Skipping blind nudge {phase_idx}")
            continue
        print(f"\n=== Blind Nudge {phase_idx} ===")
        invoke(_nudge_prompt(memory_dir, platform), resume=True)
        append_log(f"Blind Nudge {phase_idx} Completed")

    # Phase 3: audit rounds with feedback
    for i in range(audit_rounds):
        phase_idx = blind_nudges + i + 1
        if start_idx > phase_idx:
            print(f"Skipping audit round {i + 1}")
            continue
        print(f"\n=== Audit Round {i + 1} ===")
        audit_session = str(uuid.uuid4())
        # The auditor uses its own fresh session so it can't see the
        # creation agent's chain-of-thought.
        if backend == "cc":
            _claude_invoke(
                binary, _audit_explore_prompt(),
                session_id=audit_session, resume=False,
                workspace=workspace, timeout=timeout_sec,
            )
            _claude_invoke(
                binary, _audit_run_prompt(env_dir, audits_dir, memory_dir, platform),
                session_id=audit_session, resume=True,
                workspace=workspace, timeout=timeout_sec,
            )
        else:
            _codex_invoke(
                binary, _audit_explore_prompt(),
                session_id=audit_session, resume=False,
                workspace=workspace, timeout=timeout_sec,
            )
            _codex_invoke(
                binary, _audit_run_prompt(env_dir, audits_dir, memory_dir, platform),
                session_id=audit_session, resume=True,
                workspace=workspace, timeout=timeout_sec,
            )

        audit_path = audits_dir / f"audit_{env_dir}.md"
        if not audit_path.exists():
            print(f"[creation_audit] audit file missing at {audit_path}; skipping feedback")
            append_log(f"Audit Round {i + 1} produced no audit file")
            continue
        audit_text = audit_path.read_text(encoding="utf-8")
        invoke(_audit_feedback_prompt(audit_text), resume=True)

        if i < audit_rounds - 1:
            # Remove the audit so the next round writes fresh evidence.
            try:
                audit_path.unlink()
            except OSError:
                pass
        append_log(f"Audit Round {i + 1} Completed")

    print(
        f"\nCreation–Audit complete: software={software}, env_dir={env_dir}, "
        f"session={session_id}"
    )
    return 0


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def _packaged_memory_dir() -> Path:
    return Path(__file__).resolve().parent / "memory"


def _default_workspace() -> Path:
    """Default to the gym-anything project root (4 levels up from this file)."""
    here = Path(__file__).resolve()
    candidate = here.parents[4]  # extras/research/software_as_env/creation_audit/method.py -> repo root
    return candidate if (candidate / "src" / "gym_anything").is_dir() else Path.cwd()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gym-anything-extras research software_as_env creation_audit",
        description="Run the creation–audit loop on one software target.",
    )
    parser.add_argument("--software", required=True, help="Human-readable software name (e.g. 'Moodle')")
    parser.add_argument("--env-dir", required=True, help="Target env folder name (e.g. 'moodle_env')")
    parser.add_argument("--platform", choices=SUPPORTED_PLATFORMS, default="linux",
                        help=("Target platform. 'linux' (default) → benchmarks/cua_world with "
                              "QEMU/Apptainer + ubuntu-gnome. 'macos' → benchmarks/cua_world-macos "
                              "with UseComputerRunner + the use.computer fleet (see "
                              "env_creation_notes/12_macos_environments.md). Selects per-platform "
                              "creation + audit prompts."))
    parser.add_argument("--backend", choices=("cc", "codex"), default="cc",
                        help="Agent backend: cc=Claude Code, codex=Codex CLI")
    parser.add_argument("--blind-nudges", type=int, default=DEFAULT_BLIND_NUDGES)
    parser.add_argument("--audit-rounds", type=int, default=DEFAULT_AUDIT_ROUNDS)
    parser.add_argument("--start-idx", type=int, default=0,
                        help="Resume from this phase index (0=initial, 1=first nudge, ...)")
    parser.add_argument("--session-id", default=None, help="Resume an existing agent session")
    parser.add_argument("--workspace", type=Path, default=None,
                        help="Path the agent operates from; defaults to the gym-anything repo root")
    parser.add_argument("--memory-dir", type=Path, default=None,
                        help="Override the packaged memory directory")
    parser.add_argument("--audits-dir", type=Path, default=None,
                        help="Where audit files are written; defaults to <workspace>/audits")
    parser.add_argument("--logs-dir", type=Path, default=None,
                        help="Where run logs are written; defaults to <workspace>/creation_audit_logs")
    parser.add_argument("--claude-bin", default=None, help="Path to claude CLI")
    parser.add_argument("--codex-bin", default=None, help="Path to codex CLI")
    parser.add_argument("--timeout-sec", type=int, default=DEFAULT_TIMEOUT_SEC,
                        help="Per-agent-invocation timeout in seconds (default 7200)")
    return parser


def run(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    workspace = (args.workspace or _default_workspace()).resolve()
    memory_dir = (args.memory_dir or _packaged_memory_dir()).resolve()
    audits_dir = (args.audits_dir or workspace / "audits").resolve()
    logs_dir = (args.logs_dir or workspace / "creation_audit_logs").resolve()

    return run_creation_audit(
        software=args.software,
        env_dir=args.env_dir,
        backend=args.backend,
        platform=args.platform,
        blind_nudges=args.blind_nudges,
        audit_rounds=args.audit_rounds,
        start_idx=args.start_idx,
        session_id=args.session_id,
        workspace=workspace,
        memory_dir=memory_dir,
        audits_dir=audits_dir,
        logs_dir=logs_dir,
        claude_bin=args.claude_bin,
        codex_bin=args.codex_bin,
        timeout_sec=args.timeout_sec,
    )


if __name__ == "__main__":
    raise SystemExit(run())
