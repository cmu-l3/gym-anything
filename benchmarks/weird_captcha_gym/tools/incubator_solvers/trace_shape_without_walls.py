from __future__ import annotations

import json
import math
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "trace_shape_without_walls"


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_for_new_challenge(state_dir: Path, previous: str) -> str:
    deadline = time.time() + 8
    while time.time() < deadline:
        current = str(_read_json(state_dir / "ground_truth.json").get("challenge_id") or "")
        if current and current != previous:
            return current
        time.sleep(0.05)
    raise AssertionError("blind corridor did not regenerate after invalid certification")


def _stage_box(page) -> dict:
    box = page.locator(".trace-stage").bounding_box()
    if not box:
        raise AssertionError("blind-corridor oscilloscope is not visible")
    return box


def _screen_point(stage_box: dict, stage: dict, point: list[int] | tuple[int, int]) -> tuple[float, float]:
    return (
        stage_box["x"] + point[0] / int(stage["width"]) * stage_box["width"],
        stage_box["y"] + point[1] / int(stage["height"]) * stage_box["height"],
    )


def _browser_round(value: float) -> int:
    return math.floor(value + 0.5)


def _drift(sample_index: int, spec: dict) -> tuple[int, int]:
    dx = float(spec["amplitude_x"]) * (
        math.sin(float(spec["phase_x"]) + sample_index * float(spec["rate_x"])) - math.sin(float(spec["phase_x"]))
    )
    dy = float(spec["amplitude_y"]) * (
        math.cos(float(spec["phase_y"]) + sample_index * float(spec["rate_y"])) - math.cos(float(spec["phase_y"]))
    )
    return _browser_round(dx), _browser_round(dy)


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read_json(state_dir / "ground_truth.json")["challenge_id"])
    page.locator(".trace-submit").click()
    _wait_for_new_challenge(state_dir, before)
    expect(page.locator(".blind-corridor-captcha[data-fresh-failure='true']")).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_contain_text("FAIL")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def _probe_path(page, stage_box: dict, stage: dict, points: list[list[int]], stride: int = 2) -> None:
    for point in points[::stride]:
        page.mouse.move(*_screen_point(stage_box, stage, point), steps=1)


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    stage = truth["stage"]
    box = _stage_box(page)

    # Freely map the true corridor and deliberately inspect every false branch.
    _probe_path(page, box, stage, truth["main_path"][:32], stride=2)
    _probe_path(page, box, stage, truth["branches"][0]["points"], stride=2)
    page.wait_for_timeout(90)
    _screenshot(page, out_dir, mechanic, "active-local-sonar")
    _probe_path(page, box, stage, truth["main_path"][30:], stride=2)
    for branch in truth["branches"][1:]:
        _probe_path(page, box, stage, branch["points"], stride=2)

    page.wait_for_function("() => document.querySelector('.trace-start-beacon')?.dataset.armed === 'true'", timeout=5_000)
    mapped = page.evaluate("""() => ({
      probes: window.blindCorridorModel.probeCount,
      cells: window.blindCorridorModel.probeCells.size,
      main: window.blindCorridorModel.mainCoverage.size,
      branches: window.blindCorridorModel.branchCoverage.size,
    })""")
    requirement = truth["requirements"]
    if mapped["probes"] < requirement["min_probe_samples"] or mapped["cells"] < requirement["min_probe_cells"] or mapped["main"] < requirement["min_main_coverage"] or mapped["branches"] < requirement["min_branch_coverage"]:
        raise AssertionError(f"sonar exploration did not satisfy the mapping contract: {mapped}")

    # Commit once into a hidden wall, verify visible cancellation, and recover without regeneration.
    start = page.locator(".trace-start-beacon").bounding_box()
    if not start:
        raise AssertionError("START beacon is not visible")
    page.mouse.move(start["x"] + start["width"] / 2, start["y"] + start["height"] / 2)
    page.mouse.down()
    start_point = truth["start"]
    collision_point = [start_point[0] + 50, 42 if start_point[1] > 220 else int(stage["height"]) - 42]
    page.mouse.move(*_screen_point(box, stage, collision_point), steps=3)
    page.mouse.up()
    expect(page.locator(".trace-breach[data-visible='true']")).to_be_visible()
    expect(page.locator(".readout")).to_contain_text("WALL BREACH")
    _screenshot(page, out_dir, mechanic, "collision-recovery")
    page.locator(".trace-rearm").click()
    expect(page.locator(".readout")).to_contain_text("TRACE RE-ARMED")

    # Trace the spline physically while compensating each raw sample for visible deterministic drift.
    start = page.locator(".trace-start-beacon").bounding_box()
    if not start:
        raise AssertionError("START beacon disappeared after re-arm")
    page.mouse.move(start["x"] + start["width"] / 2, start["y"] + start["height"] / 2)
    page.mouse.down()
    for sample_index, effective in enumerate(truth["main_path"][1:], start=1):
        dx, dy = _drift(sample_index, truth["drift"])
        raw = [effective[0] - dx, effective[1] - dy]
        page.mouse.move(*_screen_point(box, stage, raw), steps=1)
        page.wait_for_timeout(9)
        if sample_index == 48:
            out_dir.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=str(out_dir / f"{mechanic}-active-crosswind-trace.png"), full_page=False)
    page.mouse.up()

    expect(page.locator(".trace-stage.is-complete")).to_be_visible(timeout=4_000)
    expect(page.locator(".trace-exit-beacon[data-complete='true']")).to_be_visible()
    physical = page.evaluate("""() => ({
      completed: window.blindCorridorModel.completed,
      samples: window.blindCorridorModel.completedSamples,
      distance: window.blindCorridorModel.completedDistance,
      collisions: window.blindCorridorModel.collisions,
      rearms: window.blindCorridorModel.rearmCount,
      finalProbe: window.blindCorridorModel.finalProbe,
    })""")
    if not physical["completed"] or physical["samples"] < requirement["min_trace_samples"] or physical["distance"] < requirement["min_trace_distance"] or physical["collisions"] < 1 or physical["rearms"] < 1 or physical["finalProbe"] != truth["exit"]:
        raise AssertionError(f"blind-corridor physical workflow ended unexpectedly: {physical}")
    _screenshot(page, out_dir, mechanic, "solved-exit-lock")
    page.locator(".trace-submit").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
