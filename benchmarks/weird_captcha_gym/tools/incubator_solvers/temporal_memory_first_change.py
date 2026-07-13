from __future__ import annotations

from pathlib import Path

from playwright.sync_api import expect

from benchmarks.weird_captcha_gym.tools.incubator_solvers.reviewed_overhaul_common import (
    expect_fail_and_fresh, read_json, shot,
)

MECHANIC_ID = "temporal_memory_first_change"


def _select_settled(page, timeline: dict, object_id: str) -> None:
    index = timeline["settle_order"].index(object_id)
    x, y = 70 + index * 93, 150 + (index % 2) * 68
    box = page.locator(".tracking-canvas").bounding_box()
    assert box
    page.mouse.click(box["x"] + x / 700 * box["width"], box["y"] + y / 330 * box["height"])


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    state, truth = read_json(state_dir / "public_state.json"), read_json(state_dir / "ground_truth.json")
    before, timeline = truth["challenge_id"], state["timeline"]
    page.locator(".tracking-arm").click()
    expect(page.locator('.tracking-stage[data-settled="true"]')).to_be_visible(timeout=12_000)
    wrong = next(item["id"] for item in timeline["objects"] if item["id"] != truth["target_object_id"])
    _select_settled(page, timeline, wrong)
    expect_fail_and_fresh(page, state_dir, before)
    shot(page, out_dir, mechanic, "real-wrong-carrier-rejection")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    state, truth = read_json(state_dir / "public_state.json"), read_json(state_dir / "ground_truth.json")
    timeline, target = state["timeline"], truth["target_object_id"]
    page.locator(".tracking-arm").click()
    event = timeline["events"][0]
    target_spec = next(item for item in timeline["objects"] if item["id"] == target)
    # Track the highlighted carrier with the actual cursor lens through the first
    # transient and into the decoy period; no DOM answer marker exists.
    canvas = page.locator(".tracking-canvas")
    box = canvas.bounding_box()
    assert box
    for elapsed in range(int(event["at_ms"]) - int(timeline["pulse_lead_ms"]), int(event["at_ms"]) + int(event["duration_ms"]) + 1, 90):
        page.wait_for_timeout(90 if elapsed > int(event["at_ms"]) - int(timeline["pulse_lead_ms"]) else max(0, elapsed))
        x = float(target_spec["x0"]) + __import__("math").sin(float(target_spec["phase"]) + elapsed * float(target_spec["rate_x"])) * float(target_spec["amp_x"])
        y = float(target_spec["y0"]) + __import__("math").cos(float(target_spec["phase"]) * .83 + elapsed * float(target_spec["rate_y"])) * float(target_spec["amp_y"])
        page.mouse.move(box["x"] + x / 700 * box["width"], box["y"] + y / 330 * box["height"], steps=2)
    shot(page, out_dir, mechanic, "active-lens-first-transient")
    expect(page.locator('.tracking-stage[data-settled="true"]')).to_be_visible(timeout=10_000)
    _select_settled(page, timeline, target)
