from __future__ import annotations

import json
from pathlib import Path


MECHANIC_ID = "input_lag_forklift"
KEYS = {
    "UP": "ArrowUp",
    "RIGHT": "ArrowRight",
    "DOWN": "ArrowDown",
    "LEFT": "ArrowLeft",
}


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = _read_json(state_dir / "ground_truth.json")["challenge_id"]
    page.locator("#forklift-certify").click()
    page.wait_for_function(
        "() => document.querySelector('.readout')?.textContent.includes('FAIL')",
        timeout=5000,
    )
    after = _read_json(state_dir / "ground_truth.json")["challenge_id"]
    if before == after:
        raise AssertionError("premature forklift certification did not generate a fresh challenge")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    route = [str(command) for command in truth["solution"]]
    if not route:
        raise AssertionError("generated forklift route is empty")
    initial_player = page.evaluate("() => [...window.inputLagForkliftModel.player]")
    for index, command in enumerate(route):
        if index % 2 == 0:
            page.keyboard.press(KEYS[command])
        else:
            page.locator(f'[data-command="{command}"]').click()
        page.wait_for_timeout(55)
        if index == 0:
            after_first = page.evaluate("() => [...window.inputLagForkliftModel.player]")
            pending = page.evaluate("() => window.inputLagForkliftModel.pending")
            if after_first != initial_player or pending != command:
                raise AssertionError("first direction did not behave as a queued no-op")
        if index == min(3, len(route) - 1):
            _screenshot(page, out_dir, mechanic, "active-delay")

    page.keyboard.press("f")
    page.wait_for_timeout(120)
    contract = page.evaluate(
        """() => ({
            pending: window.inputLagForkliftModel.pending,
            crates: window.inputLagForkliftModel.crates.length,
            docked: document.querySelectorAll('.forklift-cell.is-docked').length,
            last: window.inputLagForkliftModel.events.at(-1)?.issued,
        })"""
    )
    if contract["pending"] is not None or contract["last"] != "FLUSH" or contract["docked"] != contract["crates"]:
        raise AssertionError(f"forklift route did not finish docked with an empty queue: {contract}")
    _screenshot(page, out_dir, mechanic, "solved")
    page.locator("#forklift-certify").click()
    page.wait_for_function("() => document.querySelector('.readout')?.textContent === 'PASS'", timeout=5000)
