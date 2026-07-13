from __future__ import annotations

import json
from pathlib import Path


MECHANIC_ID = "exact_change_candy_cascade"


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _click_cell(page, coordinate: list[int]) -> None:
    row, column = (int(coordinate[0]), int(coordinate[1]))
    page.locator(f'.candy-cell[data-row="{row}"][data-column="{column}"]').click()


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    before = str(truth["challenge_id"])
    row, column = (int(value) for value in truth["forbidden_position"])
    if column + 1 < 5:
        neighbor = [row, column + 1]
    elif column > 0:
        neighbor = [row, column - 1]
    elif row + 1 < 5:
        neighbor = [row + 1, column]
    else:
        neighbor = [row - 1, column]
    _click_cell(page, [row, column])
    _click_cell(page, neighbor)
    page.wait_for_function(
        "() => document.querySelector('.readout')?.textContent.includes('FAIL')",
        timeout=8000,
    )
    after = _read_json(state_dir / "ground_truth.json")["challenge_id"]
    if before == after:
        raise AssertionError("forbidden candy did not generate a fresh challenge")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    swaps = truth.get("solution_swaps") or []
    if len(swaps) != 2:
        raise AssertionError(f"expected a two-swap solution, got {swaps!r}")
    for index, swap in enumerate(swaps, start=1):
        _click_cell(page, swap[0])
        _click_cell(page, swap[1])
        page.wait_for_function(
            "expected => !window.exactChangeCandyModel.busy && window.exactChangeCandyModel.validMoves === expected",
            arg=index,
            timeout=12000,
        )
        if index == 1:
            _screenshot(page, out_dir, mechanic, "active-cascade")
    contract = page.evaluate(
        """() => ({
          ready: window.exactChangeCandyModel.ready,
          score: window.exactChangeCandyModel.score,
          target: Number(window.exactChangeCandyModel.state.target_score),
          moves: window.exactChangeCandyModel.validMoves,
          forbidden: window.exactChangeCandyModel.forbiddenActivated,
        })"""
    )
    if not contract["ready"] or contract["score"] != contract["target"] or contract["moves"] != 2 or contract["forbidden"]:
        raise AssertionError(f"candy route did not reach an exact safe receipt: {contract}")
    _screenshot(page, out_dir, mechanic, "solved")
    page.locator("#candy-certify").click()
    page.wait_for_function("() => document.querySelector('.readout')?.textContent === 'PASS'", timeout=8000)
