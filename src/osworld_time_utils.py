from __future__ import annotations

import calendar
import copy
import re
from datetime import datetime, timedelta
from typing import Any


_WEEKDAYS = {day.lower(): index for index, day in enumerate(calendar.day_name)}


def _resolve_relative_time(expression: str, now: datetime | None = None) -> datetime:
    now = now or datetime.now()
    normalized = expression.strip().lower()

    if normalized == "tomorrow":
        return now + timedelta(days=1)
    if normalized == "this month":
        return now.replace(day=1)

    match = re.fullmatch(r"(\d{1,2})(?:st|nd|rd|th)\s+next month", normalized)
    if match:
        target = (now.replace(day=28) + timedelta(days=4)).replace(day=1)
        day = min(int(match.group(1)), calendar.monthrange(target.year, target.month)[1])
        return target.replace(day=day)

    match = re.fullmatch(r"next ([a-z]+)", normalized)
    if match and match.group(1) in _WEEKDAYS:
        target_weekday = _WEEKDAYS[match.group(1)]
        delta = (target_weekday - now.weekday()) % 7 or 7
        return now + timedelta(days=delta)

    match = re.fullmatch(r"next week ([a-z]+)", normalized)
    if match and match.group(1) in _WEEKDAYS:
        target_weekday = _WEEKDAYS[match.group(1)]
        start_of_next_week = now + timedelta(days=(7 - now.weekday()))
        return start_of_next_week + timedelta(days=target_weekday)

    raise ValueError(f"Unsupported relative time expression: {expression}")


def _replacement_tokens(target: datetime) -> dict[str, str]:
    return {
        "DoW": calendar.day_name[target.weekday()],
        "Month": calendar.month_name[target.month],
        "month": calendar.month_name[target.month].lower(),
        "Day": str(target.day),
        "Day0D": f"{target.day:02d}",
        "Year": str(target.year),
    }


def _replace_tokens(value: Any, tokens: dict[str, str]) -> Any:
    if isinstance(value, str):
        result = value
        for key, replacement in tokens.items():
            result = result.replace(f"{{{key}}}", replacement)
        return result
    if isinstance(value, list):
        return [_replace_tokens(item, tokens) for item in value]
    if isinstance(value, dict):
        return {key: _replace_tokens(item, tokens) for key, item in value.items()}
    return value


def process_expected_with_relative_time(expected: Any, rules: dict[str, Any], now: datetime | None = None) -> Any:
    relative = rules.get("relativeTime", {})
    target = _resolve_relative_time(relative.get("from", ""), now=now)
    tokens = _replacement_tokens(target)
    return _replace_tokens(copy.deepcopy(expected), tokens)


__all__ = ["process_expected_with_relative_time"]
