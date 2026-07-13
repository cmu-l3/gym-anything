from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


KEYS = {"N": "ArrowUp", "E": "ArrowRight", "S": "ArrowDown", "W": "ArrowLeft"}


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, name: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{name}.png"), full_page=True)


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator(".switch-abandon").click()
    expect(page.locator(".dead-switch-foot .readout")).to_contain_text("FAIL", timeout=6000)
    after = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    if before == after:
        raise AssertionError("dead_mans_switch did not regenerate after deliberate failure")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    truth = _read(state_dir / "ground_truth.json")
    route = [str(item) for item in truth["solution_path"]]
    pad = page.locator(".pressure-pad")
    bounds = pad.bounding_box()
    if not bounds:
        raise AssertionError("pressure pad has no interactive bounds")
    page.mouse.move(bounds["x"] + bounds["width"] / 2, bounds["y"] + bounds["height"] / 2)
    page.mouse.down()
    try:
        route_index = 0
        captured = False
        started = time.time()
        deadline = started + 12
        while time.time() < deadline:
            bounds = pad.bounding_box()
            if not bounds:
                raise AssertionError("moving pressure pad disappeared")
            page.mouse.move(bounds["x"] + bounds["width"] / 2, bounds["y"] + bounds["height"] / 2, steps=2)
            if route_index < len(route):
                page.keyboard.press(KEYS[route[route_index]])
                route_index += 1
            if not captured and route_index >= len(route) // 2:
                _screenshot(page, out_dir, mechanic, "active-moving-pressure-track")
                captured = True
            if page.locator(".dead-switch-foot .readout").text_content().startswith("PASS"):
                break
            page.wait_for_timeout(78)
        expect(page.locator(".dead-switch-foot .readout")).to_contain_text("PASS", timeout=8000)
        if page.locator(".dead-switch-captcha[data-holding='true']").count() != 1:
            raise AssertionError("pressure hold was not continuous through completion")
    finally:
        page.mouse.up()
    _screenshot(page, out_dir, mechanic, "pass")
