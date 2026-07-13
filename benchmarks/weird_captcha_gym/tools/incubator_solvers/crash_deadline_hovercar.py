from __future__ import annotations

import json
import math
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "crash_deadline_hovercar"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, name: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True); page.screenshot(path=str(out_dir / f"{mechanic}-{name}.png"), full_page=True)


def _wait_new(state_dir: Path, previous: str) -> None:
    deadline = time.time() + 8
    while time.time() < deadline:
        if str(_read(state_dir / "ground_truth.json").get("challenge_id")) != previous: return
        time.sleep(.05)
    raise AssertionError("hovercar challenge did not regenerate after rejection")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID: raise AssertionError(mechanic)
    # Exercise symmetric road-departure collision and humane local retry on the
    # course that will be discarded, preserving a clean final flight record.
    page.keyboard.down("w"); page.keyboard.down("d")
    expect(page.locator(".hover-crash[data-visible='true']")).to_be_visible(timeout=4_000)
    page.keyboard.up("d"); page.keyboard.up("w")
    _shot(page, out_dir, mechanic, "road-departure-crash")
    page.locator(".hover-retry").click(); expect(page.locator(".readout")).to_contain_text("RE-ARMED")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator(".hover-submit").click(); _wait_new(state_dir, before)
    expect(page.locator(".hovercar-captcha[data-fresh-failure='true']")).to_be_visible(timeout=8_000); expect(page.locator(".readout")).to_contain_text("FAIL"); _shot(page, out_dir, mechanic, "fail-fresh-course")


def _road(progress: float, physics: dict) -> float:
    return 240 + physics["road_amplitude"] * math.sin(progress / physics["road_period"] + physics["road_phase"])


def _set_key(page, current: set[str], key: str, down: bool) -> None:
    if down and key not in current: page.keyboard.down(key); current.add(key)
    elif not down and key in current: page.keyboard.up(key); current.remove(key)


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID: raise AssertionError(mechanic)
    truth = _read(state_dir / "ground_truth.json"); physics = truth["physics"]; box = page.locator(".hover-canvas").bounding_box()
    if not box: raise AssertionError("hovercar flight canvas missing")
    held: set[str] = set(); first_dwell_shot = False; deadline = time.time() + 22
    while time.time() < deadline:
        snapshot = page.evaluate("""() => { const m=window.crashDeadlineHovercarModel; const active=m.state.targets.find(t=>!m.checks.has(t.id)&&m.tick>=t.window_start&&m.tick<=t.window_end); return {tick:m.tick,progress:m.progress,lateral:m.lateral,velocity:m.lateralVelocity,speed:m.speed,checks:[...m.checks],crashed:m.crashed,finished:m.finished,active:active?{id:active.id,point:m.targetPoint(active)}:null}; }""")
        if snapshot["crashed"]: raise AssertionError(f"hovercar crashed during controlled solve at {snapshot}")
        if snapshot["finished"]: break
        # Full throttle finishes before check three. Regulate to ~47 so visual inspection, steering, and deadline all matter.
        _set_key(page, held, "w", snapshot["speed"] < 45)
        _set_key(page, held, "s", snapshot["speed"] > 53)
        desired_offset = 0.0
        for obstacle in truth["obstacles"]:
            distance = float(obstacle["world_x"]) - snapshot["progress"]
            if -42 <= distance <= 105:
                desired_offset = -62.0 if float(obstacle["lane_offset"]) > 0 else 62.0
                break
        desired = _road(snapshot["progress"] + 20, physics) + desired_offset
        control = desired - snapshot["lateral"] - snapshot["velocity"] * 1.7
        _set_key(page, held, "d", control > 2.0); _set_key(page, held, "a", control < -2.0)
        if snapshot["active"]:
            point = snapshot["active"]["point"]; page.mouse.move(box["x"] + point[0] / truth["stage"]["width"] * box["width"], box["y"] + point[1] / truth["stage"]["height"] * box["height"], steps=2)
            if not first_dwell_shot and snapshot["tick"] > truth["targets"][0]["window_start"] + 4:
                _shot(page, out_dir, mechanic, "simultaneous-drive-hover-dwell"); first_dwell_shot = True
        page.wait_for_timeout(42)
    for key in list(held): page.keyboard.up(key)
    expect(page.locator(".hover-finish[data-visible='true']")).to_be_visible(timeout=4_000)
    finished = page.evaluate("() => ({checks:[...window.crashDeadlineHovercarModel.checks].sort(),finished:window.crashDeadlineHovercarModel.finished,crashes:window.crashDeadlineHovercarModel.crashes,retries:window.crashDeadlineHovercarModel.retries,samples:window.crashDeadlineHovercarModel.pointerSamples,tick:window.crashDeadlineHovercarModel.tick})")
    if not finished["finished"] or len(finished["checks"]) != len(truth["targets"]) or finished["crashes"] != 0 or finished["retries"] != 0 or finished["samples"] < 35: raise AssertionError(f"clean divided-attention run incomplete: {finished}")
    _shot(page, out_dir, mechanic, "solved-pre-submit"); page.locator(".hover-submit").click(); expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
