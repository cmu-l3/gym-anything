from __future__ import annotations

import json
import re
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "craftcha_alchemy_bench"
PROCESS_STATIONS = ("grind", "heat", "infuse", "press")


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_fresh(state_dir: Path, previous: str) -> str:
    deadline = time.time() + 10
    while time.time() < deadline:
        current = str(_read(state_dir / "ground_truth.json").get("challenge_id") or "")
        if current and current != previous:
            return current
        time.sleep(0.05)
    raise AssertionError("alchemy failure did not issue a fresh challenge")


def _center(rect: dict) -> tuple[float, float]:
    return ((float(rect["x1"]) + float(rect["x2"])) / 2, (float(rect["y1"]) + float(rect["y2"])) / 2)


def _client_point(page, point: tuple[float, float], geometry: dict) -> tuple[float, float]:
    box = page.locator(".alchemy-bench").bounding_box()
    if not box:
        raise AssertionError("alchemy bench has no browser bounds")
    return (
        box["x"] + point[0] / float(geometry["width"]) * box["width"],
        box["y"] + point[1] / float(geometry["height"]) * box["height"],
    )


def _drag(page, geometry: dict, start: tuple[float, float], end: tuple[float, float]) -> None:
    start_x, start_y = _client_point(page, start, geometry)
    end_x, end_y = _client_point(page, end, geometry)
    page.mouse.move(start_x, start_y)
    page.mouse.down()
    page.wait_for_timeout(55)
    page.mouse.move(end_x, end_y, steps=12)
    page.wait_for_timeout(45)
    page.mouse.up()
    page.wait_for_timeout(80)


def _drag_slot_to(page, geometry: dict, slot: int, destination: str) -> None:
    start = _center(geometry["inventory_slots"][slot])
    target_rect = geometry["delivery"] if destination == "delivery" else geometry["stations"][destination]
    _drag(page, geometry, start, _center(target_rect))


def _wait_sealed(page, timeout: int = 8_000) -> None:
    expect(page.locator(".alchemy-bench")).to_have_attribute("data-recipe", "sealed", timeout=timeout)


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    _wait_sealed(page)
    page.locator("#alchemy-verify").click()
    _wait_fresh(state_dir, before)
    page.wait_for_selector('.alchemy-bench[data-fresh-failure="true"]', timeout=8_000)
    page.wait_for_function("() => document.querySelector('.alchemy-foot .readout')?.textContent.includes('FAIL')")
    _shot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    geometry = truth["geometry"]
    recipe = truth["recipe"]
    _wait_sealed(page)
    page.wait_for_function("() => !document.querySelector('.alchemy-verdict-fail')", timeout=4_000)

    # Spend the one costly replay and prove that the longer VNC-readable window
    # visibly exposes, then reseals, the generated three-branch work order.
    page.locator("#alchemy-replay").click()
    expect(page.locator(".alchemy-bench")).to_have_attribute("data-recipe", "open")
    _shot(page, out_dir, mechanic, "costly-recipe-replay")
    _wait_sealed(page, timeout=6_000)
    expect(page.locator("#alchemy-memory-count")).to_have_text("1/3")

    # A physically valid but semantically wrong machine destroys lineage. The
    # bench must make that consequence visible, then Reset must recover all raw
    # materials without refunding the replay charge.
    first_step = recipe["branches"][0]["steps"][0]
    wrong_station = next(station for station in PROCESS_STATIONS if station != first_step["station_id"])
    _drag_slot_to(page, geometry, 0, wrong_station)
    page.locator(f'[data-cycle-station="{wrong_station}"]').click()
    expect(page.locator("#alchemy-transform-count")).to_have_text(f"1/{recipe['step_count']}", timeout=3_000)
    expect(page.locator('.alchemy-item[data-slot="0"]')).to_have_class(re.compile(r"\bis-waste\b"))
    page.wait_for_timeout(140)
    _shot(page, out_dir, mechanic, "destructive-decoy-transform")
    page.locator("#alchemy-reset").click()
    expect(page.locator("#alchemy-transform-count")).to_have_text(f"0/{recipe['step_count']}")
    expect(page.locator("#alchemy-memory-count")).to_have_text("1/3")
    for index, branch in enumerate(recipe["branches"]):
        expect(page.locator(f'.alchemy-item[data-slot="{index}"]')).to_have_attribute("data-state-id", branch["raw_state_id"])
    _shot(page, out_dir, mechanic, "recovered-raw-lot")

    transform_index = 0
    for branch_index, branch in enumerate(recipe["branches"]):
        for local_index, step in enumerate(branch["steps"]):
            _drag_slot_to(page, geometry, branch_index, str(step["station_id"]))
            expect(page.locator(f'[data-alchemy-station="{step["station_id"]}"]')).to_have_attribute("data-loaded", "true")
            page.locator(f'[data-cycle-station="{step["station_id"]}"]').click()
            transform_index += 1
            expect(page.locator("#alchemy-transform-count")).to_have_text(f"{transform_index}/{recipe['step_count']}", timeout=3_000)
            expect(page.locator(f'.alchemy-item[data-slot="{branch_index}"]')).to_have_attribute("data-state-id", step["output_state_id"])
            page.wait_for_timeout(110)
            if transform_index == 2:
                _shot(page, out_dir, mechanic, "visible-intermediate-lineage")
        expect(page.locator(f'.alchemy-item[data-slot="{branch_index}"]')).to_have_attribute("data-state-id", branch["terminal_state_id"])

    for branch_index in range(3):
        _drag_slot_to(page, geometry, branch_index, "assemble")
        expect(page.locator(f'.assembly-sockets > span:nth-child({branch_index + 1})')).to_have_attribute("data-filled", "true")
    _shot(page, out_dir, mechanic, "three-terminal-assembly")
    page.locator('[data-cycle-station="assemble"]').click()
    transform_index += 1
    expect(page.locator("#alchemy-transform-count")).to_have_text(f"{transform_index}/{recipe['step_count']}", timeout=3_000)
    expect(page.locator('.alchemy-item[data-slot="0"]')).to_have_attribute("data-state-id", recipe["device_state_id"])
    page.wait_for_timeout(140)

    _drag_slot_to(page, geometry, 0, "delivery")
    expect(page.locator(".alchemy-delivery-object .alchemy-item")).to_have_attribute("data-state-id", recipe["device_state_id"])
    _shot(page, out_dir, mechanic, "device-in-lineage-scanner")
    page.locator("#alchemy-verify").click()
    expect(page.locator(".alchemy-foot .readout")).to_have_text("PASS", timeout=10_000)
