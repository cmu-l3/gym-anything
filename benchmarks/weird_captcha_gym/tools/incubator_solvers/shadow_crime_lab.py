from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "shadow_crime_lab"
INTERNAL_WIDTH = 900
INTERNAL_HEIGHT = 480


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_fresh(state_dir: Path, previous: str) -> str:
    deadline = time.time() + 8
    while time.time() < deadline:
        current = str(_read(state_dir / "ground_truth.json").get("challenge_id") or "")
        if current and current != previous:
            return current
        time.sleep(0.05)
    raise AssertionError("shadow-lab failure did not issue a fresh challenge")


def _screen(canvas_box: dict, point: dict) -> tuple[float, float]:
    return (
        canvas_box["x"] + float(point["x"]) / INTERNAL_WIDTH * canvas_box["width"],
        canvas_box["y"] + float(point["y"]) / INTERNAL_HEIGHT * canvas_box["height"],
    )


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#shadow-submit").click()
    _wait_fresh(state_dir, before)
    page.wait_for_selector('.shadow-crime-lab[data-fresh-failure="true"]', timeout=7_000)
    page.wait_for_function("() => document.querySelector('.shadow-foot .readout')?.textContent.includes('FAIL')")
    _shot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    page.wait_for_function("() => !document.querySelector('.shadow-crime-lab')?.classList.contains('is-failed')", timeout=4_000)
    truth = _read(state_dir / "ground_truth.json")
    canvas = page.locator("#shadow-canvas")
    box = canvas.bounding_box()
    if not box:
        raise AssertionError("analytic shadow canvas has no physical geometry")
    initial = truth["lamp"]

    # Exercise a genuine lamp movement and prove that local Reset restores the
    # scene before the evidence-producing probe path.
    start = _screen(box, initial)
    detour = _screen(box, {"x": float(initial["x"]) + 72, "y": float(initial["y"]) + 18})
    page.mouse.move(*start)
    page.mouse.down()
    page.mouse.move(*detour, steps=5)
    page.mouse.up()
    page.locator("#shadow-reset").click()
    expect(page.locator(".shadow-foot .readout")).to_contain_text("SCENE RESET")
    expect(page.locator(".shadow-crime-lab")).to_have_attribute("data-probe-count", "0")
    _shot(page, out_dir, mechanic, "edge-reset-recovery")

    page.mouse.move(*start)
    page.mouse.down()
    for index, probe in enumerate(truth["solution"]["probe_path"]):
        page.mouse.move(*_screen(box, probe), steps=14)
        page.wait_for_timeout(45)
        if index == 1:
            _shot(page, out_dir, mechanic, "active-causal-probes")
    page.mouse.up()
    expect(page.locator(".shadow-crime-lab")).to_have_attribute("data-probe-count", "4")
    _shot(page, out_dir, mechanic, "active-four-zone-trace")

    tag_point = truth["solution"]["expected_tag_point"]
    page.mouse.click(*_screen(box, tag_point))
    expect(page.locator(".shadow-crime-lab")).to_have_attribute("data-tagged-object", str(truth["forged_object_id"]))
    expect(page.locator("#shadow-tag-readout")).to_have_text("SHADOW TAGGED")
    _shot(page, out_dir, mechanic, "solved-forged-shadow-tag")
    page.locator("#shadow-submit").click()
    expect(page.locator(".shadow-foot .readout")).to_have_text("PASS", timeout=10_000)
