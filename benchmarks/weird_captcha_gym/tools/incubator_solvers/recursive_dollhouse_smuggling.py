from __future__ import annotations

import json
import math
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "recursive_dollhouse_smuggling"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, name: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True); page.screenshot(path=str(out_dir / f"{mechanic}-{name}.png"), full_page=True)


def _wait_new(state_dir: Path, before: str) -> None:
    deadline = time.time() + 8
    while time.time() < deadline:
        if str(_read(state_dir / "ground_truth.json").get("challenge_id")) != before: return
        time.sleep(.05)
    raise AssertionError("dollhouse challenge did not regenerate")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID: raise AssertionError(mechanic)
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"]); page.locator(".doll-submit").click(); _wait_new(state_dir, before)
    expect(page.locator(".dollhouse-captcha[data-fresh-failure='true']")).to_be_visible(timeout=8_000); expect(page.locator(".readout")).to_contain_text("FAIL"); _shot(page, out_dir, mechanic, "fail-fresh-room")


def _project(view: dict, point: list[float]) -> list[float]:
    matrix, origin = view["matrix"], view["origin"]
    return [origin[0] + matrix[0][0] * point[0] + matrix[0][1] * point[1], origin[1] + matrix[1][0] * point[0] + matrix[1][1] * point[1]]


def _screen(box: dict, view: dict, point: list[float]) -> tuple[float, float]:
    projected = _project(view, point); return box["x"] + projected[0] / view["canvas"]["width"] * box["width"], box["y"] + projected[1] / view["canvas"]["height"] * box["height"]


def _drag(page, truth: dict, view_id: str, start: list[float], waypoints: list[list[float]], steps: int = 10) -> None:
    view = next(item for item in truth["views"] if item["id"] == view_id); canvas = page.locator(f'.doll-canvas[data-view-id="{view_id}"]'); box = canvas.bounding_box()
    if not box: raise AssertionError(f"{view_id} projection canvas missing")
    page.mouse.move(*_screen(box, view, start)); page.mouse.down()
    for point in waypoints: page.mouse.move(*_screen(box, view, point), steps=steps); page.wait_for_timeout(35)
    page.mouse.up(); page.wait_for_timeout(80)


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID: raise AssertionError(mechanic)
    truth = _read(state_dir / "ground_truth.json")
    # Deliberately drive the miniature parcel into the still-solid canonical gate.
    _drag(page, truth, "mini", truth["parcel"]["initial_center"], [[28, 50]], steps=16)
    expect(page.locator(".doll-collision[data-visible='true']")).to_be_visible(); expect(page.locator(".readout")).to_contain_text("CONTACT"); _shot(page, out_dir, mechanic, "canonical-gate-collision")
    page.locator(".doll-reset").click(); expect(page.locator(".readout")).to_contain_text("REWOUND")

    # Move one canonical gate through the giant projection; all copies update.
    _drag(page, truth, "giant", truth["gate"]["center"], truth["solver_waypoints"]["gate"], steps=14)
    expect(page.locator(".doll-gate-value")).to_contain_text("PARKED"); _shot(page, out_dir, mechanic, "giant-scale-gate-reposition")
    _drag(page, truth, "mini", truth["parcel"]["initial_center"], truth["solver_waypoints"]["scale_0"], steps=18)
    expect(page.locator(".doll-scale-value")).to_contain_text("HUMAN"); _shot(page, out_dir, mechanic, "mini-to-human-frame-transfer")
    _drag(page, truth, "human", truth["portals"][0]["center"], truth["solver_waypoints"]["scale_1"], steps=12)
    expect(page.locator(".doll-scale-value")).to_contain_text("GIANT"); _shot(page, out_dir, mechanic, "human-to-giant-frame-transfer")
    _drag(page, truth, "giant", truth["portals"][1]["center"], truth["solver_waypoints"]["scale_2"], steps=12)
    expect(page.locator(".doll-delivered[data-visible='true']")).to_be_visible(); state = page.evaluate("() => ({delivered:window.recursiveDollhouseSmugglingModel.delivered,scale:window.recursiveDollhouseSmugglingModel.parcelScale,transitions:window.recursiveDollhouseSmugglingModel.transitions,views:[...window.recursiveDollhouseSmugglingModel.viewsUsed].sort(),collisions:window.recursiveDollhouseSmugglingModel.collisions,resets:window.recursiveDollhouseSmugglingModel.resets})")
    if not state["delivered"] or state["scale"] != 2 or len(state["transitions"]) != 2 or state["views"] != ["giant", "human", "mini"] or state["collisions"] < 1 or state["resets"] < 1: raise AssertionError(f"nested world incomplete: {state}")
    _shot(page, out_dir, mechanic, "solved-giant-bay"); page.locator(".doll-submit").click(); expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
