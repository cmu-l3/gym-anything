"""Runtime-mutable preferences for the expert console.

Preferences are settings that the user can change while the app is
running — primarily the summarization model and reasoning effort.
The (read-only) settings from `config.Settings` are unchanged: paths,
ports, environment variables.

Backed by a JSON file at `state/preferences.json`. Atomic writes.
"""

from __future__ import annotations

import json
import logging
import threading
from dataclasses import asdict, dataclass, fields, replace
from pathlib import Path
from typing import Any

from ..config import Settings


logger = logging.getLogger("expert_console.preferences")


_REASONING_EFFORTS = ("minimal", "low", "medium", "high")


@dataclass
class Preferences:
    """Runtime-mutable knobs. Defaults match Settings on first launch."""

    summarize_model: str = "gpt-5.4"
    summarize_reasoning_effort: str = "medium"
    summarize_max_frames: int = -1
    summarize_max_tokens: int = 8192
    summarize_timeout_sec: int = 120
    completion_threshold: float = 100.0
    integrity_threshold: float = 1.0

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class PreferencesError(RuntimeError):
    """Raised on invalid preferences input."""


class PreferencesService:
    """File-backed singleton for runtime preferences.

    Reads on every `get()` so the latest values are always served, and
    so a manual edit to `preferences.json` is picked up without a
    restart.
    """

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.path = settings.state_dir / "preferences.json"
        # RLock: `update()` calls `get()` while holding the lock.
        self._lock = threading.RLock()
        self._initial = self._load_defaults_from_settings(settings)

    def get(self) -> Preferences:
        with self._lock:
            if not self.path.is_file():
                return self._initial
            try:
                raw = json.loads(self.path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                raise PreferencesError(
                    f"preferences.json is corrupt: {exc}. "
                    f"Delete {self.path} to reset to defaults."
                ) from exc
            merged = asdict(self._initial)
            for key, value in raw.items():
                if key in merged:
                    merged[key] = value
            return Preferences(**merged)

    def update(self, patch: dict[str, Any]) -> Preferences:
        with self._lock:
            current = self.get()
            self._validate_patch(patch)
            updated = replace(current, **patch)
            tmp = self.path.with_suffix(".json.tmp")
            tmp.write_text(json.dumps(updated.to_dict(), indent=2), encoding="utf-8")
            tmp.replace(self.path)
            logger.info("preferences updated: %s", patch)
            return updated

    def reset(self) -> Preferences:
        with self._lock:
            if self.path.is_file():
                self.path.unlink()
            return self._initial

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _load_defaults_from_settings(self, settings: Settings) -> Preferences:
        return Preferences(
            summarize_model=settings.summarize_model,
            summarize_reasoning_effort=settings.summarize_reasoning_effort,
            summarize_timeout_sec=settings.summarize_timeout_sec,
        )

    def _validate_patch(self, patch: dict[str, Any]) -> None:
        allowed = {f.name for f in fields(Preferences)}
        unknown = set(patch) - allowed
        if unknown:
            raise PreferencesError(
                f"Unknown preference keys: {sorted(unknown)}. "
                f"Allowed: {sorted(allowed)}"
            )
        for key, value in patch.items():
            if key == "summarize_reasoning_effort":
                if value not in _REASONING_EFFORTS:
                    raise PreferencesError(
                        f"summarize_reasoning_effort must be one of "
                        f"{list(_REASONING_EFFORTS)}; got {value!r}"
                    )
            elif key == "summarize_model":
                if not isinstance(value, str) or not value.strip():
                    raise PreferencesError("summarize_model must be a non-empty string")
            elif key in {"summarize_max_frames", "summarize_max_tokens", "summarize_timeout_sec"}:
                if not isinstance(value, int):
                    raise PreferencesError(f"{key} must be an integer; got {type(value).__name__}")
            elif key in {"completion_threshold", "integrity_threshold"}:
                if not isinstance(value, (int, float)):
                    raise PreferencesError(f"{key} must be numeric; got {type(value).__name__}")
                if not 0.0 <= float(value) <= 100.0 and key == "completion_threshold":
                    raise PreferencesError("completion_threshold must be in [0, 100]")
                if key == "integrity_threshold" and not 0.0 <= float(value) <= 1.0:
                    raise PreferencesError("integrity_threshold must be in [0, 1]")


__all__ = [
    "Preferences",
    "PreferencesService",
    "PreferencesError",
]
