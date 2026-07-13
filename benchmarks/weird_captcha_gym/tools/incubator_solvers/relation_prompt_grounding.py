from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "relation_prompt_grounding"


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_for_new_challenge(state_dir: Path, previous: str) -> str:
    deadline = time.time() + 8
    while time.time() < deadline:
        current = str(_read_json(state_dir / "ground_truth.json").get("challenge_id") or "")
        if current and current != previous:
            return current
        time.sleep(0.05)
    raise AssertionError("relation contract did not regenerate after failure")


def _stage_target(page, virtual_x: int, virtual_y: int, width: int, height: int) -> tuple[float, float]:
    box = page.locator(".rel-stage").bounding_box()
    if not box:
        raise AssertionError("relation assembly stage is not visible")
    return (
        box["x"] + virtual_x / width * box["width"],
        box["y"] + virtual_y / height * box["height"],
    )


def _drag_object(page, object_id: str, target: dict, stage: dict) -> None:
    locator = page.locator(f'.rel-object[data-object-id="{object_id}"]')
    box = locator.bounding_box()
    if not box:
        raise AssertionError(f"assembly object {object_id} is not visible")
    destination = _stage_target(page, int(target["x"]), int(target["y"]), int(stage["width"]), int(stage["height"]))
    page.mouse.move(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
    page.mouse.down()
    page.mouse.move(destination[0], destination[1], steps=9)
    page.mouse.up()


def _set_depth(page, object_id: str, depth: int) -> None:
    page.locator(f'.rel-console .rel-select[data-object-id="{object_id}"]').click()
    track = page.locator(".rel-depth-track").bounding_box()
    knob = page.locator(".rel-depth-knob").bounding_box()
    if not track or not knob:
        raise AssertionError("depth rail is not visible")
    target_y = track["y"] + (100 - depth) / 100 * track["height"]
    x = track["x"] + track["width"] / 2
    page.mouse.move(knob["x"] + knob["width"] / 2, knob["y"] + knob["height"] / 2)
    page.mouse.down()
    page.mouse.move(x, target_y, steps=7)
    page.mouse.up()


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read_json(state_dir / "ground_truth.json")["challenge_id"])
    page.locator(".rel-submit").click()
    _wait_for_new_challenge(state_dir, before)
    expect(page.locator(".relation-assembly-captcha[data-fresh-failure='true']")).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_contain_text("FAIL")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    stage = truth["stage"]

    # Exercise a real cancelled carry and recover through the visible reset control.
    first_id = truth["objects"][0]["id"]
    first = page.locator(f'.rel-object[data-object-id="{first_id}"]')
    box = first.bounding_box()
    carousel_target = _stage_target(page, 185, 405, int(stage["width"]), int(stage["height"]))
    if not box:
        raise AssertionError("carousel object is not visible for recovery check")
    page.mouse.move(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
    page.mouse.down()
    page.mouse.move(carousel_target[0], carousel_target[1], steps=4)
    page.mouse.up()
    expect(page.locator(".readout")).to_contain_text("DROP CANCELLED")
    page.locator(".rel-reset").click()
    expect(page.locator(".readout")).to_contain_text("ASSEMBLY RESET")

    solutions = truth["solution_positions"]
    # The frame goes down before any object that may need to sit inside it.
    ordered_ids = [item["id"] for item in truth["objects"] if item.get("container")]
    ordered_ids.extend(item["id"] for item in truth["objects"] if not item.get("container"))
    for object_id in ordered_ids:
        _drag_object(page, object_id, solutions[object_id], stage)

    expect(page.locator(".rel-placed-count[data-ready='true']")).to_contain_text("5/5")
    for object_id, target in solutions.items():
        if int(target["depth"]) != 50:
            _set_depth(page, object_id, int(target["depth"]))

    physical = page.evaluate("""() => ({
      drags: window.relationAssemblyModel.dragCount,
      dragSamples: window.relationAssemblyModel.dragSamples,
      depthSamples: window.relationAssemblyModel.depthSamples,
      depthDistance: window.relationAssemblyModel.depthDistance,
      resetCount: window.relationAssemblyModel.resetCount,
    })""")
    if physical["drags"] < 5 or physical["dragSamples"] < 15 or physical["depthSamples"] < 4 or physical["depthDistance"] < 45 or physical["resetCount"] < 1:
        raise AssertionError(f"relation workflow lacked required physical evidence: {physical}")

    page.locator(".rel-settle").click()
    page.wait_for_timeout(320)
    _screenshot(page, out_dir, mechanic, "active-settle-inspection")
    page.wait_for_function("() => window.relationAssemblyModel.settled === true", timeout=5_000)
    expect(page.locator(".rel-stage.is-settled")).to_be_visible()
    _screenshot(page, out_dir, mechanic, "solved-stable-graph")
    page.locator(".rel-submit").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
