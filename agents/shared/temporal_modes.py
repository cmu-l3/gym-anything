"""Shared temporal-mode contract for computer-use agents."""

from __future__ import annotations


TEMPORAL_MODES = (
    "paused",
    "live",
    "live_timestamped",
    "live_timestamped_execution",
)
DEFAULT_TEMPORAL_MODE = "live"


def validate_temporal_mode(mode: str | None) -> str:
    value = mode or DEFAULT_TEMPORAL_MODE
    if value not in TEMPORAL_MODES:
        choices = ", ".join(TEMPORAL_MODES)
        raise ValueError(f"temporal_mode must be one of {choices}; got {value!r}")
    return value


def world_time_mode(mode: str) -> str:
    return "paused" if validate_temporal_mode(mode) == "paused" else "live"


def timestamps_enabled(mode: str) -> bool:
    return validate_temporal_mode(mode) in {
        "live_timestamped",
        "live_timestamped_execution",
    }


def scheduled_execution_enabled(mode: str) -> bool:
    return validate_temporal_mode(mode) == "live_timestamped_execution"
