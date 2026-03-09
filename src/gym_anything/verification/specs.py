from __future__ import annotations

import importlib
import re
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

from ..config.presets import load_preset_env_dict
from ..config.validators import validate_env_spec, validate_task_spec
from ..specs import EnvSpec, TaskSpec
from ..utils.merge import deep_merge_env_dict
from ..utils.yaml import load_structured_file
from .imports import find_missing_imports, list_defined_functions
from .reports import VerificationIssue, VerificationRecord, VerificationSummary


def find_env_spec_path(env_dir: Path) -> Path:
    for candidate in (env_dir / "env.yaml", env_dir / "env.yml", env_dir / "env.json"):
        if candidate.exists():
            return candidate
    raise FileNotFoundError(f"No env spec found in {env_dir}")


def find_task_spec_paths(env_dir: Path, task_id: Optional[str] = None) -> List[Path]:
    tasks_dir = env_dir / "tasks"
    if not tasks_dir.exists():
        return []
    if task_id:
        candidates = [
            tasks_dir / task_id / "task.yaml",
            tasks_dir / task_id / "task.yml",
            tasks_dir / task_id / "task.json",
        ]
        return [candidate for candidate in candidates if candidate.exists()]
    task_paths: List[Path] = []
    for pattern in ("*/task.yaml", "*/task.yml", "*/task.json"):
        task_paths.extend(sorted(tasks_dir.glob(pattern)))
    return task_paths


def _compose_env_data(data: Dict[str, Any]) -> Dict[str, Any]:
    if data.get("base"):
        base = load_preset_env_dict(data["base"])
        return deep_merge_env_dict(base, data)
    return data


def _extract_script_names(command: Optional[str]) -> List[str]:
    if not command:
        return []
    matches = re.findall(r"([A-Za-z0-9_./\\\\:-]+\.(?:sh|ps1|py|bat|cmd))", command)
    return [Path(match.replace("\\", "/")).name for match in matches]


def _extract_script_refs(command: Optional[str]) -> List[str]:
    if not command:
        return []
    return re.findall(r"([A-Za-z0-9_./\\\\:-]+\.(?:sh|ps1|py|bat|cmd))", command)


def _candidate_source_paths(env_root: Path, source: str) -> List[Path]:
    path = Path(source)
    if path.is_absolute():
        return [path]

    candidates = [Path.cwd() / path]
    candidates.extend(ancestor / path for ancestor in env_root.parents)
    candidates.append(env_root / path)

    ordered: List[Path] = []
    seen = set()
    for candidate in candidates:
        resolved = str(candidate)
        if resolved in seen:
            continue
        seen.add(resolved)
        ordered.append(candidate)
    return ordered


def _mount_value(mount: Any, field: str) -> str:
    if isinstance(mount, dict):
        return str(mount.get(field, ""))
    return str(getattr(mount, field, "") or "")


def _target_aliases(target: str) -> List[str]:
    normalized = target.replace("\\", "/").rstrip("/")
    if not normalized:
        return []

    aliases = {normalized}
    if normalized.startswith("/"):
        aliases.add(f"C:{normalized}")
    elif re.match(r"^[A-Za-z]:/", normalized):
        drive_stripped = normalized[2:]
        if drive_stripped.startswith("/"):
            aliases.add(drive_stripped)
    return sorted(aliases, key=len, reverse=True)


def _resolve_mount_path(ref: str, env_root: Path, mounts: List[Any]) -> Optional[Path]:
    normalized_ref = ref.replace("\\", "/")
    normalized_ref_lower = normalized_ref.lower()

    best_match: Optional[tuple[str, Any]] = None
    for mount in mounts:
        target = _mount_value(mount, "target")
        target_aliases = _target_aliases(target)
        if not target_aliases:
            continue
        for alias in target_aliases:
            alias_lower = alias.lower()
            if normalized_ref_lower == alias_lower or normalized_ref_lower.startswith(alias_lower.rstrip("/") + "/"):
                if best_match is None or len(alias_lower) > len(best_match[0]):
                    best_match = (alias, mount)

    if best_match is None:
        return None

    matched_target, mount = best_match
    relative = normalized_ref[len(matched_target):].lstrip("/")
    for candidate_source in _candidate_source_paths(env_root, _mount_value(mount, "source")):
        candidate = candidate_source / relative if relative else candidate_source
        if candidate.exists():
            return candidate
    return None


def _load_env_spec(path: Path) -> EnvSpec:
    raw = load_structured_file(path)
    composed = _compose_env_data(raw)
    spec = EnvSpec.from_dict(composed)
    validate_env_spec(spec)
    return spec


def _record_error(record: VerificationRecord, code: str, message: str, path: Optional[Path] = None) -> None:
    record.issues.append(
        VerificationIssue(
            code=code,
            message=message,
            severity="error",
            path=str(path) if path else None,
        )
    )


def _check_hook_command_reference(
    record: VerificationRecord,
    hook_name: str,
    command: Optional[str],
    env_root: Path,
    task_root: Optional[Path] = None,
    mounts: Optional[List[Dict[str, Any]]] = None,
) -> None:
    refs = _extract_script_refs(command)
    if not refs:
        return

    missing: List[str] = []
    for ref in refs:
        normalized = ref.replace("\\", "/")
        candidate_paths: List[Path] = []
        mounted_path = _resolve_mount_path(normalized, env_root, mounts or [])
        if mounted_path is not None:
            candidate_paths.append(mounted_path)

        if "/workspace/" in normalized:
            workspace_rel = normalized.split("/workspace/", 1)[1].lstrip("/")
            candidate_paths.append(env_root / workspace_rel)
        elif normalized.startswith("tasks/"):
            candidate_paths.append(env_root / normalized)
        elif normalized.startswith("scripts/"):
            candidate_paths.append(env_root / normalized)
        else:
            path_obj = Path(normalized)
            if task_root is not None:
                candidate_paths.append(task_root / path_obj)
            candidate_paths.append(env_root / path_obj)

        if not any(candidate.exists() for candidate in candidate_paths):
            missing.append(normalized)

    if missing:
        missing_str = ", ".join(sorted(missing))
        _record_error(
            record,
            "missing_hook_reference",
            f"{hook_name} references missing script(s): {missing_str}",
            task_root or env_root,
        )


def _load_program_reference(ref: str, task_root: Path, env_root: Optional[Path]) -> None:
    if "::" in ref:
        file_name, func_name = ref.split("::", 1)
        file_path = task_root / file_name
        if not file_path.exists():
            raise FileNotFoundError(f"Program verifier file not found: {file_path}")
        functions = list_defined_functions(file_path)
        if func_name not in functions:
            raise AttributeError(f"Verifier function '{func_name}' not found in {file_path}")
        missing_imports = find_missing_imports(file_path, task_root=task_root, env_root=env_root)
        if missing_imports:
            missing = ", ".join(missing_imports)
            raise ImportError(f"Verifier depends on missing modules: {missing}")
        return
    if ":" in ref:
        module_name, func_name = ref.split(":", 1)
        if importlib.util.find_spec(module_name) is None:
            raise ImportError(f"Verifier module '{module_name}' is not importable")
        module = importlib.import_module(module_name)
        if not hasattr(module, func_name):
            raise AttributeError(f"Verifier function '{func_name}' not found in module {module_name}")
        return
    raise ValueError("Invalid program verifier reference")


def verify_env_spec_path(path: Path) -> VerificationRecord:
    record = VerificationRecord(kind="env", path=str(path))
    try:
        raw = load_structured_file(path)
    except Exception as exc:
        _record_error(record, "parse_error", str(exc), path)
        return record

    try:
        composed = _compose_env_data(raw)
        spec = EnvSpec.from_dict(composed)
        record.spec_id = spec.id
        validate_env_spec(spec)
    except Exception as exc:
        _record_error(record, "validation_error", str(exc), path)
        return record

    env_root = path.parent
    for hook_name, command in (spec.hooks or {}).items():
        _check_hook_command_reference(record, hook_name, command, env_root, mounts=spec.mounts)
    return record


def verify_task_spec_path(
    path: Path,
    env_root: Optional[Path] = None,
    env_spec: Optional[EnvSpec] = None,
) -> VerificationRecord:
    record = VerificationRecord(kind="task", path=str(path))
    try:
        raw = load_structured_file(path)
    except Exception as exc:
        _record_error(record, "parse_error", str(exc), path)
        return record

    task_root = path.parent
    try:
        spec = TaskSpec.from_dict(raw)
        record.spec_id = spec.id
        validate_task_spec(spec)
    except Exception as exc:
        _record_error(record, "validation_error", str(exc), path)
        return record

    _check_hook_command_reference(
        record,
        "pre_task",
        spec.hooks.pre_task,
        env_root or task_root,
        task_root=task_root,
        mounts=env_spec.mounts if env_spec else None,
    )
    _check_hook_command_reference(
        record,
        "post_task",
        spec.hooks.post_task,
        env_root or task_root,
        task_root=task_root,
        mounts=env_spec.mounts if env_spec else None,
    )

    mode = spec.success.mode
    success_spec = spec.success.spec or {}
    if mode == "program":
        target = success_spec if isinstance(success_spec, str) else success_spec.get("program") or success_spec.get("target")
        if not target:
            _record_error(record, "missing_program_verifier", "Program-mode task has no verifier target", path)
        else:
            try:
                _load_program_reference(str(target), task_root, env_root=env_root)
            except Exception as exc:
                _record_error(record, "invalid_program_verifier", str(exc), task_root)
    elif mode == "image_match":
        target = success_spec.get("target")
        if not target:
            _record_error(record, "missing_image_target", "Image-match task has no target image", path)
        elif not Path(target).is_absolute():
            candidate = task_root / target
            if not candidate.exists() and env_root is not None and not (env_root / target).exists():
                _record_error(
                    record,
                    "missing_image_target",
                    f"Relative image-match target '{target}' was not found under task or environment root",
                    task_root,
                )
    elif mode == "multi":
        program_spec = success_spec.get("program", {})
        target = program_spec if isinstance(program_spec, str) else program_spec.get("program") or program_spec.get("target")
        if target:
            try:
                _load_program_reference(str(target), task_root, env_root=env_root)
            except Exception as exc:
                _record_error(record, "invalid_program_verifier", str(exc), task_root)
        image_spec = success_spec.get("image_match", {})
        image_target = image_spec.get("target")
        if image_target and not Path(image_target).is_absolute():
            candidate = task_root / image_target
            if not candidate.exists() and env_root is not None and not (env_root / image_target).exists():
                _record_error(
                    record,
                    "missing_image_target",
                    f"Relative multi-mode image target '{image_target}' was not found under task or environment root",
                    task_root,
                )
    return record


def verify_environment_dir(env_dir: Path, task_id: Optional[str] = None) -> VerificationSummary:
    env_dir = Path(env_dir)
    summary = VerificationSummary(scope="environment", root=str(env_dir))
    env_spec: Optional[EnvSpec] = None

    try:
        env_spec_path = find_env_spec_path(env_dir)
    except Exception as exc:
        summary.records.append(
            VerificationRecord(
                kind="env",
                path=str(env_dir),
                issues=[VerificationIssue(code="missing_env_spec", message=str(exc), severity="error", path=str(env_dir))],
            )
        )
        return summary

    summary.records.append(verify_env_spec_path(env_spec_path))
    try:
        env_spec = _load_env_spec(env_spec_path)
    except Exception:
        env_spec = None
    for task_path in find_task_spec_paths(env_dir, task_id=task_id):
        summary.records.append(verify_task_spec_path(task_path, env_root=env_dir, env_spec=env_spec))
    return summary


def _iter_environment_dirs(root: Path) -> Iterable[Path]:
    if root.is_dir():
        try:
            find_env_spec_path(root)
        except FileNotFoundError:
            pass
        else:
            yield root
            return
    for child in sorted(root.iterdir()):
        if child.is_dir():
            try:
                find_env_spec_path(child)
            except FileNotFoundError:
                continue
            yield child


def verify_corpus(root: Path, max_failures: Optional[int] = None) -> VerificationSummary:
    root = Path(root)
    summary = VerificationSummary(scope="corpus", root=str(root))
    for env_dir in _iter_environment_dirs(root):
        env_summary = verify_environment_dir(env_dir)
        summary.records.extend(env_summary.records)
        if max_failures is not None and summary.failed_records >= max_failures:
            break
    return summary


__all__ = [
    "find_env_spec_path",
    "find_task_spec_paths",
    "verify_corpus",
    "verify_env_spec_path",
    "verify_environment_dir",
    "verify_task_spec_path",
]
