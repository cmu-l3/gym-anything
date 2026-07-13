from __future__ import annotations

import json
import math
import time
from pathlib import Path

from playwright.sync_api import expect


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def shot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def wait_fresh(state_dir: Path, previous: str, timeout: float = 10) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        truth = read_json(state_dir / "ground_truth.json")
        if truth.get("challenge_id") and truth.get("challenge_id") != previous:
            return truth
        time.sleep(0.05)
    raise AssertionError("server did not issue a fresh challenge after a real rejection")


def expect_fail_and_fresh(page, state_dir: Path, previous: str) -> dict:
    expect(page.locator(".readout")).to_contain_text("FAIL", timeout=12_000)
    truth = wait_fresh(state_dir, previous)
    # Every mechanic deliberately leaves the rejected surface visible briefly so
    # the human can perceive the verdict before the fresh variant replaces it.
    page.wait_for_timeout(1_050)
    expect(page.locator("body[data-mechanic]")).to_be_visible(timeout=8_000)
    return truth


def center(locator) -> tuple[float, float]:
    box = locator.bounding_box()
    if not box:
        raise AssertionError(f"element is not physically visible: {locator}")
    return box["x"] + box["width"] / 2, box["y"] + box["height"] / 2


def drag(page, source, target, *, steps: int = 8, hold_ms: int = 0) -> None:
    start = center(source)
    end = center(target) if hasattr(target, "bounding_box") else target
    page.mouse.move(*start)
    page.mouse.down()
    page.mouse.move(*end, steps=steps)
    page.wait_for_timeout(max(60, hold_ms))
    page.mouse.up()


def drag_delta(page, locator, dx: float, dy: float, *, maximum_step: float = 24) -> None:
    start = center(locator)
    count = max(2, math.ceil(math.hypot(dx, dy) / maximum_step))
    page.mouse.move(*start)
    page.mouse.down()
    page.mouse.move(start[0] + dx, start[1] + dy, steps=count)
    page.wait_for_timeout(60)
    page.mouse.up()
