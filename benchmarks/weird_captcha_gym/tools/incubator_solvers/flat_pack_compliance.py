from __future__ import annotations

import json
import math
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "flat_pack_compliance"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, name: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True); page.screenshot(path=str(out_dir / f"{mechanic}-{name}.png"), full_page=True)


def _wait_new(state_dir: Path, previous: str) -> None:
    deadline = time.time() + 8
    while time.time() < deadline:
        if str(_read(state_dir / "ground_truth.json").get("challenge_id")) != previous: return
        time.sleep(.05)
    raise AssertionError("flat-pack challenge did not regenerate after rejection")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID: raise AssertionError(mechanic)
    # Prove the reversible physical failure path on the kit that will be
    # discarded. The later passing assembly should not be forced to sabotage
    # itself merely to satisfy smoke coverage.
    _mate(page, "wing-l", "wing-r"); expect(page.locator(".readout")).to_contain_text("REJECTED")
    page.locator(".flat-load").click(); expect(page.locator(".flat-failure[data-visible='true']")).to_be_visible(); _shot(page, out_dir, mechanic, "wrong-joint-load-failure")
    page.locator(".flat-reset").click(); expect(page.locator(".readout")).to_contain_text("REWOUND")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator(".flat-submit").click(); _wait_new(state_dir, before)
    expect(page.locator(".flat-pack-captcha[data-fresh-failure='true']")).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_contain_text("FAIL"); _shot(page, out_dir, mechanic, "fail-fresh-kit")


def _screen(box: dict, stage: dict, point: list[float]) -> tuple[float, float]:
    return box["x"] + point[0] / stage["width"] * box["width"], box["y"] + point[1] / stage["height"] * box["height"]


def _angle_steps(current: float, target: float) -> int:
    return min(range(4), key=lambda count: abs(((current + count * math.pi / 2 - target + math.pi) % (2 * math.pi)) - math.pi))


def _select_only(page, part_id: str) -> None:
    selected = page.evaluate("() => [...window.flatPackComplianceModel.selected]")
    for active in selected:
        page.locator(f'.flat-part-chip[data-part-id="{active}"]').click()
    page.locator(f'.flat-part-chip[data-part-id="{part_id}"]').click()


def _rotate_to_target(page, part: dict) -> None:
    current = page.evaluate("part => window.flatPackComplianceModel.bodies.find(body => body.label === part).angle", part["id"])
    steps = _angle_steps(float(current), float(part["target_pose"][2]))
    if steps:
        _select_only(page, part["id"])
        for _ in range(steps): page.locator(".flat-rotate-right").click()


def _drag_to(page, box: dict, stage: dict, part: dict) -> None:
    for _attempt in range(4):
        current = page.evaluate("part => { const b=window.flatPackComplianceModel.bodies.find(body=>body.label===part); return [b.position.x,b.position.y]; }", part["id"])
        if math.hypot(current[0] - part["target_pose"][0], current[1] - part["target_pose"][1]) <= 4.5: return
        page.mouse.move(*_screen(box, stage, current)); page.mouse.down()
        page.mouse.move(*_screen(box, stage, part["target_pose"][:2]), steps=24); page.wait_for_timeout(460); page.mouse.up(); page.wait_for_timeout(120)
    current = page.evaluate("part => { const b=window.flatPackComplianceModel.bodies.find(body=>body.label===part); return [b.position.x,b.position.y]; }", part["id"])
    if math.hypot(current[0] - part["target_pose"][0], current[1] - part["target_pose"][1]) > 16:
        raise AssertionError(f"{part['id']} failed to settle at keyed target: {current} vs {part['target_pose']}")


def _mate(page, first: str, second: str) -> None:
    selected = page.evaluate("() => [...window.flatPackComplianceModel.selected]")
    for active in selected: page.locator(f'.flat-part-chip[data-part-id="{active}"]').click()
    page.locator(f'.flat-part-chip[data-part-id="{first}"]').click(); page.locator(f'.flat-part-chip[data-part-id="{second}"]').click(); page.locator(".flat-mate").click()


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID: raise AssertionError(mechanic)
    truth = _read(state_dir / "ground_truth.json"); stage = truth["stage"]; box = page.locator(".flat-canvas").bounding_box()
    if not box: raise AssertionError("flat-pack Matter canvas missing")
    parts = {part["id"]: part for part in truth["parts"]}
    for part in truth["parts"]:
        _rotate_to_target(page, part); _drag_to(page, box, stage, part); _rotate_to_target(page, part)
    for joint in truth["joints"]:
        _mate(page, str(joint["a"]), str(joint["b"]))
    _shot(page, out_dir, mechanic, "physical-assembly-aligned")
    expected_count = len(truth["joints"])
    expect(page.locator(".flat-graph-value")).to_have_text(f"{expected_count}/{expected_count}")
    physical = page.evaluate("() => ({contacts:window.flatPackComplianceModel.contacts,joints:[...window.flatPackComplianceModel.connected].sort(),poses:Object.fromEntries(window.flatPackComplianceModel.bodies.map(b=>[b.label,[b.position.x,b.position.y,b.angle]]))})")
    if physical["joints"] != sorted(str(item["id"]) for item in truth["joints"]): raise AssertionError(f"real joint graph incomplete: {physical}")
    page.locator(".flat-load").click(); expect(page.locator(".flat-stage.under-load")).to_be_visible(); page.wait_for_timeout(700); _shot(page, out_dir, mechanic, "oscillating-load-live")
    expect(page.locator(".flat-complete[data-visible='true']")).to_be_visible(timeout=5_000); expect(page.locator(".readout")).to_contain_text("SURVIVED")
    finished = page.evaluate("() => ({completed:window.flatPackComplianceModel.completed,ticks:window.flatPackComplianceModel.loadTick,max:window.flatPackComplianceModel.maxStrain,resets:window.flatPackComplianceModel.resets,rejected:window.flatPackComplianceModel.rejected})")
    if not finished["completed"] or finished["ticks"] != len(truth["load_steps"]) or finished["resets"] != 0 or finished["rejected"] != 0: raise AssertionError(f"flat-pack clean physical run incomplete: {finished}")
    _shot(page, out_dir, mechanic, "solved-pre-submit"); page.locator(".flat-submit").click(); expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
