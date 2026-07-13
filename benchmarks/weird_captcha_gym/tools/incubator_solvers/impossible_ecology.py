from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "impossible_ecology"


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
    raise AssertionError("causal terrarium did not regenerate after failure")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read_json(state_dir / "ground_truth.json")["challenge_id"])
    page.locator(".eco-submit").click()
    _wait_for_new_challenge(state_dir, before)
    expect(page.locator(".impossible-ecology-captcha[data-fresh-failure='true']")).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_contain_text("FAIL")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    wrong_probe = next(probe for probe in ("CLIMATE", "FOOD", "LIGHT") if probe != truth["protocol"][0])
    page.locator(f'.eco-probe[data-probe="{wrong_probe}"]').click()
    expect(page.locator(".readout")).to_contain_text("PROTOCOL CONTAMINATED")
    page.locator(".eco-reset").click()
    expect(page.locator(".readout")).to_contain_text("LAB RESET")
    for index, probe in enumerate(truth["protocol"]):
        page.locator(f'.eco-probe[data-probe="{probe}"]').click()
        if index == 0:
            page.wait_for_timeout(360)
            _screenshot(page, out_dir, mechanic, "active-response-cycle")
        page.wait_for_function("expected => window.impossibleEcologyModel.progress === expected", arg=index + 1, timeout=5_000)

    expect(page.locator(".eco-quarantine-gate[data-ready='true']")).to_be_visible()
    culprit = page.locator(f'.eco-organism[data-habitat-id="{truth["culprit_id"]}"]')
    quarantine = page.locator(".eco-quarantine")
    culprit_box = culprit.bounding_box()
    quarantine_box = quarantine.bounding_box()
    if not culprit_box or not quarantine_box:
        raise AssertionError("culprit or quarantine chamber is not visible")
    page.mouse.move(culprit_box["x"] + culprit_box["width"] / 2, culprit_box["y"] + culprit_box["height"] / 2)
    page.mouse.down()
    page.mouse.move(quarantine_box["x"] + quarantine_box["width"] / 2, quarantine_box["y"] + quarantine_box["height"] / 2, steps=12)
    page.mouse.up()
    page.wait_for_timeout(120)
    expect(page.locator(".eco-quarantine[data-occupied='true']")).to_contain_text(truth["culprit_id"].upper())
    state = page.evaluate("""() => ({
        progress: window.impossibleEcologyModel.progress,
        ticks: window.impossibleEcologyModel.tickTotal,
        quarantined: window.impossibleEcologyModel.quarantinedId,
        moves: window.impossibleEcologyModel.quarantineMoves,
    })""")
    expected_ticks = 3 * int(truth["ticks_per_cycle"])
    if state["progress"] != 3 or state["ticks"] != expected_ticks or state["quarantined"] != truth["culprit_id"] or state["moves"] < 3:
        raise AssertionError(f"causal quarantine physical workflow ended in unexpected state: {state}")
    _screenshot(page, out_dir, mechanic, "solved-quarantine")
    page.locator(".eco-submit").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
