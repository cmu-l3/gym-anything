from __future__ import annotations

import json
import time
from pathlib import Path


MECHANIC_ID = "minecraft_block_grid"
INTERNAL_WIDTH = 900
INTERNAL_HEIGHT = 500


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
    raise AssertionError("voxel failure did not issue a fresh challenge")


def _click_internal(page, point: list[float]) -> None:
    canvas = page.locator("#voxel-canvas")
    box = canvas.bounding_box()
    if not box:
        raise AssertionError("voxel canvas has no physical geometry")
    page.mouse.click(
        box["x"] + float(point[0]) / INTERNAL_WIDTH * box["width"],
        box["y"] + float(point[1]) / INTERNAL_HEIGHT * box["height"],
    )
    page.wait_for_timeout(65)


def _rotate_to(page, current: int, target: int) -> int:
    while current != target:
        page.locator("#voxel-right").click()
        current = (current + 1) % 4
        page.wait_for_timeout(45)
    return current


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#voxel-exit").click()
    _wait_fresh(state_dir, before)
    page.wait_for_selector('.voxel-mine[data-fresh-failure="true"]', timeout=7_000)
    page.wait_for_function("() => document.querySelector('.readout')?.textContent.includes('FAIL')")
    _shot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    starting_durability = int(truth["starting_durability"])
    # Exercise a legal but damaging lava ray, then prove the local rebuild path
    # restores the exact initial mine before the successful extraction.
    edge = truth["edge_case_hit"]
    _click_internal(page, edge["click"])
    current_durability = page.evaluate("() => Number(window.document.getElementById('voxel-durability-value').textContent.split('/')[0].trim())")
    if current_durability != starting_durability - 1:
        raise AssertionError("lava edge case did not consume one durability")
    _shot(page, out_dir, mechanic, "edge-lava-strike")
    page.locator("#voxel-reset").click()
    page.wait_for_timeout(80)
    restored = page.evaluate("() => Number(window.document.getElementById('voxel-durability-value').textContent.split('/')[0].trim())")
    if restored != starting_durability:
        raise AssertionError("mine rebuild did not restore durability")

    orientation = int(truth["starting_orientation"])
    for index, step in enumerate(truth["solution_steps"]):
        orientation = _rotate_to(page, orientation, int(step["orientation"]))
        _click_internal(page, step["click"])
        if index == 0:
            _shot(page, out_dir, mechanic, "active-blocker-removal")
        if step["kind"] == "extract" and index < 4:
            _shot(page, out_dir, mechanic, "active-diamond-extraction")
    inventory = page.locator('#voxel-inventory li[data-filled="true"]').count()
    if inventory != len(truth["diamond_ids"]):
        raise AssertionError(f"voxel extraction collected {inventory}/{len(truth['diamond_ids'])} diamonds")
    _shot(page, out_dir, mechanic, "solved-pre-exit")
    page.locator("#voxel-exit").click()
    page.wait_for_function("() => document.querySelector('.readout')?.textContent === 'PASS'", timeout=8_000)
