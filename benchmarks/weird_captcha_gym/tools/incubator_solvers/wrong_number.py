from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "wrong_number"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_new(state_dir: Path, previous: str) -> None:
    deadline = time.time() + 8
    while time.time() < deadline:
        current = str(_read(state_dir / "ground_truth.json").get("challenge_id") or "")
        if current and current != previous:
            return
        time.sleep(.05)
    raise AssertionError("phase-lock switchboard did not regenerate")


def _set_range(page, selector: str, value: int, minimum: int) -> None:
    slider = page.locator(selector)
    slider.focus()
    page.keyboard.press("Home")
    for _ in range(value - minimum):
        page.keyboard.press("ArrowRight")
    expect(slider).to_have_value(str(value))


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(mechanic)
    truth = _read(state_dir / "ground_truth.json")
    before = str(truth["challenge_id"])
    wrong = next(line for line in truth["lines"] if line["id"] != truth["target_line_id"])
    page.locator(f'.wrong-line[data-line-id="{wrong["id"]}"]').click()
    _set_range(page, "#wrong-phase", (-int(wrong["phase_offset_steps"])) % int(truth["qualification"]["phase_steps"]), 0)
    _set_range(page, "#wrong-skew", -int(wrong["skew_offset_steps"]), int(truth["qualification"]["skew_min"]))
    page.locator("#wrong-test").click()
    page.wait_for_function("() => Boolean(window.wrongNumberPhaseLockModel?.trial)")
    page.wait_for_timeout(520)
    _shot(page, out_dir, mechanic, "active-impostor-test")
    expect(page.locator(".wrong-number-foot .readout")).to_contain_text("NO SUSTAINED LOCK", timeout=8_000)
    _shot(page, out_dir, mechanic, "impostor-rejected-locally")
    page.locator("#wrong-abandon").click()
    _wait_new(state_dir, before)
    expect(page.locator('.wrong-number-captcha[data-fresh-failure="true"]')).to_be_visible(timeout=8_000)
    expect(page.locator(".wrong-number-foot .readout")).to_contain_text("FAIL")
    _shot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(mechanic)
    truth = _read(state_dir / "ground_truth.json")
    target_id = str(truth["target_line_id"])
    page.locator(f'.wrong-line[data-line-id="{target_id}"]').click()
    _set_range(page, "#wrong-phase", int(truth["solution_phase_step"]), 0)
    _set_range(page, "#wrong-skew", int(truth["solution_skew_step"]), int(truth["qualification"]["skew_min"]))
    expect(page.locator(".wrong-lock-state")).to_have_attribute("data-locked", "true")
    _shot(page, out_dir, mechanic, "aligned-authorized-carrier")
    page.locator("#wrong-test").click()
    page.wait_for_function("() => Boolean(window.wrongNumberPhaseLockModel?.trial)")
    phase_slider = page.locator("#wrong-phase")
    phase_slider.focus()
    line = next(item for item in truth["lines"] if item["id"] == target_id)
    steps = int(truth["qualification"]["phase_steps"])
    captured = False
    deadline = time.time() + 10
    while time.time() < deadline:
        snapshot = page.evaluate("""() => { const m=window.wrongNumberPhaseLockModel; return {trial:Boolean(m?.trial), terminal:Boolean(m?.terminal), elapsed:m?.trial ? performance.now()-m.trial.performanceStart : 0, phase:Number(m?.phase||0)}; }""")
        if snapshot["terminal"] or not snapshot["trial"]:
            break
        target = (-float(line["phase_offset_steps"]) - float(line["drift_milli_steps_per_second"]) * float(snapshot["elapsed"]) / 1_000_000) % steps
        desired = int(round(target)) % steps
        current = int(snapshot["phase"])
        if desired != current:
            direct = desired - current
            if abs(direct) <= steps // 2:
                key = "ArrowRight" if direct > 0 else "ArrowLeft"
                for _ in range(abs(direct)):
                    page.keyboard.press(key)
            elif desired > current:
                page.keyboard.press("End")
                for _ in range((steps - 1) - desired):
                    page.keyboard.press("ArrowLeft")
            else:
                page.keyboard.press("Home")
                for _ in range(desired):
                    page.keyboard.press("ArrowRight")
        if not captured and snapshot["elapsed"] >= 2_000:
            _shot(page, out_dir, mechanic, "active-drift-correction")
            captured = True
        page.wait_for_timeout(70)
    expect(page.locator(".wrong-number-foot .readout")).to_have_text("PASS", timeout=10_000)
    result = _read(state_dir / "result.json")
    trial_starts = [event for event in result.get("events") or [] if event.get("type") == "trial_start"]
    trial_ends = [event for event in result.get("events") or [] if event.get("type") == "trial_end"]
    if len(trial_starts) != 1 or len(trial_ends) != 1 or trial_ends[0].get("passed_local") is not True:
        raise AssertionError("clean switchboard solve did not contain exactly one sustained lock trial")
