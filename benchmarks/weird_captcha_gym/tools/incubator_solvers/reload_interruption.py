from __future__ import annotations

from pathlib import Path

from playwright.sync_api import expect

from benchmarks.weird_captcha_gym.tools.incubator_solvers.reviewed_overhaul_common import (
    center, expect_fail_and_fresh, read_json, shot,
)

MECHANIC_ID = "reload_interruption"
VECTORS = {"up": (0, -62), "right": (62, 0), "down": (0, 62), "left": (-62, 0)}


def _gesture(page, direction: str) -> None:
    lever = page.locator(".reload-v2-lever")
    x, y = center(lever)
    dx, dy = VECTORS[direction]
    page.mouse.move(x, y)
    page.mouse.down()
    page.mouse.move(x + dx, y + dy, steps=5)
    page.mouse.up()


def _clear_overload(page) -> None:
    spark = page.locator(".overload-spark")
    expect(spark).to_be_visible(timeout=3_000)
    x, y = center(spark)
    page.mouse.move(x, y)
    page.mouse.down()
    for _ in range(18):
        page.wait_for_timeout(78)
        x, y = center(spark)
        page.mouse.move(x, y, steps=1)
    page.mouse.up()
    expect(page.locator(".reload-overload")).to_have_count(0, timeout=3_000)


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    truth = read_json(state_dir / "ground_truth.json")
    before = truth["challenge_id"]
    expect(page.locator(".reload-v2.is-ready")).to_be_visible(timeout=8_000)
    wrong = next(item for item in VECTORS if item != truth["sequence"][0])
    _gesture(page, wrong)
    expect_fail_and_fresh(page, state_dir, before)
    shot(page, out_dir, mechanic, "real-memory-gesture-rejection")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    state = read_json(state_dir / "public_state.json")
    expect(page.locator(".reload-v2.is-ready")).to_be_visible(timeout=8_000)
    interruption_steps = {int(item["after_step"]) for item in state["interruptions"]}
    for index, direction in enumerate(state["sequence"], start=1):
        _gesture(page, direction)
        if index in interruption_steps:
            shot(page, out_dir, mechanic, f"moving-overload-{index}")
            _clear_overload(page)
