"""Pure-Python recovery logic. Imported by `recover/method.py`.

Lives in its own module because the dispatcher loads `method.py` via
`spec_from_file_location` and synthetic module names break dataclass
introspection; keeping the dataclasses + parsing in a normally-imported
package sidesteps that.
"""

from __future__ import annotations

import datetime as _dt
import json
import logging
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from extras.research.expert_console.server.config import Settings
from extras.research.expert_console.server.db import (
    init_db,
    session_scope,
)
from extras.research.expert_console.server.models import (
    AgentRun,
    Feedback,
    FeedbackRoute,
    MemoryTier as MemoryTierEnum,
    Pipeline as PipelineEnum,
    RunLog,
    RunStatus,
    Session as SessionRow,
    SessionStatus,
)


logger = logging.getLogger("expert_console.recover.core")


# ----------------------------------------------------------------------
# Shapes
# ----------------------------------------------------------------------


@dataclass
class FeedbackEntry:
    timestamp: _dt.datetime
    target_label: str
    env_dir: Optional[str]
    memory_tier: MemoryTierEnum
    body: str
    appended_to_path: str
    feedback_target: str  # "creator" | "audit" | "proposer"
    task_hint: Optional[str] = None

    @property
    def route(self) -> FeedbackRoute:
        if self.feedback_target == "audit":
            return FeedbackRoute.AUDIT
        return FeedbackRoute.CREATOR


@dataclass
class RunArtifact:
    log_path: Path
    started_at: _dt.datetime
    finished_at: _dt.datetime
    env_dir: str
    pipeline: PipelineEnum
    command: list
    task_id: Optional[str]
    succeeded: bool


@dataclass
class RecoveryPlan:
    feedbacks: list = field(default_factory=list)
    runs: list = field(default_factory=list)

    def summary(self) -> str:
        return f"{len(self.feedbacks)} feedback entries, {len(self.runs)} run artifacts"


# ----------------------------------------------------------------------
# Parsing
# ----------------------------------------------------------------------


_HEADER_RE = re.compile(
    r"^##\s+(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\s+—\s+(?P<rest>.*)$"
)
_ENV_LINE_RE = re.compile(r"Env folder:\s*(\S+)")
_TARGET_TASK_RE = re.compile(r"Target Task:\s*(\S+)")
_STAGES_RE = re.compile(r"Stages\s*:\s*(\S+)")


def _parse_iso_z(s: str) -> _dt.datetime:
    return _dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=_dt.timezone.utc
    )


def _classify_header(
    rest: str, known_envs
) -> tuple[str, Optional[str], MemoryTierEnum, Optional[str]]:
    rest = rest.strip()
    pieces = [p.strip() for p in rest.split(" — ")]
    head = pieces[0]
    rest_pieces = pieces[1:]

    if head == "GLOBAL":
        task = rest_pieces[0] if rest_pieces else None
        return ("GLOBAL", None, MemoryTierEnum.GENERAL, task)

    if head in known_envs:
        env_dir = head
        if rest_pieces and rest_pieces[0].lower() == "global":
            return (
                f"{env_dir} — global",
                env_dir,
                MemoryTierEnum.GENERAL,
                None,
            )
        return (env_dir, env_dir, MemoryTierEnum.SPECIFIC, None)

    return ("GLOBAL", None, MemoryTierEnum.GENERAL, None)


def _clean_body(body: str) -> str:
    lines = []
    for line in body.split("\n"):
        if line.strip().startswith("**Proposed checklist change.**"):
            continue
        lines.append(line)
    return "\n".join(lines).strip()


def parse_feedback_file(
    path: Path, feedback_target: str, known_envs
) -> list:
    if not path.is_file():
        return []
    text = path.read_text(encoding="utf-8", errors="replace")
    entries: list = []
    current_header = None
    current_body: list = []
    for line in text.splitlines():
        match = _HEADER_RE.match(line)
        if match:
            if current_header is not None:
                ts, rest = current_header
                label, env_dir, tier, task_hint = _classify_header(rest, known_envs)
                body = _clean_body("\n".join(current_body))
                if body:
                    entries.append(
                        FeedbackEntry(
                            timestamp=ts,
                            target_label=label,
                            env_dir=env_dir,
                            memory_tier=tier,
                            body=body,
                            appended_to_path=path.as_posix(),
                            feedback_target=feedback_target,
                            task_hint=task_hint,
                        )
                    )
            current_header = (_parse_iso_z(match.group("ts")), match.group("rest"))
            current_body = []
        elif current_header is not None:
            current_body.append(line)
    if current_header is not None:
        ts, rest = current_header
        label, env_dir, tier, task_hint = _classify_header(rest, known_envs)
        body = _clean_body("\n".join(current_body))
        if body:
            entries.append(
                FeedbackEntry(
                    timestamp=ts,
                    target_label=label,
                    env_dir=env_dir,
                    memory_tier=tier,
                    body=body,
                    appended_to_path=path.as_posix(),
                    feedback_target=feedback_target,
                    task_hint=task_hint,
                )
            )
    return entries


def parse_run_log(path: Path, known_envs) -> Optional[RunArtifact]:
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    env_dir: Optional[str] = None
    task_id: Optional[str] = None
    pipeline = PipelineEnum.PROPOSE_AND_AMPLIFY
    command: list = []

    m = _ENV_LINE_RE.search(text)
    if m:
        env_dir = Path(m.group(1).strip()).name

    m = _TARGET_TASK_RE.search(text)
    if m:
        task_id = m.group(1).strip()

    # If task wasn't explicit, scan the log for `tasks/<slug>/` references —
    # edit_task.py's prompt embeds the full task folder path, so any
    # task the agent worked on shows up multiple times.
    if task_id is None and env_dir is not None:
        task_path_re = re.compile(
            rf"environments/{re.escape(env_dir)}/tasks/(?P<task>[A-Za-z0-9_]+)"
        )
        counts: dict = {}
        for match in task_path_re.finditer(text):
            t = match.group("task")
            counts[t] = counts.get(t, 0) + 1
        if counts:
            # Most-mentioned task wins.
            task_id = max(counts.items(), key=lambda kv: kv[1])[0]

    if "edit_task" in text or "Edit Task" in text:
        pipeline = PipelineEnum.PROPOSE_AND_AMPLIFY
        command = [
            sys.executable,
            "-m",
            "extras.research.task_generation.propose_and_amplify.method",
            "--env-dir",
            env_dir or "?",
            "--stage",
            "edit",
        ]
        if task_id:
            command.extend(["--target-task", task_id])
    elif "Propose-and-Amplify" in text:
        pipeline = PipelineEnum.PROPOSE_AND_AMPLIFY
        stage = "all"
        sm = _STAGES_RE.search(text)
        if sm:
            stage = sm.group(1).strip()
        command = [
            sys.executable,
            "-m",
            "extras.research.task_generation.propose_and_amplify.method",
            "--env-dir",
            env_dir or "?",
            "--stage",
            stage,
        ]
    elif "creation_audit" in text or "Creation–Audit" in text:
        pipeline = PipelineEnum.CREATION_AUDIT
        command = [
            sys.executable,
            "-m",
            "extras.research.software_as_env.creation_audit.method",
            "--env-dir",
            env_dir or "?",
        ]
    elif "edit_env" in text or "Edit Env" in text:
        pipeline = PipelineEnum.CREATION_AUDIT
        command = [
            sys.executable,
            "-m",
            "extras.research.software_as_env.creation_audit.edit_env",
            env_dir or "?",
        ]

    if env_dir is None or env_dir not in known_envs:
        logger.warning("log %s has no resolvable env_dir; skipping", path.name)
        return None

    stat = path.stat()
    try:
        started_at = _dt.datetime.fromtimestamp(stat.st_birthtime, tz=_dt.timezone.utc)
    except AttributeError:
        started_at = _dt.datetime.fromtimestamp(stat.st_ctime, tz=_dt.timezone.utc)
    finished_at = _dt.datetime.fromtimestamp(stat.st_mtime, tz=_dt.timezone.utc)
    if finished_at <= started_at:
        finished_at = started_at + _dt.timedelta(seconds=1)

    succeeded = (
        "complete" in text.lower()
        or "Task Edit Complete" in text
        or "Edit Env Complete" in text
    )

    return RunArtifact(
        log_path=path,
        started_at=started_at,
        finished_at=finished_at,
        env_dir=env_dir,
        pipeline=pipeline,
        command=command,
        task_id=task_id,
        succeeded=succeeded,
    )


def _known_envs(settings: Settings):
    envs = settings.environments_dir
    if not envs.is_dir():
        return set()
    return {
        p.name
        for p in envs.iterdir()
        if p.is_dir() and not p.name.startswith((".", "__"))
    }


def gather(settings: Settings) -> RecoveryPlan:
    known_envs = _known_envs(settings)
    plan = RecoveryPlan()

    plan.feedbacks.extend(
        parse_feedback_file(
            settings.expert_feedback_creation_path,
            feedback_target="creator",
            known_envs=known_envs,
        )
    )
    plan.feedbacks.extend(
        parse_feedback_file(
            settings.expert_feedback_audit_path,
            feedback_target="audit",
            known_envs=known_envs,
        )
    )
    plan.feedbacks.extend(
        parse_feedback_file(
            settings.expert_feedback_propose_path,
            feedback_target="proposer",
            known_envs=known_envs,
        )
    )

    runs_dir = settings.artifacts_dir
    if runs_dir.is_dir():
        for log in sorted(runs_dir.glob("*.log")):
            artifact = parse_run_log(log, known_envs)
            if artifact is not None:
                plan.runs.append(artifact)

    plan.feedbacks.sort(key=lambda f: f.timestamp)
    plan.runs.sort(key=lambda r: r.started_at)
    return plan


def _match_feedback_to_run(feedbacks, run):
    best = None
    best_delta = None
    window = _dt.timedelta(hours=12)
    for fb in feedbacks:
        if fb.env_dir is not None and fb.env_dir != run.env_dir:
            continue
        if fb.timestamp > run.finished_at + _dt.timedelta(minutes=5):
            continue
        delta = abs(run.started_at - fb.timestamp)
        if delta > window:
            continue
        if best_delta is None or delta < best_delta:
            best_delta = delta
            best = fb
    return best


def _session_key(env_dir, task_id):
    return f"{env_dir or 'general'}::{task_id or '-'}"


def apply(plan: RecoveryPlan, settings: Settings):
    init_db(settings)
    inserted = {"sessions": 0, "feedbacks": 0, "runs": 0, "run_logs": 0}
    matched_feedback_ids = set()
    session_id_by_key: dict = {}

    with session_scope() as db:
        for run in plan.runs:
            fb_match = _match_feedback_to_run(plan.feedbacks, run)
            task_id = run.task_id or (fb_match.task_hint if fb_match else None)
            key = _session_key(run.env_dir, task_id)
            sess_id = session_id_by_key.get(key)
            if sess_id is None:
                title_extra = f"/{task_id}" if task_id else ""
                sess = SessionRow(
                    title=f"[recovered] {run.env_dir}{title_extra}",
                    env_dir=run.env_dir,
                    task_id=task_id,
                    status=SessionStatus.ARCHIVED.value,
                    created_at=run.started_at,
                    updated_at=run.finished_at,
                )
                db.add(sess)
                db.flush()
                session_id_by_key[key] = sess.id
                sess_id = sess.id
                inserted["sessions"] += 1

            feedback_id = None
            if fb_match is not None:
                fb_row = Feedback(
                    session_id=sess_id,
                    message=fb_match.body,
                    route=fb_match.route.value,
                    memory_tier=fb_match.memory_tier.value,
                    suggest_checklist_change=False,
                    env_dir=fb_match.env_dir,
                    task_id=task_id,
                    is_new_task=False,
                    appended_to_path=fb_match.appended_to_path,
                    entry_anchor=None,
                    dispatched=True,
                    created_at=fb_match.timestamp,
                )
                db.add(fb_row)
                db.flush()
                feedback_id = fb_row.id
                inserted["feedbacks"] += 1
                matched_feedback_ids.add(id(fb_match))

            run_row = AgentRun(
                session_id=sess_id,
                feedback_id=feedback_id,
                pipeline=run.pipeline.value,
                command=json.dumps(run.command),
                status=(
                    RunStatus.FINISHED.value if run.succeeded else RunStatus.FAILED.value
                ),
                exit_code=0 if run.succeeded else None,
                log_path=run.log_path.as_posix(),
                pid=None,
                pgid=None,
                current_phase=None,
                created_at=run.started_at,
                started_at=run.started_at,
                finished_at=run.finished_at,
            )
            db.add(run_row)
            db.flush()
            inserted["runs"] += 1

            try:
                lines = run.log_path.read_text(
                    encoding="utf-8", errors="replace"
                ).splitlines()
            except OSError:
                lines = []
            for seq, line in enumerate(lines):
                db.add(
                    RunLog(
                        run_id=run_row.id,
                        seq=seq,
                        stream="stdout",
                        line=line,
                        ts=run.started_at,
                    )
                )
                inserted["run_logs"] += 1

        for fb in plan.feedbacks:
            if id(fb) in matched_feedback_ids:
                continue
            key = _session_key(fb.env_dir, fb.task_hint)
            sess_id = session_id_by_key.get(key)
            if sess_id is None:
                sess = SessionRow(
                    title=(
                        f"[recovered] {fb.env_dir}"
                        if fb.env_dir
                        else "[recovered] general feedback"
                    ),
                    env_dir=fb.env_dir,
                    task_id=fb.task_hint,
                    status=SessionStatus.ARCHIVED.value,
                    created_at=fb.timestamp,
                    updated_at=fb.timestamp,
                )
                db.add(sess)
                db.flush()
                session_id_by_key[key] = sess.id
                sess_id = sess.id
                inserted["sessions"] += 1
            db.add(
                Feedback(
                    session_id=sess_id,
                    message=fb.body,
                    route=fb.route.value,
                    memory_tier=fb.memory_tier.value,
                    suggest_checklist_change=False,
                    env_dir=fb.env_dir,
                    task_id=fb.task_hint,
                    is_new_task=False,
                    appended_to_path=fb.appended_to_path,
                    entry_anchor=None,
                    dispatched=False,
                    created_at=fb.timestamp,
                )
            )
            inserted["feedbacks"] += 1

    return inserted


def print_plan(plan: RecoveryPlan) -> None:
    print()
    print(f"Recovery plan: {plan.summary()}")
    print()
    print("Feedbacks:")
    for i, fb in enumerate(plan.feedbacks):
        scope = (
            "SPECIFIC" if fb.memory_tier is MemoryTierEnum.SPECIFIC else "GENERAL"
        )
        env = fb.env_dir or "—"
        task = fb.task_hint or "—"
        body_snip = (fb.body[:80] + "…") if len(fb.body) > 80 else fb.body
        print(
            f"  [{i}] {fb.timestamp.isoformat()} env={env} task={task} scope={scope} "
            f"target={fb.feedback_target}"
        )
        print(f"      body: {body_snip}")
    print()
    print("Runs:")
    for i, run in enumerate(plan.runs):
        secs = int((run.finished_at - run.started_at).total_seconds())
        print(
            f"  [{i}] {run.started_at.isoformat()} → {run.finished_at.isoformat()} "
            f"({secs}s)"
        )
        print(
            f"      env={run.env_dir} task={run.task_id or '—'} "
            f"pipeline={run.pipeline.value} succeeded={run.succeeded}"
        )
        print(f"      log: {run.log_path.name}")
