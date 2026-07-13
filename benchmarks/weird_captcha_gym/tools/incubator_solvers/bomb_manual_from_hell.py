from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "bomb_manual_from_hell"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_new(state_dir: Path, previous: str) -> None:
    deadline = time.time() + 8
    while time.time() < deadline:
        current = str(_read(state_dir / "ground_truth.json").get("challenge_id") or "")
        if current and current != previous:
            return
        time.sleep(.05)
    raise AssertionError("acetate bomb challenge did not regenerate")


def _screen(box: dict, stage: dict, x: float, y: float) -> tuple[float, float]:
    return (
        box["x"] + x / float(stage["width"]) * box["width"],
        box["y"] + y / float(stage["height"]) * box["height"],
    )


def _drag_plate(page, box: dict, stage: dict, plate_id: str, target: dict) -> None:
    current = page.evaluate("plateId => { const p=window.bombManualAcetateModel.poses[plateId]; return {x:p.x,y:p.y}; }", plate_id)
    page.mouse.move(*_screen(box, stage, current["x"], current["y"]))
    page.mouse.down()
    page.mouse.move(*_screen(box, stage, float(target["x"]), float(target["y"])), steps=26)
    page.wait_for_timeout(180)
    page.mouse.up()
    page.wait_for_timeout(80)


def _orient_plate(page, plate: dict, target: dict) -> None:
    current = page.evaluate("plateId => window.bombManualAcetateModel.poses[plateId]", plate["id"])
    if bool(current["flipped"]) != bool(target["flipped"]):
        page.locator('[data-transform="flip"]').click()
    step = 45
    turns = int(((int(target["angle_deg"]) - int(current["angle_deg"])) % 360) / step)
    for _ in range(turns):
        page.locator('[data-transform="rotate-right"]').click()


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(mechanic)
    truth = _read(state_dir / "ground_truth.json")
    before = str(truth["challenge_id"])
    plate = truth["plates"][0]
    target = truth["target_poses"][plate["id"]]
    box = page.locator("#bomb-acetate-canvas").bounding_box()
    if not box:
        raise AssertionError("acetate workbench canvas is not visible")
    _drag_plate(page, box, truth["stage"], plate["id"], target)
    current = page.evaluate("plateId => window.bombManualAcetateModel.poses[plateId]", plate["id"])
    if int(current["angle_deg"]) == int(target["angle_deg"]) and bool(current["flipped"]) == bool(target["flipped"]):
        page.locator('[data-transform="rotate-right"]').click()
    page.locator("#bomb-seat-plate").click()
    expect(page.locator(".bomb-foot .readout")).to_contain_text("KEYHOLES MISS")
    _shot(page, out_dir, mechanic, "local-keyhole-miss")
    page.locator('[data-transform="reset"]').click()
    page.locator("#bomb-reissue").click()
    _wait_new(state_dir, before)
    expect(page.locator('.bomb-manual-captcha[data-fresh-failure="true"]')).to_be_visible(timeout=8_000)
    expect(page.locator(".bomb-foot .readout")).to_contain_text("FAIL")
    _shot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(mechanic)
    truth = _read(state_dir / "ground_truth.json")
    box = page.locator("#bomb-acetate-canvas").bounding_box()
    if not box:
        raise AssertionError("acetate workbench canvas is not visible")
    for index, plate in enumerate(truth["plates"]):
        page.locator(f'.bomb-plate-card[data-plate-id="{plate["id"]}"]').click()
        target = truth["target_poses"][plate["id"]]
        _orient_plate(page, plate, target)
        _drag_plate(page, box, truth["stage"], plate["id"], target)
        if index == 0:
            _shot(page, out_dir, mechanic, "active-first-acetate-alignment")
        page.locator("#bomb-seat-plate").click()
        expect(page.locator(f'.bomb-plate-card[data-plate-id="{plate["id"]}"]')).to_have_attribute("data-locked", "true")
    plate_count = len(truth["plates"])
    expect(page.locator(".bomb-status-count b")).to_have_text(f"{plate_count} / {plate_count}")
    _shot(page, out_dir, mechanic, "all-plate-aperture-intersection")

    wire = next(item for item in truth["wires"] if item["id"] == truth["correct_wire_id"])
    page.mouse.click(*_screen(box, truth["stage"], float(truth["observation_x"]), float(wire["y"])))
    expect(page.locator(".bomb-selected-wire")).to_contain_text("SELECTED")
    expect(page.locator(".bomb-cut-button")).to_be_enabled()
    _shot(page, out_dir, mechanic, "correct-wire-selected")
    page.locator(".bomb-cut-button").click()
    expect(page.locator(".bomb-foot .readout")).to_have_text("PASS", timeout=8_000)
    result = _read(state_dir / "result.json")
    locks = [event for event in result.get("events") or [] if event.get("type") == "plate_lock"]
    cuts = [event for event in result.get("events") or [] if event.get("type") == "cut"]
    if len(locks) != plate_count or not all(event.get("accepted") is True for event in locks) or len(cuts) != 1 or result.get("misseat_count") != 0:
        raise AssertionError("clean acetate defusal transcript is not exact")
