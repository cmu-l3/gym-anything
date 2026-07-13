from __future__ import annotations

import json
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
    page.locator(".dice-abandon").click()
    expect(page.locator(".blind-dice-foot .readout")).to_contain_text("FAIL", timeout=6000)
    after = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    if before == after:
        raise AssertionError("blind_dice_courier did not regenerate after deliberate failure")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    truth = _read(state_dir / "ground_truth.json")
    route = [str(item) for item in truth["solution_path"]]
    for index, direction in enumerate(route):
        page.keyboard.press(KEYS[direction])
        page.wait_for_timeout(55)
        if index == max(1, len(route) // 2):
            _screenshot(page, out_dir, mechanic, "active-blind-roll")
    expect(page.locator(".blind-dice-foot .readout")).to_contain_text("PASS", timeout=8000)
    _screenshot(page, out_dir, mechanic, "pass")
