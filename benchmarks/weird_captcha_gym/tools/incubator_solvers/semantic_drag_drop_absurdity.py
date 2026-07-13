from __future__ import annotations

from pathlib import Path

from benchmarks.weird_captcha_gym.tools.incubator_solvers.reviewed_overhaul_common import (
    drag, expect_fail_and_fresh, read_json, shot,
)

MECHANIC_ID = "semantic_drag_drop_absurdity"


def _probe(page, object_id: str, kind: str, hold: int) -> None:
    drag(page, page.locator(f'.probe-tool[data-probe="{kind}"]'), page.locator(f'[data-object-id="{object_id}"]'), steps=8, hold_ms=hold + 80)


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    before = read_json(state_dir / "ground_truth.json")["challenge_id"]
    page.locator(".causal-submit").click()
    expect_fail_and_fresh(page, state_dir, before)
    shot(page, out_dir, mechanic, "real-unprobed-rejection")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    state, truth = read_json(state_dir / "public_state.json"), read_json(state_dir / "ground_truth.json")
    for item in state["objects"]:
        _probe(page, item["id"], "thermal", int(state["probe_hold_ms"]))
        _probe(page, item["id"], "polarity", int(state["probe_hold_ms"]))
    shot(page, out_dir, mechanic, "physical-probe-response")
    for object_id, receiver_id in truth["expected_assignments"].items():
        drag(page, page.locator(f'[data-object-id="{object_id}"]'), page.locator(f'[data-receiver-id="{receiver_id}"]'), steps=10)
    page.locator(".causal-submit").click()
