from __future__ import annotations

import json
from pathlib import Path


MECHANIC_ID = "jigsaw_slider_alignment"


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _rail_value(page) -> int:
    return int(page.evaluate("() => window.jigsawSliderAlignmentModel.rail"))


def _depth_value(page) -> int:
    return int(page.evaluate("() => window.jigsawSliderAlignmentModel.depth"))


def _drag_rail(page, delta_pixels: float, *, precision_tail: bool) -> None:
    carriage = page.locator("#alignment-carriage")
    box = carriage.bounding_box()
    if box is None:
        raise AssertionError("rail carriage has no visible bounds")
    start_x = box["x"] + box["width"] / 2
    start_y = box["y"] + box["height"] / 2
    page.mouse.move(start_x, start_y)
    page.mouse.down()
    if precision_tail and abs(delta_pixels) > 1.2:
        tail = 1.0 if delta_pixels > 0 else -1.0
        page.mouse.move(start_x + delta_pixels - tail, start_y)
        page.wait_for_timeout(175)
        page.mouse.move(start_x + delta_pixels, start_y)
    else:
        page.mouse.move(start_x + delta_pixels, start_y)
    page.mouse.up()
    page.wait_for_function("() => window.jigsawSliderAlignmentModel.railDrag === null", timeout=3000)


def _set_depth(page, target_depth: int) -> None:
    for _attempt in range(6):
        current = _depth_value(page)
        delta = target_depth - current
        if abs(delta) <= 2:
            return
        grip = page.locator("#alignment-depth-grip")
        track = page.locator("#alignment-depth-track")
        grip_box = grip.bounding_box()
        track_box = track.bounding_box()
        if grip_box is None or track_box is None:
            raise AssertionError("depth grip has no visible bounds")
        start_x = grip_box["x"] + grip_box["width"] / 2
        start_y = grip_box["y"] + grip_box["height"] / 2
        target_y = start_y - delta * track_box["height"] / 1000
        page.mouse.move(start_x, start_y)
        page.mouse.down()
        page.mouse.move(start_x, target_y)
        page.mouse.up()
        page.wait_for_function("() => window.jigsawSliderAlignmentModel.depthDrag === null", timeout=3000)
    raise AssertionError(f"depth grip did not reach target {target_depth}; current={_depth_value(page)}")


def _set_rail(page, target_rail: int) -> None:
    for _attempt in range(7):
        page.wait_for_function("() => window.jigsawSliderAlignmentModel.inertia === null", timeout=5000)
        current = _rail_value(page)
        delta_pixels = (target_rail - current) / 1000
        if abs(delta_pixels) <= 2.0:
            return
        _drag_rail(page, delta_pixels, precision_tail=True)
        if page.evaluate("() => window.jigsawSliderAlignmentModel.inertia !== null"):
            page.wait_for_function("() => window.jigsawSliderAlignmentModel.inertia === null", timeout=5000)
    raise AssertionError(f"rail did not reach target {target_rail}; current={_rail_value(page)}")


def _hold_scan(page, milliseconds: int = 780) -> None:
    button = page.locator("#alignment-scan")
    box = button.bounding_box()
    if box is None:
        raise AssertionError("optical lock has no visible bounds")
    x = box["x"] + box["width"] / 2
    y = box["y"] + box["height"] / 2
    page.mouse.move(x, y)
    page.mouse.down()
    page.wait_for_timeout(milliseconds)
    page.mouse.up()


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = _read_json(state_dir / "ground_truth.json")["challenge_id"]
    _hold_scan(page, 760)
    page.wait_for_function(
        "() => document.querySelector('.readout')?.textContent.includes('FAIL')",
        timeout=8000,
    )
    after = _read_json(state_dir / "ground_truth.json")["challenge_id"]
    if before == after:
        raise AssertionError("misaligned optical hold did not generate fresh geometry")
    page.wait_for_timeout(260)
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    scene = truth["scene"]
    current = _rail_value(page)
    maximum = int(scene["rail"]["maximum_milli"])
    fast_delta = 150.0 if maximum - current > 260000 else -150.0
    _drag_rail(page, fast_delta, precision_tail=False)
    page.wait_for_function(
        "() => window.jigsawSliderAlignmentModel.inertiaSamples >= 2 && window.jigsawSliderAlignmentModel.inertia !== null",
        timeout=4000,
    )
    _screenshot(page, out_dir, mechanic, "active-inertia")
    page.wait_for_function("() => window.jigsawSliderAlignmentModel.inertia === null", timeout=6000)

    _set_depth(page, int(truth["target_depth_milli"]))
    _set_rail(page, int(truth["target_rail_milli"]))
    page.wait_for_function("() => document.querySelectorAll('.alignment-axis-pair > div.is-locked').length === 2", timeout=3000)
    proof = page.evaluate(
        """() => ({
          railTravel: window.jigsawSliderAlignmentModel.railTravel,
          depthTravel: window.jigsawSliderAlignmentModel.depthTravel,
          inertiaSamples: window.jigsawSliderAlignmentModel.inertiaSamples,
          rail: window.jigsawSliderAlignmentModel.rail,
          depth: window.jigsawSliderAlignmentModel.depth,
        })"""
    )
    if proof["railTravel"] < int(truth["tolerances"]["minimum_rail_travel_milli"]):
        raise AssertionError(f"rail manipulation proof is too short: {proof}")
    if proof["depthTravel"] < int(truth["tolerances"]["minimum_depth_travel_milli"]):
        raise AssertionError(f"depth manipulation proof is too short: {proof}")
    if proof["inertiaSamples"] < int(truth["tolerances"]["minimum_inertia_samples"]):
        raise AssertionError(f"inertia proof is too short: {proof}")
    page.wait_for_timeout(260)
    _screenshot(page, out_dir, mechanic, "aligned")
    _hold_scan(page, 790)
    page.wait_for_function("() => document.querySelector('.readout')?.textContent === 'PASS'", timeout=8000)
