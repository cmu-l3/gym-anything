from __future__ import annotations

import io
import json
import math
import re
import time
from pathlib import Path

from PIL import Image
from playwright.sync_api import expect


MECHANIC_ID = "impossible_panorama"


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
    raise AssertionError("panorama failure did not issue a fresh challenge")


def _camera(page) -> tuple[float, float, float]:
    root = page.locator(".impossible-panorama")
    return (
        float(root.get_attribute("data-camera-x") or 0),
        float(root.get_attribute("data-camera-y") or 0),
        float(root.get_attribute("data-zoom") or 0),
    )


def _move_camera(page, destination: dict, *, tolerance: float = 1.2) -> None:
    canvas = page.locator("#panorama-canvas")
    box = canvas.bounding_box()
    if not box:
        raise AssertionError("panorama canvas has no physical geometry")
    origin_x = box["x"] + box["width"] / 2
    origin_y = box["y"] + box["height"] / 2
    for _ in range(90):
        camera_x, camera_y, zoom = _camera(page)
        delta_x = float(destination["x"]) - camera_x
        delta_y = float(destination["y"]) - camera_y
        if math.hypot(delta_x, delta_y) <= tolerance:
            return
        drag_x = max(-118.0, min(118.0, -delta_x * zoom * box["width"] / 820.0))
        drag_y = max(-88.0, min(88.0, -delta_y * zoom * box["height"] / 450.0))
        page.mouse.move(origin_x, origin_y)
        page.mouse.down()
        page.mouse.move(origin_x + drag_x, origin_y + drag_y, steps=6)
        page.mouse.up()
    raise AssertionError(f"could not physically pan to {destination}; camera ended at {_camera(page)}")


def _ring_present(canvas) -> bool:
    image = Image.open(io.BytesIO(canvas.screenshot())).convert("RGB")
    center_x, center_y = image.width // 2, image.height // 2
    cyan = 0
    for red, green, blue in image.crop((center_x - 72, center_y - 72, center_x + 72, center_y + 72)).getdata():
        if red < 165 and green > 185 and blue > 180 and green - red > 45 and blue - red > 35:
            cyan += 1
    return cyan >= 32


def _wait_for_new_event(canvas) -> None:
    deadline = time.time() + 8
    while time.time() < deadline and _ring_present(canvas):
        time.sleep(0.06)
    while time.time() < deadline:
        if _ring_present(canvas):
            return
        time.sleep(0.055)
    raise AssertionError("the repeating tip-to-tip ring event was not visibly observed")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    # Exercise local recovery on the challenge that will be discarded. The
    # eventual passing transcript stays a clean, mistake-free solve.
    page.locator("#panorama-zoom-in").click()
    page.locator("#panorama-focus-slider").focus()
    page.keyboard.press("ArrowRight")
    page.locator('[data-pan="right"]').click()
    page.locator("#panorama-reset").click()
    expect(page.locator(".panorama-foot .readout")).to_contain_text("PLATE RESET")
    expect(page.locator(".impossible-panorama")).to_have_attribute("data-visited-count", "1")
    initial = truth["initial_camera"]
    camera_x, camera_y, zoom = _camera(page)
    assert abs(camera_x - float(initial["x"])) < .1 and abs(camera_y - float(initial["y"])) < .1 and abs(zoom - float(initial["zoom"])) < .01
    _shot(page, out_dir, mechanic, "reset-recovery")

    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#panorama-submit").click()
    _wait_fresh(state_dir, before)
    page.wait_for_selector('.impossible-panorama[data-fresh-failure="true"]', timeout=7_000)
    page.wait_for_function("() => document.querySelector('.panorama-foot .readout')?.textContent.includes('FAIL')")
    expect(page.locator(".impossible-panorama")).to_have_class(re.compile(r"\bis-failed\b"))
    _shot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    page.wait_for_function("() => !document.querySelector('.impossible-panorama')?.classList.contains('is-failed')", timeout=5_000)
    truth = _read(state_dir / "ground_truth.json")
    solution = truth["solution"]

    # A couple of ordinary search sweeps prove the pan controls without making
    # arbitrary mileage part of the pass condition.
    for index, waypoint in enumerate(solution["search_waypoints"][:2]):
        _move_camera(page, waypoint)
        if index == 1:
            _shot(page, out_dir, mechanic, "active-search")
    _shot(page, out_dir, mechanic, "search-sectors")

    # Use only the visible controls: twelve + buttons reach 1.80x, while the
    # focused range input is moved by real keyboard events to the target plane.
    for _ in range(12):
        page.locator("#panorama-zoom-in").click()
    expect(page.locator(".impossible-panorama")).to_have_attribute("data-zoom", "1.8")
    focus = page.locator("#panorama-focus-slider")
    focus.focus()
    page.keyboard.press("Home")
    for _ in range(int(solution["target_depth"])):
        page.keyboard.press("ArrowRight")
    expect(page.locator(".impossible-panorama")).to_have_attribute("data-focus", str(int(solution["target_depth"])))
    _move_camera(page, solution["target_base"])
    _shot(page, out_dir, mechanic, "focused-reticle")

    canvas = page.locator("#panorama-canvas")
    _wait_for_new_event(canvas)
    page.wait_for_timeout(75)
    _shot(page, out_dir, mechanic, "event-observed")
    shutter = page.locator("#panorama-shutter")
    box = shutter.bounding_box()
    if not box:
        raise AssertionError("shutter control has no physical geometry")
    page.mouse.move(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
    page.mouse.down()
    page.wait_for_timeout(330)
    _shot(page, out_dir, mechanic, "active-stable-hold")
    # The contract requires 940 ms of coherent shutter samples. Keep a clear
    # margin above that requirement instead of relying on screenshot latency to
    # make a nominal 900 ms hold pass on slower machines.
    page.wait_for_timeout(850)
    page.mouse.up()
    expect(page.locator(".panorama-foot .readout")).to_contain_text("COHERENT EVENT")
    page.wait_for_timeout(100)
    _shot(page, out_dir, mechanic, "solved-exposure")
    page.locator("#panorama-submit").click()
    expect(page.locator(".panorama-foot .readout")).to_have_text("PASS", timeout=10_000)
