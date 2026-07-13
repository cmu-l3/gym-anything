from __future__ import annotations

import json
import math
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "cursor_lens_reveal"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_new(state_dir: Path, previous: str) -> None:
    deadline = time.time() + 8
    while time.time() < deadline:
        if str(_read(state_dir / "ground_truth.json").get("challenge_id")) != previous:
            return
        time.sleep(0.05)
    raise AssertionError("palimpsest did not issue a fresh plate")


def _box(page) -> dict:
    box = page.locator("#palimpsest-canvas").bounding_box()
    if not box:
        raise AssertionError("palimpsest canvas is not visible")
    return box


def _screen(box: dict, point: list[float]) -> tuple[float, float]:
    return box["x"] + point[0] / 920 * box["width"], box["y"] + point[1] / 500 * box["height"]


def _position(node: dict, elapsed_ms: float) -> list[float]:
    motion = node["motion"]
    angle = math.tau * elapsed_ms / motion["period_ms"] + motion["phase"]
    return [node["base"][0] + motion["radius_x"] * math.sin(angle), node["base"][1] + motion["radius_y"] * math.cos(angle * motion["ratio"])]


def _elapsed(page) -> float:
    return float(page.evaluate("() => performance.now() - movingPalimpsestModel.startedAt"))


def _tune(page, target: int) -> None:
    while int(page.evaluate("() => movingPalimpsestModel.polarization")) != target:
        current = int(page.evaluate("() => movingPalimpsestModel.polarization"))
        clockwise = ((target - current) % 180) // 45
        counter = ((current - target) % 180) // 45
        page.locator("#pol-right" if clockwise <= counter else "#pol-left").click()


def _capture(page, node: dict, *, short: bool = False) -> None:
    box = _box(page)
    start = _position(node, _elapsed(page))
    page.mouse.move(*_screen(box, start))
    page.mouse.down()
    if short:
        page.wait_for_timeout(120)
        page.mouse.up()
        return
    for _ in range(7):
        page.wait_for_timeout(82)
        target = _position(node, _elapsed(page))
        page.mouse.move(*_screen(box, target), steps=2)
    page.mouse.up()


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#palimpsest-submit").click()
    _wait_new(state_dir, before)
    expect(page.locator('.moving-palimpsest[data-fresh-failure="true"]')).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_have_text("FAIL")
    _shot(page, out_dir, mechanic, "fail-fresh-plate")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    page.wait_for_function("() => document.querySelector('.moving-palimpsest')?.dataset.freshFailure === 'false'", timeout=4_000)
    box = _box(page)
    # A broad, real scan establishes local coverage before any answer hold.
    for row in range(5):
        for column in range(7):
            page.mouse.move(*_screen(box, [65 + column * 132, 52 + row * 98]), steps=1)
            page.wait_for_timeout(12)
    _shot(page, out_dir, mechanic, "active-local-scan")

    first = truth["nodes"][0]
    _tune(page, int(first["polarization_deg"]))
    _capture(page, first, short=True)
    page.wait_for_function("() => movingPalimpsestModel.misses === 1")
    _shot(page, out_dir, mechanic, "early-hold-decay")
    _capture(page, first)
    page.wait_for_function("() => movingPalimpsestModel.current === 1")
    page.locator("#palimpsest-reset").click()
    page.wait_for_function("() => movingPalimpsestModel.current === 0 && movingPalimpsestModel.resetCount === 1")

    for index, node in enumerate(truth["nodes"]):
        _tune(page, int(node["polarization_deg"]))
        # Capture a tuned-lens frame while the moving mark is actually visible.
        if index == 2:
            position = _position(node, _elapsed(page))
            page.mouse.move(*_screen(box, position))
            page.wait_for_timeout(80)
            _shot(page, out_dir, mechanic, "tuned-moving-echo")
        _capture(page, node)
        page.wait_for_function("count => movingPalimpsestModel.current === count", arg=index + 1)
    expect(page.locator('.moving-palimpsest[data-completed="true"]')).to_be_visible()
    state = page.evaluate("() => ({probes:movingPalimpsestModel.probes,cells:movingPalimpsestModel.cells.size,turns:movingPalimpsestModel.tuningChanges,locked:movingPalimpsestModel.locked.length})")
    requirements = truth["requirements"]
    if state["probes"] < requirements["minimum_probe_samples"] or state["cells"] < requirements["minimum_probe_cells"] or state["turns"] < requirements["minimum_tuning_changes"] or state["locked"] != 5:
        raise AssertionError(f"palimpsest interaction contract is incomplete: {state}")
    _shot(page, out_dir, mechanic, "five-echoes-fixed")
    page.locator("#palimpsest-submit").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
    expect(page.locator(".palimpsest-verdict")).to_contain_text("PASS")
    expect(page.locator(".palimpsest-verdict")).not_to_contain_text("FAIL")
