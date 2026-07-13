from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "top_face_dice_arithmetic"
OPPOSITE = {"N": "S", "E": "W", "S": "N", "W": "E"}
KEYS = {"N": "ArrowUp", "E": "ArrowRight", "S": "ArrowDown", "W": "ArrowLeft"}


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
    raise AssertionError("foundry failure did not issue a fresh challenge")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#foundry-weigh").click()
    _wait_fresh(state_dir, before)
    page.wait_for_selector('.foundry-scale[data-fresh-failure="true"]', timeout=7_000)
    page.wait_for_function("() => document.querySelector('.foundry-foot .readout')?.textContent.includes('FAIL')")
    _shot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    page.wait_for_function("() => !document.querySelector('.foundry-scale')?.classList.contains('is-failed')", timeout=4_000)
    truth = _read(state_dir / "ground_truth.json")
    first_id = truth["dice"][0]["id"]
    first_token = page.locator(f'[data-foundry-token="{first_id}"]')

    # Exercise a real rejected roll and prove the recoverable reset before solving.
    page.locator(f'[data-die-select="{first_id}"]').click()
    start_x, start_y = first_token.get_attribute("data-x"), first_token.get_attribute("data-y")
    page.keyboard.press("ArrowLeft")
    expect(page.locator(".foundry-foot .readout")).to_contain_text("RAIL STOP")
    if first_token.get_attribute("data-x") != start_x or first_token.get_attribute("data-y") != start_y:
        raise AssertionError("invalid foundry roll moved the selected die")
    _shot(page, out_dir, mechanic, "edge-invalid-roll")
    page.locator("#foundry-reset").click()
    expect(page.locator(".foundry-foot .readout")).to_contain_text("TABLE RESET")
    if page.locator('.foundry-die-token[data-visible="true"]').count() != 3:
        raise AssertionError("foundry reset did not restore all three initial top reveals")

    # The 180-degree table turn is meaningful: screen commands now map to the
    # opposite world directions used in the private solver-backed routes.
    page.locator("#foundry-view-rotate").click()
    expect(page.locator(".foundry-scale")).to_have_attribute("data-view", "2")
    _shot(page, out_dir, mechanic, "active-rotated-table")

    captured_hidden = False
    captured_scanner = False
    move_index = 0
    for plan in truth["solution_plans"]:
        die_id = str(plan["die_id"])
        page.locator(f'[data-die-select="{die_id}"]').click()
        token = page.locator(f'[data-foundry-token="{die_id}"]')
        for command_index, world_direction in enumerate(plan["world_directions"]):
            screen_direction = OPPOSITE[str(world_direction)]
            if move_index % 2 == 0:
                page.keyboard.press(KEYS[screen_direction])
            else:
                page.locator(f'#foundry-roll-{screen_direction.lower()}').click()
            page.wait_for_timeout(45)
            move_index += 1
            if not captured_hidden and command_index >= 1 and token.get_attribute("data-visible") == "false":
                _shot(page, out_dir, mechanic, "active-occluding-housing")
                captured_hidden = True
            if not captured_scanner and command_index >= 2 and token.get_attribute("data-visible") == "true" and token.get_attribute("data-docked") == "false":
                _shot(page, out_dir, mechanic, "active-scanner-reveal")
                captured_scanner = True
        expect(token).to_have_attribute("data-docked", "true")

    if page.locator('.foundry-die-token[data-docked="true"]').count() != 3:
        raise AssertionError("not all three foundry dice reached their scale docks")
    page.wait_for_timeout(340)
    _shot(page, out_dir, mechanic, "solved-three-docks")
    page.locator("#foundry-weigh").click()
    expect(page.locator(".foundry-scale")).to_have_attribute("data-settling", "true")
    page.wait_for_timeout(280)
    _shot(page, out_dir, mechanic, "active-balance-settle")
    expect(page.locator(".foundry-foot .readout")).to_have_text("PASS", timeout=10_000)
