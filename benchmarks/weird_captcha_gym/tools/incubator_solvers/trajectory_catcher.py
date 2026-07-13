from __future__ import annotations

import json
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "trajectory_catcher"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_for_phase(page, phase: str, timeout: int = 8_000) -> None:
    expect(page.locator(".trajectory-catcher")).to_have_attribute("data-phase", phase, timeout=timeout)


def _canvas_position(page, point: dict) -> tuple[float, float]:
    bounds = page.locator("#trajectory-canvas").bounding_box()
    if not bounds:
        raise AssertionError("trajectory canvas has no interactive bounds")
    return (
        bounds["x"] + float(point["x"]) / 900.0 * bounds["width"],
        bounds["y"] + float(point["y"]) / 480.0 * bounds["height"],
    )


def _place_catcher(page, round_data: dict, solution: dict) -> None:
    initial = round_data["initial_catcher"]
    source = _canvas_position(page, initial)
    destination = _canvas_position(page, solution)
    page.mouse.move(*source)
    page.mouse.down()
    page.mouse.move(*destination, steps=10)
    page.mouse.up()

    current_angle = int(initial["angle_deg"]) % 180
    target_angle = int(solution["angle_deg"]) % 180
    clockwise_steps = ((target_angle - current_angle) % 180) // 15
    counter_steps = ((current_angle - target_angle) % 180) // 15
    if clockwise_steps == 0:
        # A successful transcript must demonstrate a real orientation action even
        # when a generated tangent happens to match the reset stop.
        page.locator("#trajectory-rotate-right").click()
        page.locator("#trajectory-rotate-left").click()
    elif clockwise_steps <= counter_steps:
        for _ in range(clockwise_steps):
            page.locator("#trajectory-rotate-right").click()
    else:
        for _ in range(counter_steps):
            page.locator("#trajectory-rotate-left").click()

    aperture = int(initial["aperture"])
    target_aperture = int(solution["aperture"])
    button = "#trajectory-size-up" if target_aperture > aperture else "#trajectory-size-down"
    for _ in range(abs(target_aperture - aperture) // 10):
        page.locator(button).click()

    root = page.locator(".trajectory-catcher")
    expected = page.evaluate(
        """() => ({
            angle: document.querySelector('#trajectory-angle')?.textContent,
            aperture: document.querySelector('#trajectory-aperture')?.textContent,
        })"""
    )
    if expected != {"angle": f"{target_angle}°", "aperture": str(target_aperture)}:
        raise AssertionError(f"catcher controls did not reach hidden solution: {expected}")
    expect(root).to_have_attribute("data-phase", "hidden")
    page.locator("#trajectory-arm").click()
    expect(root).to_have_attribute("data-armed", "true")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#trajectory-file").click()
    expect(page.locator(".trajectory-catcher[data-fresh-failure='true']")).to_be_visible(timeout=7_000)
    expect(page.locator(".trajectory-foot .readout")).to_have_text("FAIL", timeout=7_000)
    after = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    if before == after:
        raise AssertionError("failed flight log did not issue a fresh challenge")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    rounds = truth["rounds"]
    solutions = truth["solutions"]
    if len(rounds) != 3 or len(solutions) != 3:
        raise AssertionError("trajectory challenge does not contain exactly three flights")

    # The refreshed challenge begins immediately. Preserve visual evidence of the
    # observable flight before any hidden commitment is made.
    _wait_for_phase(page, "observing")
    page.wait_for_timeout(520)
    _screenshot(page, out_dir, mechanic, "active-observation")

    # Exercise the one-round replay contract with a genuine physical miss.
    _wait_for_phase(page, "hidden")
    page.locator("#trajectory-arm").click()
    expect(page.locator(".trajectory-catcher")).to_have_attribute("data-result", "miss", timeout=7_000)
    _screenshot(page, out_dir, mechanic, "miss-feedback")
    page.locator("#trajectory-replay").click()

    for index, (round_data, solution) in enumerate(zip(rounds, solutions)):
        _wait_for_phase(page, "hidden")
        if index == 0:
            page.locator("#trajectory-reset-catcher").click()
            expect(page.locator(".trajectory-foot .readout")).to_contain_text("CATCHER RESET")
            _screenshot(page, out_dir, mechanic, "reset-contract")
        _place_catcher(page, round_data, solution)
        if index == 0:
            _screenshot(page, out_dir, mechanic, "hidden-commit")
        expect(page.locator(".trajectory-catcher")).to_have_attribute("data-result", "caught", timeout=7_000)
        if index < len(rounds) - 1:
            page.locator("#trajectory-next").click()

    _screenshot(page, out_dir, mechanic, "solved")
    page.locator("#trajectory-file").click()
    expect(page.locator(".trajectory-foot .readout")).to_have_text("PASS", timeout=7_000)
    expect(page.locator(".trajectory-foot .readout")).to_have_attribute("data-status", "passed")
