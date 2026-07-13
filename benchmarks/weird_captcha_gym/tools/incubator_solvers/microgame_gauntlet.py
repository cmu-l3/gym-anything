from __future__ import annotations

import json
import math
import time
from pathlib import Path


MECHANIC_ID = "microgame_gauntlet"


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
    raise AssertionError("reactor failure did not issue a fresh challenge")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#gauntlet-certify").click()
    _wait_fresh(state_dir, before)
    page.wait_for_selector('.gauntlet-reactor[data-fresh-failure="true"]', timeout=7_000)
    page.wait_for_function("() => document.querySelector('.readout')?.textContent.includes('FAIL')")
    _shot(page, out_dir, mechanic, "fail-refresh")


def _wait_round(page, round_data: dict) -> None:
    page.wait_for_function(
        "roundId => document.querySelector('.gauntlet-reactor')?.dataset.roundId === roundId",
        arg=round_data["id"], timeout=7_000,
    )


def _dial_point(box: dict, angle: float, radius: float = 88) -> tuple[float, float]:
    radians = math.radians(angle)
    return box["x"] + box["width"] / 2 + math.cos(radians) * radius, box["y"] + box["height"] / 2 + math.sin(radians) * radius


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    for round_index, round_data in enumerate(truth["rounds"]):
        _wait_round(page, round_data)
        round_type = round_data["type"]
        if round_type == "pressure":
            page.keyboard.down("Space")
            for pulse in round_data["pulses"]:
                page.locator(f'[data-pulse-id="{pulse["id"]}"]').click()
                page.wait_for_timeout(35)
            if round_index < 3:
                _shot(page, out_dir, mechanic, "active-pressure-hold")
            page.keyboard.up("Space")
        elif round_type == "chord":
            first, second = round_data["keys"]
            page.keyboard.down(first)
            page.keyboard.down(second)
            page.wait_for_timeout(int(round_data["required_ticks"] * round_data["tick_ms"] + 180))
            if round_index < 3:
                _shot(page, out_dir, mechanic, "active-two-key-chord")
            page.keyboard.up(first)
            page.keyboard.up(second)
        elif round_type == "dial":
            dial = page.locator("#gauntlet-dial")
            box = dial.bounding_box()
            if not box:
                raise AssertionError("dial has no physical geometry")
            target = float(round_data["target_angle"])
            angles = [target - 90, target - 75, target - 60, target - 45]
            start = _dial_point(box, angles[0])
            page.mouse.move(*start)
            page.mouse.down()
            for angle in angles[1:]:
                page.mouse.move(*_dial_point(box, angle))
                page.wait_for_timeout(25)
            page.mouse.up()
            page.wait_for_selector('#gauntlet-brake[data-in-zone="true"]', timeout=6_000)
            _shot(page, out_dir, mechanic, "active-inertial-coast")
            page.locator("#gauntlet-brake").click()
        elif round_type == "intercept":
            page.locator("#intercept-arm").click()
            page.wait_for_timeout(120)
            _shot(page, out_dir, mechanic, "active-moving-intercept")
            page.wait_for_selector('#intercept-target[data-in-gate="true"]', timeout=6_000)
            page.locator("#intercept-target").click()
        elif round_type == "route":
            pad = page.locator("#route-pad")
            box = pad.bounding_box()
            if not box:
                raise AssertionError("route pad has no physical geometry")
            points = round_data["points"]
            def screen(point: dict) -> tuple[float, float]:
                return box["x"] + box["width"] * float(point["x"]) / 100, box["y"] + box["height"] * float(point["y"]) / 100
            page.mouse.move(*screen(points[0]))
            page.mouse.down()
            for point in points[1:]:
                page.mouse.move(*screen(point), steps=3)
            _shot(page, out_dir, mechanic, "active-balance-route")
            page.mouse.up()
        else:
            raise AssertionError(f"unknown reactor round {round_type!r}")
        if round_index < len(truth["rounds"]) - 1:
            page.wait_for_function("index => Number(document.getElementById('gauntlet-round-counter')?.textContent.split('/')[0].trim()) === index", arg=round_index + 2, timeout=7_000)
    page.wait_for_function("() => document.querySelector('.gauntlet-reactor')?.dataset.roundType === 'complete'", timeout=7_000)
    _shot(page, out_dir, mechanic, "solved-five-rounds")
    page.locator("#gauntlet-certify").click()
    page.wait_for_function("() => document.querySelector('.readout')?.textContent === 'PASS'", timeout=8_000)
