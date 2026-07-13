from __future__ import annotations

import calendar
import hashlib
import random
from typing import Any


MECHANIC_ID = "thirty_year_time_wheel"
MIN_YEAR = 1996
MAX_YEAR = 2025
PALETTES = ("orrery", "verdigris", "eclipse", "almanac")


def _days_in_month(year: int, month: int) -> int:
    return calendar.monthrange(year, month)[1]


def _step_month(date: dict[str, int], direction: int) -> dict[str, int]:
    year, month, day = date["year"], date["month"], date["day"]
    ordinal = year * 12 + month - 1 + direction
    minimum = MIN_YEAR * 12
    maximum = MAX_YEAR * 12 + 11
    ordinal = max(minimum, min(maximum, ordinal))
    next_year, month_index = divmod(ordinal, 12)
    next_month = month_index + 1
    return {"year": next_year, "month": next_month, "day": min(day, _days_in_month(next_year, next_month))}


def _step_year(date: dict[str, int], direction: int) -> dict[str, int]:
    year = max(MIN_YEAR, min(MAX_YEAR, date["year"] + direction))
    return {"year": year, "month": date["month"], "day": min(date["day"], _days_in_month(year, date["month"]))}


def _step_day(date: dict[str, int], direction: int) -> dict[str, int]:
    maximum = _days_in_month(date["year"], date["month"])
    day = ((date["day"] - 1 + direction) % maximum) + 1
    return {"year": date["year"], "month": date["month"], "day": day}


def _apply(date: dict[str, int], component: str, steps: int) -> dict[str, int]:
    current = dict(date)
    direction = 1 if steps >= 0 else -1
    for _ in range(abs(steps)):
        if component == "month":
            current = _step_month(current, direction)
        elif component == "year":
            current = _step_year(current, direction)
        elif component == "day":
            current = _step_day(current, direction)
        else:
            raise ValueError(f"unknown component {component}")
    return current


def _generate_dates(rng: random.Random) -> tuple[dict[str, int], dict[str, int], list[dict[str, Any]]]:
    for _attempt in range(200):
        initial_year = rng.randint(MIN_YEAR, MAX_YEAR)
        initial_month = rng.randint(1, 12)
        initial_day = rng.randint(1, _days_in_month(initial_year, initial_month))
        target_year = rng.choice([year for year in range(MIN_YEAR, MAX_YEAR + 1) if year != initial_year])
        target_month = rng.choice([month for month in range(1, 13) if month != initial_month])
        target_day = rng.randint(1, _days_in_month(target_year, target_month))
        if target_day == initial_day:
            continue
        initial = {"year": initial_year, "month": initial_month, "day": initial_day}
        target = {"year": target_year, "month": target_month, "day": target_day}
        current = dict(initial)
        month_steps = target_month - current["month"]
        current = _apply(current, "month", month_steps)
        year_steps = target_year - current["year"]
        current = _apply(current, "year", year_steps)
        day_steps = target_day - current["day"]
        if day_steps == 0:
            continue
        current = _apply(current, "day", day_steps)
        if current != target:
            continue
        route = [
            {"component": "month", "steps": month_steps},
            {"component": "year", "steps": year_steps},
            {"component": "day", "steps": day_steps},
        ]
        if all(item["steps"] != 0 for item in route):
            return initial, target, route
    raise ValueError("could not generate a practical three-ring date route")


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    digest = hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode("utf-8")).digest()
    rng = random.Random(int.from_bytes(digest[:8], "big"))
    initial, target, direct_route = _generate_dates(rng)
    task_id = str(task.get("id") or "thirty_year_time_wheel_seed_0001@0.1")
    challenge_id = hashlib.sha256(f"{seed}|thirty-year-time-wheel".encode("utf-8")).hexdigest()[:12]
    palette = PALETTES[rng.randrange(len(PALETTES))]
    ring_offsets = {component: rng.randrange(0, 360, 6) for component in ("day", "month", "year")}
    variant_lower_bound = len(PALETTES) * 30 * 29 * 12 * 11 * 26 * (60**3)
    public_state = {
        "benchmark": "weird_captcha_gym",
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "challenge_id": challenge_id,
        "prompt": task.get("natural_language")
        or "Wind all three calendar rings to the target. Let one ring coast, then catch it with the brake before locking.",
        "submit_label": "LOCK CHRONOMETER",
        "asset_manifest": "shared_runtime/assets/provenance/incubator_puzzles_v1.json",
        "generator": {
            "name": "thirty_year_time_wheel_v1",
            "year_span": 30,
            "variant_count": variant_lower_bound,
            "variant_count_kind": "conservative valid date/ring-offset lower bound",
        },
        "year_range": {"minimum": MIN_YEAR, "maximum": MAX_YEAR},
        "initial_date": initial,
        "target_date": target,
        "ring_offsets": ring_offsets,
        "detent_degrees": 12,
        "inertia": {"minimum_velocity_rad_s": 0.8, "tick_ms": 90, "maximum_detents": 10},
        "palette": palette,
        "rules": {
            "day": "Day detents wrap inside the current month's real length.",
            "month_year": "Month and year changes clamp invalid dates, including leap day.",
            "proof": "LOCK requires every ring, a genuine coast detent, and an effective brake.",
        },
    }
    ground_truth = {
        "mechanic_id": MECHANIC_ID,
        "task_id": task_id,
        "seed": seed,
        "challenge_id": challenge_id,
        "year_range": {"minimum": MIN_YEAR, "maximum": MAX_YEAR},
        "initial_date": initial,
        "target_date": target,
        "detent_degrees": 12,
        "inertia": {"minimum_velocity_rad_s": 0.8, "tick_ms": 90, "maximum_detents": 10},
        "direct_recovery_route": direct_route,
        "ring_offsets": ring_offsets,
        "palette": palette,
        "variant_count": variant_lower_bound,
        "variant_count_kind": "conservative valid date/ring-offset lower bound",
    }
    return public_state, ground_truth
