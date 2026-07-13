from __future__ import annotations

from pathlib import Path

from playwright.sync_api import expect

from benchmarks.weird_captcha_gym.tools.incubator_solvers.reviewed_overhaul_common import (
    center, expect_fail_and_fresh, read_json, shot,
)

MECHANIC_ID = "popup_exorcist"


def _provoke(page, state: dict, parasite: str) -> None:
    parasite_z = next(int(item["z"]) for item in state["popups"] if item["id"] == parasite)
    for item in sorted(state["popups"], key=lambda value: int(value["z"]), reverse=True):
        if int(item["z"]) > parasite_z:
            page.locator(f'[data-window-id="{item["id"]}"] .parasite-close').click()
    page.locator(f'[data-window-id="{parasite}"] .parasite-close').click()
    expect(page.locator(".containment-well[data-active='true']")).to_be_visible()


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    state, truth = read_json(state_dir / "public_state.json"), read_json(state_dir / "ground_truth.json")
    before = truth["challenge_id"]
    _provoke(page, state, truth["parasite_id"])
    close = page.locator(f'[data-window-id="{truth["parasite_id"]}"] .parasite-close')
    for _ in range(3):
        close.click()
    expect_fail_and_fresh(page, state_dir, before)
    shot(page, out_dir, mechanic, "real-parasite-resistance")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    state, truth = read_json(state_dir / "public_state.json"), read_json(state_dir / "ground_truth.json")
    _provoke(page, state, truth["parasite_id"])
    shot(page, out_dir, mechanic, "replication-discovered")
    echo = page.locator(f'[data-window-id="{truth["echo_ids"][0]}"]')
    header = echo.locator("header")
    well = page.locator(".containment-well")
    sx, sy = center(header)
    wx, wy = center(well)
    echo_box = echo.bounding_box()
    header_box = header.bounding_box()
    assert echo_box and header_box
    end = (wx + (sx - (echo_box["x"] + echo_box["width"] / 2)), wy + (sy - (echo_box["y"] + echo_box["height"] / 2)))
    page.mouse.move(sx, sy)
    page.mouse.down()
    page.mouse.move(*end, steps=12)
    page.mouse.up()
