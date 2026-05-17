"""Inspection service — surfaces curated env/task views for the UI.

The inspector reads the on-disk artifacts that the creation-audit and
propose-and-amplify pipelines produce (env.json, task.json, scripts,
audit reports, evidence docs) and exposes them in a stable shape the
frontend can render without knowing the disk layout.

Pure read. No mutations. Fails loud on missing required files.
"""

from __future__ import annotations

import enum
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from ..config import Settings


MAX_PREVIEW_BYTES = 64 * 1024  # 64 KB per artifact preview
DATA_DIR_NAMES = ("config", "data", "fixtures", "datasets")
EVIDENCE_DIR_NAME = "evidence_docs"


# ----------------------------------------------------------------------
# Result shapes
# ----------------------------------------------------------------------


class ArtifactKind(str, enum.Enum):
    SHELL = "shell"
    PYTHON = "python"
    JSON = "json"
    YAML = "yaml"
    MARKDOWN = "markdown"
    IMAGE = "image"
    DATA = "data"
    OTHER = "other"


@dataclass
class Artifact:
    name: str
    rel_path: str  # relative to repo root
    role: str
    kind: ArtifactKind
    size_bytes: int

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "rel_path": self.rel_path,
            "role": self.role,
            "kind": self.kind.value,
            "size_bytes": self.size_bytes,
        }


@dataclass
class ExternalSource:
    """A URL discovered in install/setup scripts — likely a dataset."""

    url: str
    discovered_in: str  # rel_path of the script

    def to_dict(self) -> dict:
        return {"url": self.url, "discovered_in": self.discovered_in}


@dataclass
class TaskSummary:
    task_id: str
    env_dir: str
    description: str | None
    difficulty: str | None
    success_mode: str | None
    has_vlm_checklist: bool

    def to_dict(self) -> dict:
        return {
            "task_id": self.task_id,
            "env_dir": self.env_dir,
            "description": self.description,
            "difficulty": self.difficulty,
            "success_mode": self.success_mode,
            "has_vlm_checklist": self.has_vlm_checklist,
        }


@dataclass
class SoftwareEntry:
    env_dir: str
    spec_id: str
    description: str | None
    tags: list[str]
    runner: str | None
    task_count: int

    def to_dict(self) -> dict:
        return {
            "env_dir": self.env_dir,
            "spec_id": self.spec_id,
            "description": self.description,
            "tags": list(self.tags),
            "runner": self.runner,
            "task_count": self.task_count,
        }


@dataclass
class AuditReport:
    rel_path: str
    size_bytes: int
    snippet: str  # first ~1000 chars

    def to_dict(self) -> dict:
        return {
            "rel_path": self.rel_path,
            "size_bytes": self.size_bytes,
            "snippet": self.snippet,
        }


@dataclass
class EnvView:
    env_dir: str
    spec_id: str
    description: str | None
    tags: list[str]
    runner: str | None
    base_preset: str | None
    artifacts: list[Artifact] = field(default_factory=list)
    data_files: list[Artifact] = field(default_factory=list)
    external_sources: list[ExternalSource] = field(default_factory=list)
    evidence_docs: list[Artifact] = field(default_factory=list)
    audit_report: AuditReport | None = None
    tasks: list[TaskSummary] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "env_dir": self.env_dir,
            "spec_id": self.spec_id,
            "description": self.description,
            "tags": list(self.tags),
            "runner": self.runner,
            "base_preset": self.base_preset,
            "artifacts": [a.to_dict() for a in self.artifacts],
            "data_files": [a.to_dict() for a in self.data_files],
            "external_sources": [s.to_dict() for s in self.external_sources],
            "evidence_docs": [a.to_dict() for a in self.evidence_docs],
            "audit_report": self.audit_report.to_dict() if self.audit_report else None,
            "tasks": [t.to_dict() for t in self.tasks],
        }


@dataclass
class TaskView:
    env_dir: str
    task_id: str
    description: str | None
    difficulty: str | None
    success_mode: str | None
    natural_language: str | None
    max_steps: int | None
    timeout_sec: int | None
    artifacts: list[Artifact] = field(default_factory=list)
    vlm_checklist_present: bool = False
    data_files: list[Artifact] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "env_dir": self.env_dir,
            "task_id": self.task_id,
            "description": self.description,
            "difficulty": self.difficulty,
            "success_mode": self.success_mode,
            "natural_language": self.natural_language,
            "max_steps": self.max_steps,
            "timeout_sec": self.timeout_sec,
            "artifacts": [a.to_dict() for a in self.artifacts],
            "vlm_checklist_present": self.vlm_checklist_present,
            "data_files": [a.to_dict() for a in self.data_files],
        }


@dataclass
class ArtifactContent:
    rel_path: str
    kind: ArtifactKind
    size_bytes: int
    text: str | None
    truncated: bool

    def to_dict(self) -> dict:
        return {
            "rel_path": self.rel_path,
            "kind": self.kind.value,
            "size_bytes": self.size_bytes,
            "text": self.text,
            "truncated": self.truncated,
        }


# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------


_URL_RE = re.compile(r"https?://[\w\-./%?=&:#~+]+", re.IGNORECASE)


def _classify(path: Path) -> ArtifactKind:
    name = path.name.lower()
    if name.endswith((".sh", ".bash", ".zsh", ".bat", ".cmd", ".ps1")):
        return ArtifactKind.SHELL
    if name.endswith(".py"):
        return ArtifactKind.PYTHON
    if name.endswith(".json"):
        return ArtifactKind.JSON
    if name.endswith((".yaml", ".yml")):
        return ArtifactKind.YAML
    if name.endswith(".md"):
        return ArtifactKind.MARKDOWN
    if name.endswith((".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff")):
        return ArtifactKind.IMAGE
    if name.endswith(
        (
            ".csv",
            ".tsv",
            ".parquet",
            ".pkl",
            ".pickle",
            ".sqlite",
            ".db",
            ".xml",
            ".xlsx",
        )
    ):
        return ArtifactKind.DATA
    return ArtifactKind.OTHER


def _rel(path: Path, repo_root: Path) -> str:
    return path.resolve().relative_to(repo_root).as_posix()


def _load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise InspectionError(f"Malformed JSON at {path}: {exc}") from exc


def _scan_urls(scripts: Iterable[Path], repo_root: Path) -> list[ExternalSource]:
    found: dict[str, ExternalSource] = {}
    for script in scripts:
        if not script.is_file():
            continue
        try:
            text = script.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for match in _URL_RE.finditer(text):
            url = match.group(0).rstrip(").,;\"'")
            if url.startswith(("https://localhost", "http://localhost")):
                continue
            if url in found:
                continue
            found[url] = ExternalSource(url=url, discovered_in=_rel(script, repo_root))
    return list(found.values())


# ----------------------------------------------------------------------
# Errors
# ----------------------------------------------------------------------


class InspectionError(RuntimeError):
    """Raised when the on-disk artifacts violate the env/task contract."""


# ----------------------------------------------------------------------
# Service
# ----------------------------------------------------------------------


class InspectionService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.repo_root = settings.repo_root
        self.envs_dir = settings.environments_dir
        self.audits_dir = settings.audits_dir

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def list_software(self) -> list[SoftwareEntry]:
        if not self.envs_dir.is_dir():
            raise InspectionError(f"Environments directory missing: {self.envs_dir}")
        entries: list[SoftwareEntry] = []
        for env_path in sorted(self.envs_dir.iterdir()):
            if not env_path.is_dir():
                continue
            if env_path.name.startswith((".", "__")):
                continue
            env_json = env_path / "env.json"
            if not env_json.is_file():
                # An env folder must declare env.json. Anything else
                # under benchmarks/cua_world/environments is malformed.
                continue
            spec = _load_json(env_json)
            tasks_dir = env_path / "tasks"
            task_count = (
                len([p for p in tasks_dir.iterdir() if p.is_dir()])
                if tasks_dir.is_dir()
                else 0
            )
            entries.append(
                SoftwareEntry(
                    env_dir=env_path.name,
                    spec_id=str(spec.get("id", env_path.name)),
                    description=spec.get("description"),
                    tags=list(spec.get("tags") or []),
                    runner=spec.get("runner") or spec.get("base"),
                    task_count=task_count,
                )
            )
        return entries

    def list_tasks(self, env_dir: str) -> list[TaskSummary]:
        env_path = self._require_env_dir(env_dir)
        tasks_dir = env_path / "tasks"
        if not tasks_dir.is_dir():
            return []
        out: list[TaskSummary] = []
        for task_path in sorted(tasks_dir.iterdir()):
            if not task_path.is_dir() or task_path.name.startswith((".", "__")):
                continue
            task_json = task_path / "task.json"
            if not task_json.is_file():
                continue
            spec = _load_json(task_json)
            success = spec.get("success") or {}
            out.append(
                TaskSummary(
                    task_id=task_path.name,
                    env_dir=env_dir,
                    description=spec.get("description"),
                    difficulty=spec.get("difficulty"),
                    success_mode=success.get("mode") if isinstance(success, dict) else None,
                    has_vlm_checklist=(task_path / "vlm_checklist.json").is_file(),
                )
            )
        return out

    def get_env_view(self, env_dir: str) -> EnvView:
        env_path = self._require_env_dir(env_dir)
        spec = _load_json(env_path / "env.json")

        artifacts: list[Artifact] = []
        artifacts.append(self._artifact(env_path / "env.json", role="env_spec"))

        scripts_dir = env_path / "scripts"
        script_paths: list[Path] = []
        if scripts_dir.is_dir():
            for script in sorted(scripts_dir.iterdir()):
                if not script.is_file():
                    continue
                role = "install_script" if "install" in script.name else (
                    "setup_script" if "setup" in script.name else "script"
                )
                artifacts.append(self._artifact(script, role=role))
                script_paths.append(script)

        readme = env_path / "README.md"
        if readme.is_file():
            artifacts.append(self._artifact(readme, role="readme"))

        data_files = self._collect_data_files(env_path)
        external_sources = _scan_urls(script_paths, self.repo_root)
        evidence = self._collect_evidence(env_path)
        audit = self._collect_audit(env_dir)
        tasks = self.list_tasks(env_dir)

        return EnvView(
            env_dir=env_dir,
            spec_id=str(spec.get("id", env_dir)),
            description=spec.get("description"),
            tags=list(spec.get("tags") or []),
            runner=spec.get("runner"),
            base_preset=spec.get("base"),
            artifacts=artifacts,
            data_files=data_files,
            external_sources=external_sources,
            evidence_docs=evidence,
            audit_report=audit,
            tasks=tasks,
        )

    def get_task_view(self, env_dir: str, task_id: str) -> TaskView:
        env_path = self._require_env_dir(env_dir)
        task_path = env_path / "tasks" / task_id
        if not task_path.is_dir():
            raise InspectionError(f"Task folder not found: {task_path}")
        task_json = task_path / "task.json"
        if not task_json.is_file():
            raise InspectionError(f"task.json missing at {task_json}")
        spec = _load_json(task_json)
        init = spec.get("init") or {}
        success = spec.get("success") or {}

        artifacts: list[Artifact] = [self._artifact(task_json, role="task_spec")]
        for name, role in (
            ("setup_task.sh", "task_setup"),
            ("export_result.sh", "task_export"),
            ("verifier.py", "verifier"),
            ("vlm_checklist.json", "vlm_checklist"),
            ("validated_pi.json", "privileged_info"),
            ("README.md", "readme"),
        ):
            path = task_path / name
            if path.is_file():
                artifacts.append(self._artifact(path, role=role))

        data_files: list[Artifact] = []
        for entry in sorted(task_path.iterdir()):
            if entry.is_file() and _classify(entry) == ArtifactKind.DATA:
                data_files.append(self._artifact(entry, role="data"))

        return TaskView(
            env_dir=env_dir,
            task_id=task_id,
            description=spec.get("description"),
            difficulty=spec.get("difficulty"),
            success_mode=success.get("mode") if isinstance(success, dict) else None,
            natural_language=spec.get("natural_language") if isinstance(
                spec.get("natural_language"), str
            ) else None,
            max_steps=init.get("max_steps") if isinstance(init, dict) else None,
            timeout_sec=init.get("timeout_sec") if isinstance(init, dict) else None,
            artifacts=artifacts,
            vlm_checklist_present=(task_path / "vlm_checklist.json").is_file(),
            data_files=data_files,
        )

    def get_artifact_content(self, rel_path: str) -> ArtifactContent:
        path = self._resolve_artifact_path(rel_path)
        kind = _classify(path)
        size = path.stat().st_size
        truncated = False
        text: str | None = None
        if kind == ArtifactKind.IMAGE or size > MAX_PREVIEW_BYTES * 4:
            text = None
        else:
            raw = path.read_bytes()
            if len(raw) > MAX_PREVIEW_BYTES:
                raw = raw[:MAX_PREVIEW_BYTES]
                truncated = True
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                text = raw.decode("utf-8", errors="replace")
                truncated = True
        return ArtifactContent(
            rel_path=_rel(path, self.repo_root),
            kind=kind,
            size_bytes=size,
            text=text,
            truncated=truncated,
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _require_env_dir(self, env_dir: str) -> Path:
        if "/" in env_dir or env_dir.startswith("."):
            raise InspectionError(f"Invalid env_dir: {env_dir}")
        path = self.envs_dir / env_dir
        if not path.is_dir():
            raise InspectionError(f"Environment not found: {env_dir}")
        return path

    def _resolve_artifact_path(self, rel_path: str) -> Path:
        candidate = (self.repo_root / rel_path).resolve()
        try:
            candidate.relative_to(self.repo_root.resolve())
        except ValueError as exc:
            raise InspectionError(f"Artifact escapes repo root: {rel_path}") from exc
        if not candidate.is_file():
            raise InspectionError(f"Artifact not found: {rel_path}")
        return candidate

    def _artifact(self, path: Path, *, role: str) -> Artifact:
        stat = path.stat()
        return Artifact(
            name=path.name,
            rel_path=_rel(path, self.repo_root),
            role=role,
            kind=_classify(path),
            size_bytes=stat.st_size,
        )

    def _collect_data_files(self, env_path: Path) -> list[Artifact]:
        out: list[Artifact] = []
        for name in DATA_DIR_NAMES:
            d = env_path / name
            if not d.is_dir():
                continue
            for path in sorted(d.rglob("*")):
                if not path.is_file():
                    continue
                out.append(self._artifact(path, role="data"))
        return out

    def _collect_evidence(self, env_path: Path) -> list[Artifact]:
        d = env_path / EVIDENCE_DIR_NAME
        if not d.is_dir():
            return []
        out: list[Artifact] = []
        for path in sorted(d.rglob("*")):
            if not path.is_file():
                continue
            out.append(self._artifact(path, role="evidence"))
        return out

    def _collect_audit(self, env_dir: str) -> AuditReport | None:
        if not self.audits_dir.is_dir():
            return None
        candidate = self.audits_dir / f"audit_{env_dir}.md"
        if not candidate.is_file():
            return None
        size = candidate.stat().st_size
        snippet = candidate.read_text(encoding="utf-8", errors="replace")[:2000]
        return AuditReport(
            rel_path=_rel(candidate, self.repo_root),
            size_bytes=size,
            snippet=snippet,
        )


__all__ = [
    "InspectionService",
    "InspectionError",
    "Artifact",
    "ArtifactKind",
    "ArtifactContent",
    "EnvView",
    "TaskView",
    "TaskSummary",
    "SoftwareEntry",
    "ExternalSource",
    "AuditReport",
]
