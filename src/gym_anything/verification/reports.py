from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Literal, Optional


Severity = Literal["error", "warning", "info"]
RecordKind = Literal["env", "task"]


@dataclass
class VerificationIssue:
    code: str
    message: str
    severity: Severity = "error"
    path: Optional[str] = None


@dataclass
class VerificationRecord:
    kind: RecordKind
    path: str
    spec_id: Optional[str] = None
    issues: List[VerificationIssue] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not any(issue.severity == "error" for issue in self.issues)


@dataclass
class VerificationSummary:
    scope: str
    root: str
    records: List[VerificationRecord] = field(default_factory=list)

    @property
    def total_records(self) -> int:
        return len(self.records)

    @property
    def error_count(self) -> int:
        return sum(
            1
            for record in self.records
            for issue in record.issues
            if issue.severity == "error"
        )

    @property
    def warning_count(self) -> int:
        return sum(
            1
            for record in self.records
            for issue in record.issues
            if issue.severity == "warning"
        )

    @property
    def failed_records(self) -> int:
        return sum(1 for record in self.records if not record.ok)

    @property
    def ok(self) -> bool:
        return self.failed_records == 0

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class TaskPipelineVerificationResult:
    env_dir: str
    task_id: str
    ok: bool
    stage: str
    episode_dir: Optional[str] = None
    verifier: Optional[Dict[str, Any]] = None
    error: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def render_summary_text(summary: VerificationSummary) -> str:
    lines = [
        f"Scope: {summary.scope}",
        f"Root: {summary.root}",
        f"Records: {summary.total_records}",
        f"Failed records: {summary.failed_records}",
        f"Errors: {summary.error_count}",
        f"Warnings: {summary.warning_count}",
    ]
    for record in summary.records:
        status = "OK" if record.ok else "FAIL"
        label = record.spec_id or record.path
        lines.append(f"[{status}] {record.kind}: {label}")
        for issue in record.issues:
            loc = f" ({issue.path})" if issue.path else ""
            lines.append(f"  - {issue.severity}:{issue.code}{loc}: {issue.message}")
    return "\n".join(lines)


def render_task_pipeline_result_text(result: TaskPipelineVerificationResult) -> str:
    lines = [
        f"Environment: {result.env_dir}",
        f"Task: {result.task_id}",
        f"Stage: {result.stage}",
        f"Status: {'OK' if result.ok else 'FAIL'}",
    ]
    if result.episode_dir:
        lines.append(f"Episode dir: {result.episode_dir}")
    if result.verifier is not None:
        lines.append(f"Verifier: {result.verifier}")
    if result.error:
        lines.append(f"Error: {result.error}")
    return "\n".join(lines)


__all__ = [
    "TaskPipelineVerificationResult",
    "VerificationIssue",
    "VerificationRecord",
    "VerificationSummary",
    "render_summary_text",
    "render_task_pipeline_result_text",
]
