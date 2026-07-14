from __future__ import annotations

import json
import os
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:  # Package import in tests; local import when the dashboard is executed directly.
    from .catalog import REPO_ROOT, environment_index
except ImportError:  # pragma: no cover - exercised by the script entrypoint.
    from catalog import REPO_ROOT, environment_index  # type: ignore[no-redef]


REVIEW_STATUSES = ("pending", "looks_good", "approved", "revision_requested")
RESEARCH_ROOT = Path(os.environ.get("CAPTCHA_BENCH_RESEARCH_ROOT", REPO_ROOT.parent / "research")).expanduser().resolve()
LEGACY_REVIEW_PATH = (RESEARCH_ROOT / "collection" / "environment-reviews.json").resolve()
LOCAL_REVIEW_PATH = (Path.home() / ".captcha-bench" / "environment-reviews.json").resolve()
DEFAULT_REVIEW_PATH = Path(os.environ.get(
    "CAPTCHA_BENCH_REVIEW_PATH",
    LEGACY_REVIEW_PATH if LEGACY_REVIEW_PATH.is_file() else LOCAL_REVIEW_PATH,
)).expanduser().resolve()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _reviewable_environments() -> dict[str, dict[str, Any]]:
    return {
        environment_id: environment
        for environment_id, environment in environment_index().items()
        if environment.get("stage") == "built"
    }


def _normalized_record(environment_id: str, value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    status = str(value.get("status") or "pending")
    if status not in REVIEW_STATUSES:
        status = "pending"
    note = str(value.get("note") or "")
    history: list[dict[str, str]] = []
    raw_history = value.get("history")
    if isinstance(raw_history, list):
        for entry in raw_history[-100:]:
            if not isinstance(entry, dict):
                continue
            entry_status = str(entry.get("status") or "pending")
            if entry_status not in REVIEW_STATUSES:
                continue
            history.append({
                "status": entry_status,
                "note": str(entry.get("note") or ""),
                "created_at": str(entry.get("created_at") or ""),
            })
    return {
        "environment_id": environment_id,
        "status": status,
        "note": note,
        "created_at": value.get("created_at"),
        "updated_at": value.get("updated_at"),
        "history": history,
    }


class EnvironmentReviewStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = (path or DEFAULT_REVIEW_PATH).expanduser().resolve()
        self._lock = threading.RLock()

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            payload = _read_json(self.path)
            raw_items = payload.get("items") if isinstance(payload.get("items"), dict) else {}
            reviewable = _reviewable_environments()
            items: dict[str, dict[str, Any]] = {}
            for environment_id, value in raw_items.items():
                environment_id = str(environment_id)
                if environment_id not in reviewable:
                    continue
                record = _normalized_record(environment_id, value)
                if record:
                    items[environment_id] = record
            approved = sum(record["status"] == "approved" for record in items.values())
            looks_good = sum(record["status"] == "looks_good" for record in items.values())
            revision_requested = sum(record["status"] == "revision_requested" for record in items.values())
            total = len(reviewable)
            decided = approved + revision_requested
            reviewed = decided + looks_good
            return {
                "version": 1,
                "updated_at": payload.get("updated_at"),
                "statuses": list(REVIEW_STATUSES),
                "stats": {
                    "total": total,
                    # ``reviewed`` includes a video/design screening. ``decided``
                    # is the stricter hands-on acceptance gate.
                    "reviewed": reviewed,
                    "decided": decided,
                    "pending": total - reviewed,
                    "hands_on_pending": total - decided,
                    "looks_good": looks_good,
                    "approved": approved,
                    "revision_requested": revision_requested,
                },
                "items": items,
            }

    def update(self, environment_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        environment = _reviewable_environments().get(environment_id)
        if environment is None:
            raise ValueError("unknown or non-reviewable environment")
        status = str(payload.get("status") or "pending")
        if status not in REVIEW_STATUSES:
            raise ValueError("invalid review status")
        note = str(payload.get("note") or "").strip()
        if len(note) > 5_000:
            raise ValueError("review note is too long")
        if status == "revision_requested" and not note:
            raise ValueError("revision requests require a note")

        with self._lock:
            existing_payload = _read_json(self.path)
            items = existing_payload.get("items") if isinstance(existing_payload.get("items"), dict) else {}
            previous = _normalized_record(environment_id, items.get(environment_id)) or {
                "environment_id": environment_id,
                "status": "pending",
                "note": "",
                "created_at": None,
                "updated_at": None,
                "history": [],
            }
            if previous["status"] == status and previous["note"] == note:
                return previous

            now = utc_now()
            history = list(previous.get("history") or [])
            history.append({"status": status, "note": note, "created_at": now})
            record = {
                "environment_id": environment_id,
                "status": status,
                "note": note,
                "created_at": previous.get("created_at") or now,
                "updated_at": now,
                "history": history[-100:],
            }
            items[environment_id] = record
            output = {"version": 1, "updated_at": now, "items": items}
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.path.with_suffix(self.path.suffix + ".tmp")
            temporary.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            temporary.replace(self.path)
            return record


__all__ = ["DEFAULT_REVIEW_PATH", "EnvironmentReviewStore", "REVIEW_STATUSES"]
