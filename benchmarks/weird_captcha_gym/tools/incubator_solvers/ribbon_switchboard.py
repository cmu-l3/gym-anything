from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "ribbon_switchboard"


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
    raise AssertionError("ribbon switchboard did not regenerate after invalid certification")


def _stage_box(page) -> dict:
    box = page.locator(".ribbon-stage").bounding_box()
    if not box:
        raise AssertionError("ribbon switchboard is not visible")
    return box


def _screen_point(box: dict, stage: dict, point: list[int]) -> tuple[float, float]:
    return box["x"] + point[0] / int(stage["width"]) * box["width"], box["y"] + point[1] / int(stage["height"]) * box["height"]


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read_json(state_dir / "ground_truth.json")["challenge_id"])
    page.locator(".ribbon-submit").click()
    _wait_for_new_challenge(state_dir, before)
    expect(page.locator(".ribbon-switchboard-captcha[data-fresh-failure='true']")).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_contain_text("FAIL")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    stage, target_path, requirements = truth["stage"], truth["target_path"], truth["requirements"]
    box = _stage_box(page)

    for point in target_path[:38:2]:
        page.mouse.move(*_screen_point(box, stage, point), steps=1)
    for crossing in truth["target_crossings"][:3]:
        page.mouse.move(*_screen_point(box, stage, crossing["point"]), steps=1)
    page.wait_for_timeout(100)
    _screenshot(page, out_dir, mechanic, "active-local-depth")
    for point in target_path[36::2]:
        page.mouse.move(*_screen_point(box, stage, point), steps=1)
    for crossing in truth["target_crossings"]:
        page.mouse.move(*_screen_point(box, stage, crossing["point"]), steps=1)
    page.wait_for_function("() => document.querySelector('.ribbon-source')?.dataset.armed === 'true'", timeout=5_000)

    explored = page.evaluate("""() => ({
      hover: window.ribbonSwitchboardModel.hoverCount,
      cells: window.ribbonSwitchboardModel.hoverCells.size,
      route: window.ribbonSwitchboardModel.targetCoverage.size,
      crossings: window.ribbonSwitchboardModel.crossingCoverage.size,
    })""")
    if explored["hover"] < requirements["min_hover_samples"] or explored["cells"] < requirements["min_hover_cells"] or explored["route"] < requirements["min_target_coverage"] or explored["crossings"] < requirements["min_crossing_coverage"]:
        raise AssertionError(f"local depth exploration was insufficient: {explored}")

    source = page.locator(".ribbon-source").bounding_box()
    if not source:
        raise AssertionError("marked ribbon source is not visible")
    page.mouse.move(source["x"] + source["width"] / 2, source["y"] + source["height"] / 2)
    page.mouse.down()
    start = target_path[0]
    collision = [start[0] + 48, int(stage["height"]) - 35 if start[1] < int(stage["height"]) / 2 else 35]
    page.mouse.move(*_screen_point(box, stage, collision), steps=3)
    page.mouse.up()
    expect(page.locator(".ribbon-breach[data-visible='true']")).to_be_visible()
    _screenshot(page, out_dir, mechanic, "edge-breach-recovery")
    page.locator(".ribbon-rearm").click()
    expect(page.locator(".readout")).to_contain_text("RE-ARMED")

    source = page.locator(".ribbon-source").bounding_box()
    if not source:
        raise AssertionError("marked source disappeared after re-arm")
    page.mouse.move(source["x"] + source["width"] / 2, source["y"] + source["height"] / 2)
    page.mouse.down()
    for sample_index, point in enumerate(target_path[1:], start=1):
        page.mouse.move(*_screen_point(box, stage, point), steps=1)
        page.wait_for_timeout(8)
        if sample_index == 48:
            out_dir.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=str(out_dir / f"{mechanic}-active-continuous-route.png"), full_page=False)
    page.mouse.up()
    expect(page.locator(".ribbon-stage.is-complete")).to_be_visible(timeout=4_000)
    physical = page.evaluate("""() => ({
      completed: window.ribbonSwitchboardModel.completed,
      samples: window.ribbonSwitchboardModel.completedSamples,
      crossings: window.ribbonSwitchboardModel.completedCrossings,
      collisions: window.ribbonSwitchboardModel.collisions,
      rearms: window.ribbonSwitchboardModel.rearmCount,
      final: window.ribbonSwitchboardModel.finalPoint,
    })""")
    if not physical["completed"] or physical["samples"] < requirements["min_trace_samples"] or physical["crossings"] != len(truth["target_crossings"]) or physical["collisions"] < 1 or physical["rearms"] < 1 or physical["final"] != truth["target_terminal"]:
        raise AssertionError(f"physical ribbon route ended unexpectedly: {physical}")
    _screenshot(page, out_dir, mechanic, "solved-true-terminal")
    page.locator(".ribbon-submit").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
