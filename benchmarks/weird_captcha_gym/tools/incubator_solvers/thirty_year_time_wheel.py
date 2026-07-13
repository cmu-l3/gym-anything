from __future__ import annotations

import json
import math
from pathlib import Path


MECHANIC_ID = "thirty_year_time_wheel"
RADII = {"day": 0.42, "month": 0.296, "year": 0.183}


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _drag_detents(page, component: str, steps: int, *, brake_immediately: bool) -> None:
    if not steps:
        return
    dial = page.locator("#time-wheel-dial")
    box = dial.bounding_box()
    if box is None:
        raise AssertionError("time wheel dial has no visible bounds")
    center_x = box["x"] + box["width"] / 2
    center_y = box["y"] + box["height"] / 2
    radius = box["width"] * RADII[component]
    direction = 1 if steps > 0 else -1
    angle = -math.pi / 2
    page.mouse.move(center_x + radius * math.cos(angle), center_y + radius * math.sin(angle))
    page.mouse.down()
    for _ in range(abs(steps)):
        angle += direction * math.radians(12.12)
        page.mouse.move(center_x + radius * math.cos(angle), center_y + radius * math.sin(angle))
    page.mouse.up()
    page.wait_for_function("() => window.thirtyYearTimeWheelModel.drag === null", timeout=3000)
    if brake_immediately:
        page.locator("#time-brake").click()
        page.wait_for_timeout(20)


def _component_value(page, component: str) -> int:
    return int(page.evaluate("component => window.thirtyYearTimeWheelModel.current[component]", component))


def _adjust_to(page, component: str, target: int) -> None:
    for _attempt in range(10):
        current = _component_value(page, component)
        if current == target:
            return
        _drag_detents(page, component, target - current, brake_immediately=True)
    raise AssertionError(f"could not set {component} ring to {target}; current={_component_value(page, component)}")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = _read_json(state_dir / "ground_truth.json")["challenge_id"]
    page.locator("#time-lock").click()
    page.wait_for_function(
        "() => document.querySelector('.readout')?.textContent.includes('FAIL')",
        timeout=8000,
    )
    after = _read_json(state_dir / "ground_truth.json")["challenge_id"]
    if before == after:
        raise AssertionError("premature time-wheel LOCK did not generate a fresh challenge")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    target = {key: int(value) for key, value in truth["target_date"].items()}

    # A fast physical day-ring release establishes genuine momentum. Let at least
    # one timer-driven detent happen before pressing the visible brake.
    _drag_detents(page, "day", 5, brake_immediately=False)
    page.wait_for_function(
        "() => window.thirtyYearTimeWheelModel.coastDetents >= 1 && window.thirtyYearTimeWheelModel.coast !== null",
        timeout=5000,
    )
    _screenshot(page, out_dir, mechanic, "active-coast")
    page.locator("#time-brake").click()
    page.wait_for_function(
        "() => window.thirtyYearTimeWheelModel.qualifyingBrakes >= 1 && window.thirtyYearTimeWheelModel.coast === null",
        timeout=3000,
    )

    # Month and year changes can clamp the day. Set them first, then recover the
    # exact day. Every adjustment is another physical angular drag; the brake is
    # clicked immediately after release so no unobserved coast can corrupt it.
    _adjust_to(page, "month", target["month"])
    _adjust_to(page, "year", target["year"])
    _adjust_to(page, "day", target["day"])
    contract = page.evaluate(
        """target => ({
          current: {...window.thirtyYearTimeWheelModel.current},
          coverage: [...window.thirtyYearTimeWheelModel.coverage].sort(),
          coast: window.thirtyYearTimeWheelModel.coastDetents,
          brakes: window.thirtyYearTimeWheelModel.qualifyingBrakes,
          target,
        })""",
        target,
    )
    if contract["current"] != target or contract["coverage"] != ["day", "month", "year"] or contract["coast"] < 1 or contract["brakes"] < 1:
        raise AssertionError(f"time wheel proof is incomplete: {contract}")
    _screenshot(page, out_dir, mechanic, "solved")
    page.locator("#time-lock").click()
    page.wait_for_function("() => document.querySelector('.readout')?.textContent === 'PASS'", timeout=8000)
