from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "occlusion_shell_swindle"


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
    raise AssertionError("shell swindle did not regenerate after invalid certification")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read_json(state_dir / "ground_truth.json")["challenge_id"])
    page.locator(".shell-certify").click()
    _wait_for_new_challenge(state_dir, before)
    expect(page.locator(".occlusion-shell-captcha[data-fresh-failure='true']")).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_contain_text("FAIL")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    for round_index, round_state in enumerate(truth["rounds"]):
        if round_index == 0:
            # Intentionally miss the physical inspection port once, then prove
            # that the visible rewind/recovery contract restores the same round.
            page.locator(".shell-start-round").click()
            page.wait_for_function("() => window.occlusionShellModel.mode === 'rewind'", timeout=12_000)
            _screenshot(page, out_dir, mechanic, "missed-port-rewind")
            page.locator(".shell-start-round").click()
            page.wait_for_function("() => window.occlusionShellModel.mode === 'ready'")
        expect(page.locator(".shell-start-round")).to_be_enabled()
        page.locator(".shell-start-round").click()
        stage = page.locator(".shell-stage").bounding_box()
        if not stage:
            raise AssertionError("shell theater is not visible")
        port = round_state["inspection"]["port"]
        page.mouse.move(stage["x"] + port[0] / truth["stage"]["width"] * stage["width"], stage["y"] + port[1] / truth["stage"]["height"] * stage["height"])
        handoff_tick = int(round_state["handoff"]["tick"])
        page.wait_for_function("tick => window.occlusionShellModel.tick >= tick", arg=handoff_tick, timeout=10_000)
        if round_index == 1:
            expect(page.locator('.shell-inspection-port[data-revealed="true"]')).to_be_visible()
            _screenshot(page, out_dir, mechanic, "active-physical-shuttle")
        page.wait_for_function("() => window.occlusionShellModel.mode === 'select'", timeout=12_000)
        if round_index == 0:
            _screenshot(page, out_dir, mechanic, "round-one-stop")
        carrier = str(round_state["final_carrier"])
        page.locator(f'.shell-piece[data-shell-id="{carrier}"]').click()
        if round_index < 2:
            page.wait_for_function("index => window.occlusionShellModel.roundIndex === index && window.occlusionShellModel.mode === 'ready'", arg=round_index + 1, timeout=4_000)
        else:
            page.wait_for_function("() => window.occlusionShellModel.mode === 'certify'", timeout=4_000)

    physical = page.evaluate("""() => ({
      rounds: window.occlusionShellModel.roundIndex,
      choices: window.occlusionShellModel.choices,
      ticks: window.occlusionShellModel.totalTicks,
      observed: window.occlusionShellModel.observedMs,
      inspections: window.occlusionShellModel.inspectionSamples,
      rewinds: window.occlusionShellModel.rewindCount,
    })""")
    expected_ticks = sum(int(item["frame_count"]) for item in truth["rounds"])
    minimum_inspections = sum(int(item["inspection"]["minimum_samples"]) for item in truth["rounds"])
    if physical["rounds"] != 3 or len(physical["choices"]) != 3 or physical["ticks"] <= expected_ticks or physical["observed"] < 28_000 or physical["inspections"] < minimum_inspections or physical["rewinds"] != 1:
        raise AssertionError(f"three-round physical observation ended unexpectedly: {physical}")
    _screenshot(page, out_dir, mechanic, "three-tracks-sealed")
    page.locator(".shell-certify").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
