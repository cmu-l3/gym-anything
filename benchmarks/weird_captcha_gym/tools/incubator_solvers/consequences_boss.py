from __future__ import annotations

from pathlib import Path

from playwright.sync_api import expect

from benchmarks.weird_captcha_gym.tools.incubator_solvers.reviewed_overhaul_common import (
    center, drag, expect_fail_and_fresh, read_json, shot,
)

MECHANIC_ID = "consequences_boss"


def _seal(page, quadrant: int) -> None:
    seal = page.locator(".covenant-seal")
    cx, cy = center(seal)
    points = ((cx, cy - 32), (cx + 32, cy), (cx, cy + 32), (cx - 32, cy))
    page.mouse.move(*points[quadrant])
    page.mouse.down()
    page.mouse.move(*points[quadrant], steps=2)
    page.mouse.up()


def _answer(page, socket: str, seal: int) -> None:
    drag(page, page.locator(".covenant-relic"), page.locator(f'.covenant-socket[data-socket="{socket}"]'), steps=9)
    _seal(page, seal)
    page.locator(".covenant-bind").click()


def _commitments(state: dict) -> dict[str, tuple[str, int]]:
    return {scene["id"]: ("left" if index % 2 == 0 else "right", (int(scene["initial_seal"]) + index + 1) % 4) for index, scene in enumerate(state["scenes"])}


def _make(page, state: dict) -> dict[str, tuple[str, int]]:
    choices = _commitments(state)
    for scene in state["scenes"]:
        _answer(page, *choices[scene["id"]])
    expect(page.locator(".covenant-phase")).to_contain_text("RECKONING", timeout=6_000)
    return choices


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    state = read_json(state_dir / "public_state.json")
    before = state["challenge_id"]
    choices = _make(page, state)
    for index, scene_id in enumerate(state["boss_order"]):
        socket, seal = choices[scene_id]
        _answer(page, socket, (seal + 1) % 4 if index == 0 else seal)
    expect_fail_and_fresh(page, state_dir, before)
    shot(page, out_dir, mechanic, "real-wrong-reconstruction")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    assert mechanic == MECHANIC_ID
    state = read_json(state_dir / "public_state.json")
    choices = _make(page, state)
    shot(page, out_dir, mechanic, "judgment-after-occlusion")
    for scene_id in state["boss_order"]:
        _answer(page, *choices[scene_id])
