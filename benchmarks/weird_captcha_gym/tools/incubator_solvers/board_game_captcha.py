from __future__ import annotations

import json
import math
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "board_game_captcha"


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
    raise AssertionError("gyro board did not issue a fresh run")


def _pad(page) -> tuple[dict, float, float, float]:
    box = page.locator("#tilt-pad").bounding_box()
    if not box:
        raise AssertionError("analog tilt pad is not visible")
    return box, box["x"] + box["width"] / 2, box["y"] + box["height"] / 2, min(box["width"], box["height"]) * 0.38


def _move_pad(page, center_x: float, center_y: float, radius: float, tilt: tuple[float, float]) -> None:
    length = math.hypot(*tilt)
    x, y = tilt
    if length > 1:
        x, y = x / length, y / length
    page.mouse.move(center_x + x * radius, center_y + y * radius, steps=1)


def _drive(page, waypoints: list[list[float]], switch_targets: set[int], timeout_s: float = 38.0) -> None:
    _, cx, cy, radius = _pad(page)
    page.mouse.move(cx, cy)
    page.mouse.down()
    deadline = time.time() + timeout_s
    try:
        for index, target in enumerate(waypoints):
            while time.time() < deadline:
                state = page.evaluate("() => ({position:gyroBoardModel.position,velocity:gyroBoardModel.velocity,switchIndex:gyroBoardModel.switchIndex,completed:gyroBoardModel.completed,deaths:gyroBoardModel.deaths})")
                if state["completed"]:
                    return
                if index in switch_targets:
                    expected_switch = {0: 1, 2: 2, 4: 3}[index]
                    if state["switchIndex"] >= expected_switch:
                        break
                elif math.hypot(target[0] - state["position"][0], target[1] - state["position"][1]) < 31:
                    break
                dx, dy = target[0] - state["position"][0], target[1] - state["position"][1]
                vx, vy = state["velocity"]
                command = (dx * 0.018 - vx * 0.0105, dy * 0.018 - vy * 0.0105)
                _move_pad(page, cx, cy, radius, command)
                page.wait_for_timeout(95)
            else:
                raise AssertionError(f"gyro controller timed out at waypoint {index}: {target}")
        while time.time() < deadline and not page.evaluate("() => gyroBoardModel.completed"):
            state = page.evaluate("() => ({position:gyroBoardModel.position,velocity:gyroBoardModel.velocity})")
            target = waypoints[-1]
            command = ((target[0] - state["position"][0]) * 0.018 - state["velocity"][0] * 0.011, (target[1] - state["position"][1]) * 0.018 - state["velocity"][1] * 0.011)
            _move_pad(page, cx, cy, radius, command)
            page.wait_for_timeout(95)
        if not page.evaluate("() => gyroBoardModel.completed"):
            raise AssertionError("ball never settled in the goal cup")
    finally:
        page.mouse.up()


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#gyro-submit").click()
    _wait_new(state_dir, before)
    expect(page.locator('.gyro-board[data-fresh-failure="true"]')).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_have_text("FAIL")
    _shot(page, out_dir, mechanic, "fail-fresh-board")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    page.wait_for_function("() => document.querySelector('.gyro-board')?.dataset.freshFailure === 'false'", timeout=4_000)

    # Exercise a genuine rim collision and the explicit recovery contract.
    _, cx, cy, radius = _pad(page)
    outward = -1 if truth["start"][0] < truth["stage"]["width"] / 2 else 1
    page.mouse.move(cx, cy); page.mouse.down(); _move_pad(page, cx, cy, radius, (outward, 0.2))
    page.wait_for_function("() => gyroBoardModel.collisions > 0", timeout=6_000)
    page.mouse.up()
    _shot(page, out_dir, mechanic, "real-rim-contact")
    page.locator("#gyro-reset").click()
    page.wait_for_function("() => gyroBoardModel.manualResets === 1 && gyroBoardModel.switchIndex === 0")

    _drive(page, truth["solver_waypoints"], {0, 2, 4})
    expect(page.locator('.gyro-board[data-completed="true"]')).to_be_visible(timeout=4_000)
    state = page.evaluate("() => ({ticks:gyroBoardModel.tickCount,controls:gyroBoardModel.controlChanges,switches:gyroBoardModel.switchIndex,deaths:gyroBoardModel.deaths,collisions:gyroBoardModel.collisions,resets:gyroBoardModel.manualResets})")
    if state["ticks"] < truth["requirements"]["minimum_ticks"] or state["controls"] < truth["requirements"]["minimum_control_changes"] or state["switches"] != 3 or state["resets"] != 1 or state["collisions"] < 1:
        raise AssertionError(f"gyro run lacks physical evidence: {state}")
    _shot(page, out_dir, mechanic, "three-lamps-and-cup")
    page.locator("#gyro-submit").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
    expect(page.locator(".gyro-verdict")).to_contain_text("PASS")
    expect(page.locator(".gyro-verdict")).not_to_contain_text("FAIL")
