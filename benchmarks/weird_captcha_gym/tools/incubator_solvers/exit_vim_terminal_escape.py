from __future__ import annotations

import json
import time
from pathlib import Path


MECHANIC_ID = "exit_vim_terminal_escape"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_for_fresh(state_dir: Path, previous: str) -> str:
    deadline = time.time() + 8
    while time.time() < deadline:
        current = str(_read(state_dir / "ground_truth.json").get("challenge_id") or "")
        if current and current != previous:
            return current
        time.sleep(0.05)
    raise AssertionError("terminal failure did not regenerate a fresh challenge")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#terminal-verify").click()
    _wait_for_fresh(state_dir, before)
    page.wait_for_selector('.terminal-escape[data-fresh-failure="true"]', timeout=7_000)
    page.wait_for_function("() => document.querySelector('.readout')?.textContent.includes('FAIL')")
    _shot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    public = _read(state_dir / "public_state.json")
    if truth["challenge_id"] != public["challenge_id"]:
        raise AssertionError("terminal public/private challenge mismatch")
    page.locator(".terminal-escape").click(position={"x": 420, "y": 250})
    page.keyboard.press("g")
    page.keyboard.press("g")
    for index, line in enumerate(truth["target_buffer"]):
        page.keyboard.press("c")
        page.keyboard.press("c")
        page.keyboard.type(str(line), delay=2)
        page.keyboard.press("Escape")
        if index == 1:
            _shot(page, out_dir, mechanic, "active-editor-repair")
        if index < len(truth["target_buffer"]) - 1:
            page.keyboard.press("j")
    buffer_state = page.evaluate("() => [...window.exitVimTerminalModel.buffer]")
    if buffer_state != truth["target_buffer"]:
        raise AssertionError(f"physical editor repair diverged: {buffer_state!r}")

    page.keyboard.type(":wq", delay=20)
    page.keyboard.press("Enter")
    page.wait_for_timeout(90)
    if page.evaluate("() => window.exitVimTerminalModel.saved") is not True:
        raise AssertionError(":wq did not save and exit the repaired buffer")

    for index, layer in enumerate(truth["layer_order"]):
        page.wait_for_function("layer => document.getElementById('terminal-viewport')?.dataset.layer === layer", arg=layer)
        if index == 0:
            _shot(page, out_dir, mechanic, f"active-{layer}-layer")
        if index == len(truth["layer_order"]) - 1:
            _shot(page, out_dir, mechanic, "solved-pre-final-exit")
        if layer == "pager":
            page.keyboard.press("q")
        elif layer == "job":
            page.keyboard.press("Control+c")
        elif layer == "ssh":
            page.keyboard.type("exit", delay=25)
            page.keyboard.press("Enter")
        else:
            raise AssertionError(f"unknown generated terminal layer {layer!r}")
        page.wait_for_timeout(90)
    page.wait_for_function("() => document.querySelector('.readout')?.textContent === 'PASS'", timeout=8_000)
