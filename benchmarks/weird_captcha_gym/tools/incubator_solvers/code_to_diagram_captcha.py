from __future__ import annotations

import json
import time
from pathlib import Path


MECHANIC_ID = "code_to_diagram_captcha"


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
    raise AssertionError("control-flow failure did not regenerate a fresh challenge")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#flow-certify").click()
    _wait_for_fresh(state_dir, before)
    page.wait_for_selector('.flow-lab[data-fresh-failure="true"]', timeout=7_000)
    page.wait_for_function("() => document.querySelector('.readout')?.textContent.includes('FAIL')")
    _shot(page, out_dir, mechanic, "fail-refresh")


def _drag(page, source_selector: str, target_selector: str) -> None:
    source = page.locator(source_selector)
    target = page.locator(target_selector)
    source.scroll_into_view_if_needed()
    target.scroll_into_view_if_needed()
    start = source.bounding_box()
    end = target.bounding_box()
    if not start or not end:
        raise AssertionError(f"missing drag geometry for {source_selector} -> {target_selector}")
    sx, sy = start["x"] + start["width"] / 2, start["y"] + start["height"] / 2
    tx, ty = end["x"] + end["width"] / 2, end["y"] + end["height"] / 2
    page.mouse.move(sx, sy)
    page.mouse.down()
    page.mouse.move((sx + tx) / 2, (sy + ty) / 2, steps=8)
    page.mouse.move(tx, ty, steps=8)
    page.mouse.up()


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    public = _read(state_dir / "public_state.json")
    if truth["challenge_id"] != public["challenge_id"]:
        raise AssertionError("control-flow public/private challenge mismatch")

    index_by_input = {int(value): index for index, value in enumerate(public["probe_inputs"])}
    for run_index, expected_run in enumerate(truth["expected_probe_runs"]):
        probe = int(expected_run["input"])
        page.locator(f'[data-probe-index="{index_by_input[probe]}"]').click()
        for step_index, _step in enumerate(expected_run["steps"]):
            page.locator("#flow-step").click()
            page.wait_for_timeout(45)
            if run_index == 1 and step_index == 1:
                _shot(page, out_dir, mechanic, "active-transient-debugger")
        page.wait_for_timeout(40)
    counts = page.evaluate("""() => ({
      probes: window.document.querySelectorAll('[data-probe-index][data-status="done"]').length,
      coverage: Number(document.getElementById('flow-coverage-count')?.textContent.split('/')[0].trim()),
    })""")
    if counts != {"probes": 3, "coverage": 6}:
        raise AssertionError(f"debugger coverage did not complete: {counts}")

    for index, edge in enumerate(truth["expected_edges"]):
        _drag(
            page,
            f'[data-port-id="{edge["from_port"]}"]',
            f'.flow-port-in[data-node-id="{edge["to_node"]}"]',
        )
        page.wait_for_timeout(45)
        if index == 2:
            _shot(page, out_dir, mechanic, "active-wiring")
    wire_count = page.locator("#flow-wire-ledger li:not(.is-empty)").count()
    if wire_count != len(truth["expected_edges"]):
        raise AssertionError(f"physical patching produced {wire_count} wires, expected {len(truth['expected_edges'])}")
    _shot(page, out_dir, mechanic, "solved-pre-submit")
    page.locator("#flow-certify").click()
    page.wait_for_function("() => document.querySelector('.readout')?.textContent === 'PASS'", timeout=8_000)
