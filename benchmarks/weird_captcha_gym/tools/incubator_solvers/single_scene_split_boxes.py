from __future__ import annotations

import json
from pathlib import Path


MECHANIC_ID = "single_scene_split_boxes"


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _hold_sync(page, milliseconds: int = 780) -> None:
    button = page.locator("#mosaic-sync")
    box = button.bounding_box()
    if box is None:
        raise AssertionError("scene sync control has no visible bounds")
    x = box["x"] + box["width"] / 2
    y = box["y"] + box["height"] / 2
    page.mouse.move(x, y)
    page.mouse.down()
    page.wait_for_timeout(milliseconds)
    page.mouse.up()


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = _read_json(state_dir / "ground_truth.json")["challenge_id"]
    _hold_sync(page, 760)
    page.wait_for_function(
        "() => document.querySelector('.readout')?.textContent.includes('FAIL')",
        timeout=8000,
    )
    after = _read_json(state_dir / "ground_truth.json")["challenge_id"]
    if before == after:
        raise AssertionError("premature scene sync did not generate fresh channels")
    page.wait_for_timeout(240)
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    tiles = list(truth["tiles"])
    slots: list[str | None] = [None] * 9
    for tile in tiles:
        slots[int(tile["initial_slot"])] = str(tile["id"])
    if any(tile_id is None for tile_id in slots):
        raise AssertionError("generated mosaic has an empty slot")
    slots = [str(tile_id) for tile_id in slots]
    desired = {
        int(tile["source"]["row"]) * 3 + int(tile["source"]["column"]): str(tile["id"])
        for tile in tiles
    }
    swap_count = 0
    for destination in range(9):
        tile_id = desired[destination]
        if slots[destination] == tile_id:
            continue
        origin = slots.index(tile_id)
        displaced = slots[destination]
        page.locator(f'.mosaic-tile[data-tile-id="{tile_id}"]').drag_to(
            page.locator(f'.mosaic-tile[data-tile-id="{displaced}"]')
        )
        page.wait_for_function(
            "({tileId, slot}) => window.singleSceneSplitBoxesModel.slots[slot] === tileId",
            arg={"tileId": tile_id, "slot": destination},
            timeout=4000,
        )
        slots[origin], slots[destination] = slots[destination], slots[origin]
        swap_count += 1
        if swap_count == 3:
            _screenshot(page, out_dir, mechanic, "active-spatial")

    for tile in tiles:
        if int(tile["initial_rotation"]) != 180:
            continue
        tile_id = str(tile["id"])
        page.locator(f'.mosaic-tile[data-tile-id="{tile_id}"]').click()
        page.locator("#mosaic-rotate").click()
        page.wait_for_function(
            "tileId => window.singleSceneSplitBoxesModel.rotations[tileId] === 0",
            arg=tile_id,
            timeout=2000,
        )

    phase_tiles = [tile for tile in tiles if int(tile["initial_phase"]) != 0]
    for index, tile in enumerate(phase_tiles):
        tile_id = str(tile["id"])
        page.locator(f'.mosaic-tile[data-tile-id="{tile_id}"]').click()
        track = page.locator("#phase-track")
        box = track.bounding_box()
        if box is None:
            raise AssertionError("temporal scrub track has no visible bounds")
        page.mouse.click(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
        page.wait_for_function(
            "tileId => window.singleSceneSplitBoxesModel.phases[tileId] === 0",
            arg=tile_id,
            timeout=2000,
        )
        if index == min(3, len(phase_tiles) - 1):
            _screenshot(page, out_dir, mechanic, "active-temporal")

    page.wait_for_function("() => document.querySelectorAll('.mosaic-errors > div.is-clear').length === 4", timeout=4000)
    proof = page.evaluate(
        """() => ({
          spatial: window.singleSceneSplitBoxesModel.spatialTouched.size,
          rotation: window.singleSceneSplitBoxesModel.rotationTouched.size,
          phase: window.singleSceneSplitBoxesModel.phaseTouched.size,
          errors: [...document.querySelectorAll('.mosaic-errors > div:not(.is-clear)')].length,
        })"""
    )
    requirements = truth["requirements"]
    if proof["spatial"] < int(requirements["minimum_spatial_touches"]):
        raise AssertionError(f"spatial operation proof is incomplete: {proof}")
    if proof["rotation"] < int(requirements["minimum_rotation_touches"]):
        raise AssertionError(f"rotation operation proof is incomplete: {proof}")
    if proof["phase"] < int(requirements["minimum_phase_touches"]):
        raise AssertionError(f"temporal operation proof is incomplete: {proof}")
    page.wait_for_timeout(180)
    _screenshot(page, out_dir, mechanic, "coherent")
    _hold_sync(page, 790)
    page.wait_for_function("() => document.querySelector('.readout')?.textContent === 'PASS'", timeout=8000)
