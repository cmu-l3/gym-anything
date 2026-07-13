from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "flat_prisoner"


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
        time.sleep(.05)
    raise AssertionError("flat prison did not regenerate after terminal failure")


def _click_many(page, selector: str, count: int, *, out_dir: Path | None = None, label: str | None = None) -> None:
    for index in range(count):
        page.locator(selector).click()
        page.wait_for_timeout(30)
        if out_dir is not None and label and index == max(0, count // 2):
            _screenshot(page, out_dir, MECHANIC_ID, label)


def _align_camera(page, truth: dict, out_dir: Path) -> None:
    initial = truth["initial_camera"]
    target = truth["solution"]["camera"]
    controls = truth["controls"]
    orbit = float(controls["orbit_step_deg"])
    pan = float(controls["pan_step"])
    dolly = float(controls["dolly_step"])

    yaw_steps = round((float(target["yaw_deg"]) - float(initial["yaw_deg"])) / orbit)
    _click_many(page, "#orbit-right" if yaw_steps > 0 else "#orbit-left", abs(yaw_steps), out_dir=out_dir, label="active-camera-orbit")
    pitch_steps = round((float(target["pitch_deg"]) - float(initial["pitch_deg"])) / orbit)
    _click_many(page, "#orbit-down" if pitch_steps > 0 else "#orbit-up", abs(pitch_steps))
    x_steps = round((float(target["target"][0]) - float(initial["target"][0])) / pan)
    _click_many(page, "#pan-right" if x_steps > 0 else "#pan-left", abs(x_steps))
    y_steps = round((float(target["target"][1]) - float(initial["target"][1])) / pan)
    _click_many(page, "#pan-up" if y_steps > 0 else "#pan-down", abs(y_steps))
    dolly_steps = round((float(target["distance"]) - float(initial["distance"])) / dolly)
    _click_many(page, "#dolly-out" if dolly_steps > 0 else "#dolly-in", abs(dolly_steps))
    page.wait_for_timeout(90)

    camera = page.evaluate("() => window.flatPrisonerModel.camera")
    if camera != target:
        raise AssertionError(f"primitive camera controls did not reach target: {camera} != {target}")
    audit = page.evaluate("""() => ({
      valid: window.flatPrisonerModel.topology.valid,
      joins: window.flatPrisonerModel.topology.joins.length,
      cameraEvents: window.flatPrisonerModel.cameraEventCount,
    })""")
    if not audit["valid"] or audit["joins"] < int(truth["requirements"]["minimum_screen_joins"]) or audit["cameraEvents"] < int(truth["requirements"]["minimum_camera_events"]):
        raise AssertionError(f"aligned camera did not create a qualifying projection: {audit}")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read_json(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#abandon-flat").click()
    _wait_for_new_challenge(state_dir, before)
    expect(page.locator(".flat-prison-verdict.is-fail")).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_contain_text("FAIL")
    _screenshot(page, out_dir, mechanic, "dominant-fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    page.wait_for_timeout(1_450)
    expect(page.locator(".flat-prison-verdict.is-fresh")).to_have_count(0)
    truth = _read_json(state_dir / "ground_truth.json")

    # Freeze the intake camera, physically walk off its disconnected projection,
    # and recover through the visible thaw/reframe workflow.
    page.locator("#freeze-view").click()
    expect(page.locator('.flat-prisoner[data-mode="flat"]')).to_be_visible()
    _screenshot(page, out_dir, mechanic, "bad-frozen-projection")
    page.keyboard.down("ArrowRight")
    page.wait_for_function("() => window.flatPrisonerModel.prisoner && !window.flatPrisonerModel.prisoner.alive", timeout=9_000)
    page.keyboard.up("ArrowRight")
    expect(page.locator("#prisoner-status")).to_contain_text("FELL")
    _screenshot(page, out_dir, mechanic, "failed-flat-traversal")
    page.locator("#thaw-view").click()
    expect(page.locator('.flat-prisoner[data-mode="camera"]')).to_be_visible()
    page.wait_for_timeout(35)
    page.locator("#reset-camera").click()
    page.wait_for_timeout(35)

    _align_camera(page, truth, out_dir)
    _screenshot(page, out_dir, mechanic, "successful-camera-topology")
    page.locator("#freeze-view").click()
    expect(page.locator('.flat-prisoner[data-mode="flat"]')).to_be_visible()
    _screenshot(page, out_dir, mechanic, "successful-frozen-topology")

    thresholds = page.evaluate("""() => {
      const segments = window.flatPrisonerModel.topology.segments;
      const byId = id => segments.find(segment => segment.id === id);
      return [byId('surface-02').right - 35, byId('surface-04').right - 35];
    }""")
    page.keyboard.down("ArrowRight")
    for index, threshold in enumerate(thresholds):
        page.wait_for_function(
            "threshold => window.flatPrisonerModel.prisoner.x >= threshold && window.flatPrisonerModel.prisoner.grounded",
            arg=threshold,
            timeout=8_000,
        )
        page.keyboard.down("Space")
        page.wait_for_timeout(95)
        if index == 0:
            _screenshot(page, out_dir, mechanic, "active-prisoner-jump")
        page.keyboard.up("Space")
    page.wait_for_function("() => window.flatPrisonerModel.prisoner?.reached === true", timeout=10_000)
    page.keyboard.up("ArrowRight")
    physical = page.evaluate("""() => ({
      reached: window.flatPrisonerModel.prisoner.reached,
      alive: window.flatPrisonerModel.prisoner.alive,
      ticks: window.flatPrisonerModel.prisoner.tick,
      jumps: window.flatPrisonerModel.prisoner.jumps,
      transitions: window.flatPrisonerModel.prisoner.transitions,
      cameraEvents: window.flatPrisonerModel.cameraEventCount,
      freezes: window.flatPrisonerModel.freezeCount,
      thaws: window.flatPrisonerModel.thawCount,
      deaths: window.flatPrisonerModel.deathCount,
    })""")
    requirements = truth["requirements"]
    if not physical["reached"] or not physical["alive"] or physical["ticks"] < int(requirements["minimum_traversal_ticks"]) or physical["jumps"] < int(requirements["minimum_jumps"]) or physical["transitions"] < int(requirements["minimum_key_transitions"]) or physical["cameraEvents"] < int(requirements["minimum_camera_events"]) or physical["freezes"] < 2 or physical["thaws"] < 1 or physical["deaths"] < 1:
        raise AssertionError(f"flat-prison physical workflow was incomplete: {physical}")
    _screenshot(page, out_dir, mechanic, "exit-reached-before-certification")
    page.locator("#certify-escape").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=10_000)
    expect(page.locator(".readout")).to_have_attribute("data-status", "passed")
    expect(page.locator(".flat-prison-verdict.is-pass")).to_be_visible()
