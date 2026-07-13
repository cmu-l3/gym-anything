from __future__ import annotations

import math
from pathlib import Path

from benchmarks.weird_captcha_gym.tools.incubator_solvers.reviewed_overhaul_common import (
    drag_delta, expect_fail_and_fresh, read_json, shot,
)

MECHANIC_ID = "rotate_wrong_thing_upright"


def _solve_linear(matrix: list[list[float]], rhs: list[float]) -> list[float]:
    work = [row[:] + [rhs[index]] for index, row in enumerate(matrix)]
    for column in range(3):
        pivot = max(range(column, 3), key=lambda row: abs(work[row][column]))
        work[column], work[pivot] = work[pivot], work[column]
        scale = work[column][column]
        work[column] = [value / scale for value in work[column]]
        for row in range(3):
            if row == column:
                continue
            amount = work[row][column]
            work[row] = [work[row][index] - amount * work[column][index] for index in range(4)]
    return [work[index][3] for index in range(3)]


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    before = read_json(state_dir / "ground_truth.json")["challenge_id"]
    page.locator(".gimbal-submit").click()
    expect_fail_and_fresh(page, state_dir, before)
    shot(page, out_dir, mechanic, "real-single-view-rejection")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    contract = read_json(state_dir / "public_state.json")["gimbal"]
    for view in contract["views"]:
        page.locator(f'.gimbal-view[data-view="{view}"]').click()
    c = contract["coupling"]
    matrix = [[1, float(c["middle_to_outer"]), 0], [0, 1, float(c["inner_to_middle"])], [float(c["outer_to_inner"]), 0, 1]]
    initial = contract["initial"]
    deltas = _solve_linear(matrix, [-float(initial[axis]) for axis in ("outer", "middle", "inner")])
    for axis, degrees in zip(("outer", "middle", "inner"), deltas):
        if abs(degrees) > float(contract["max_drag_delta"]):
            raise AssertionError("generated gimbal correction exceeds one physical rail")
        drag_delta(page, page.locator(f'.gimbal-control[data-axis="{axis}"]'), degrees / float(contract["degrees_per_pixel"]), 0, maximum_step=20)
    shot(page, out_dir, mechanic, "tri-view-coupled-alignment")
    page.locator(".gimbal-submit").click()
