from __future__ import annotations

from pathlib import Path

from benchmarks.weird_captcha_gym.tools.incubator_solvers.reviewed_overhaul_common import (
    drag_delta, expect_fail_and_fresh, read_json, shot,
)

MECHANIC_ID = "wonky_text_hostile_rendering"


def _short_delta(target: float, initial: float) -> float:
    return (target - initial + 180) % 360 - 180


def _lock_all(page, press: dict) -> None:
    for plate in press["plates"]:
        page.locator(f'.plate-lock[data-plate-id="{plate["id"]}"]').click()


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    state = read_json(state_dir / "public_state.json")
    before = state["challenge_id"]
    _lock_all(page, state["press"])
    page.locator(".registration-press").click()
    expect_fail_and_fresh(page, state_dir, before)
    shot(page, out_dir, mechanic, "real-misaligned-press-rejection")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    press = read_json(state_dir / "public_state.json")["press"]
    for plate in press["plates"]:
        degrees = _short_delta(float(plate["target"]), float(plate["initial"]))
        drag_delta(page, page.locator(f'.registration-wheel[data-plate-id="{plate["id"]}"]'), degrees / float(press["degrees_per_pixel"]), 0, maximum_step=20)
        page.locator(f'.plate-lock[data-plate-id="{plate["id"]}"]').click()
    shot(page, out_dir, mechanic, "registered-three-plate-image")
    page.locator(".registration-press").click()
