from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "clockwork_doppelganger_customs"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _canvas_point(page, point: dict) -> tuple[float, float]:
    box = page.locator("#clockwork-canvas").bounding_box()
    if not box:
        raise AssertionError("clockwork canvas has no interactive geometry")
    return (
        box["x"] + float(point["x"]) / 860.0 * box["width"],
        box["y"] + float(point["y"]) / 420.0 * box["height"],
    )


def _move_path(page, points: list[dict], duration_ms: int) -> None:
    segments = max(1, len(points) - 1)
    per_segment = duration_ms // segments
    for first, second in zip(points, points[1:]):
        start = _canvas_point(page, first)
        end = _canvas_point(page, second)
        page.mouse.move(*start)
        steps = 7
        for step in range(1, steps + 1):
            amount = step / steps
            page.mouse.move(start[0] + (end[0] - start[0]) * amount, start[1] + (end[1] - start[1]) * amount)
            page.wait_for_timeout(max(45, per_segment // steps))


def _record_role(page, truth: dict, slot: int, out_dir: Path, mechanic: str) -> None:
    stations = truth["stations"]
    if slot == 0:
        start, end = stations["pickup"], stations["handoff_a"]
        path = [start, {"x": (start["x"] + end["x"]) / 2, "y": start["y"] - 68}, end]
    elif slot == 1:
        start, stamp, end = stations["handoff_a"], stations["stamp"], stations["handoff_b"]
        path = [start, stamp, end]
    else:
        start, end = stations["handoff_b"], stations["exit"]
        path = [start, {"x": (start["x"] + end["x"]) / 2, "y": start["y"] + 62}, end]

    page.mouse.move(*_canvas_point(page, start))
    page.locator(f'[data-record="{slot}"]').click()
    page.mouse.move(*_canvas_point(page, start))
    page.wait_for_timeout(300)
    page.keyboard.press("g")
    if slot == 1:
        _move_path(page, [start, path[1]], 480)
        page.wait_for_timeout(50)
        page.keyboard.press("t")
        _move_path(page, [path[1], end], 480)
        page.wait_for_timeout(180)
    else:
        _move_path(page, path, 650 if slot == 0 else 700)
        page.wait_for_timeout(150 if slot == 0 else 160)
    page.keyboard.press("r")
    expect(page.locator(f'[data-loop-card="{slot}"]')).to_have_attribute("data-ready", "true", timeout=4_500)
    card = page.locator(f'[data-loop-card="{slot}"]')
    required = ["grab", "release"] if slot != 1 else ["grab", "stamp", "release"]
    for action in required:
        if not card.get_attribute(f"data-{action}-ms"):
            raise AssertionError(f"accepted loop {slot} is missing its recorded {action} action")


def _action_time(page, slot: int, action: str) -> int:
    value = page.locator(f'[data-loop-card="{slot}"]').get_attribute(f"data-{action}-ms")
    if value is None or value == "":
        raise AssertionError(f"loop {slot} has no recorded {action} time")
    return int(value)


def _set_phase(page, slot: int, target: int, step: int) -> None:
    slider = page.locator(f"#ghost-phase-{slot}")
    slider.focus()
    page.keyboard.press("Home")
    for _ in range(target // step):
        page.keyboard.press("ArrowRight")
    expect(slider).to_have_value(str(target))


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    expect(page.locator(".clockwork-customs")).to_have_attribute("data-active", "true")
    page.locator("#clockwork-submit").click()
    expect(page.locator(".clockwork-customs[data-fresh-failure='true']")).to_be_visible(timeout=7_000)
    expect(page.locator(".clockwork-foot .readout")).to_have_text("FAIL", timeout=7_000)
    deadline = time.time() + 7
    while time.time() < deadline:
        if str(_read(state_dir / "ground_truth.json")["challenge_id"]) != before:
            break
        time.sleep(.05)
    else:
        raise AssertionError("failed customs filing did not issue a fresh challenge")
    _shot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    expect(page.locator(".clockwork-customs")).to_have_attribute("data-active", "true", timeout=6_000)
    truth = _read(state_dir / "ground_truth.json")
    controls = truth["controls"]
    _shot(page, out_dir, mechanic, "initial-fresh-desk")

    # Capture active recording evidence in an intentionally discarded take, so
    # screenshot latency can never perturb one of the authoritative loops.
    start = truth["stations"]["pickup"]
    page.mouse.move(*_canvas_point(page, start))
    page.locator('[data-record="0"]').click()
    page.mouse.move(*_canvas_point(page, start))
    page.wait_for_timeout(260)
    page.keyboard.press("g")
    _shot(page, out_dir, mechanic, "active-dense-recording")
    expect(page.locator(".clockwork-foot .readout")).to_contain_text("TAKE 1 REJECTED", timeout=4_500)

    for slot in range(3):
        _record_role(page, truth, slot, out_dir, mechanic)
    _shot(page, out_dir, mechanic, "three-recorded-ghosts")

    # Zero phases are a genuine synchronization near-miss, not a terminal
    # failure. The user can rewind without losing any dense take.
    page.locator("#clockwork-run").click()
    expect(page.locator(".clockwork-customs")).to_have_attribute("data-cycle", "true")
    expect(page.locator(".clockwork-customs")).to_have_attribute("data-cycle", "false", timeout=int(controls["loop_duration_ms"]) + 2_500)
    expect(page.locator(".clockwork-foot .readout")).to_contain_text("SYNC MISS")
    _shot(page, out_dir, mechanic, "local-sync-failure")
    page.locator("#clockwork-rewind").click()
    expect(page.locator(".clockwork-foot .readout")).to_contain_text("REWOUND")

    step = int(controls["phase_step_ms"])
    catch_time = int(truth["conveyor"]["catch_time_ms"])
    gap = int(truth["solution"]["handoff_gap_ms"])
    grab0, release0 = _action_time(page, 0, "grab"), _action_time(page, 0, "release")
    grab1, release1 = _action_time(page, 1, "grab"), _action_time(page, 1, "release")
    grab2 = _action_time(page, 2, "grab")
    phase0 = round((catch_time - grab0) / step) * step
    release_global0 = phase0 + release0
    phase1 = round((release_global0 + gap - grab1) / step) * step
    release_global1 = phase1 + release1
    phase2 = round((release_global1 + gap - grab2) / step) * step
    for slot, phase in enumerate((phase0, phase1, phase2)):
        if phase < 0 or phase >= int(controls["loop_duration_ms"]):
            raise AssertionError(f"computed ghost phase is outside master loop: {phase}")
        _set_phase(page, slot, phase, step)
    _shot(page, out_dir, mechanic, "timeline-phased")

    page.locator("#clockwork-run").click()
    page.wait_for_timeout(1_450)
    _shot(page, out_dir, mechanic, "concurrent-ghost-playback")
    expect(page.locator(".clockwork-customs")).to_have_attribute("data-success", "true", timeout=int(controls["loop_duration_ms"]) + 2_500)
    _shot(page, out_dir, mechanic, "synchronized-delivery")
    page.locator("#clockwork-submit").click()
    expect(page.locator(".clockwork-foot .readout")).to_have_text("PASS", timeout=10_000)
