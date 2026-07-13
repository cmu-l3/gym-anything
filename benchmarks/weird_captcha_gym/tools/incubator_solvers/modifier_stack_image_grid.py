from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "modifier_stack_image_grid"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_new(state_dir: Path, previous: str) -> None:
    deadline = time.time() + 8
    while time.time() < deadline:
        if str(_read(state_dir / "ground_truth.json").get("challenge_id")) != previous:
            return
        time.sleep(0.05)
    raise AssertionError("restoration press did not issue fresh film")


def _box(page) -> dict:
    box = page.locator("#restoration-canvas").bounding_box()
    if not box:
        raise AssertionError("restoration canvas is not visible")
    return box


def _screen(box: dict, point: list[float]) -> tuple[float, float]:
    return box["x"] + point[0] / 940 * box["width"], box["y"] + point[1] / 500 * box["height"]


def _center(rect: dict) -> list[float]:
    return [rect["x"] + rect["width"] / 2, rect["y"] + rect["height"] / 2]


def _place(page, rack: dict, slot: dict) -> None:
    box = _box(page)
    page.mouse.move(*_screen(box, _center(rack)))
    page.mouse.down()
    page.wait_for_timeout(20)
    page.mouse.move(*_screen(box, _center(slot)), steps=7)
    page.wait_for_timeout(95)
    page.mouse.up()


def _invert(page, slot: dict) -> None:
    box = _box(page)
    page.mouse.click(*_screen(box, [slot["x"] + slot["width"] - 15, slot["y"] + 15]))


def _run_rail(page, rail: dict) -> None:
    box = _box(page)
    page.mouse.move(*_screen(box, rail["start"]))
    page.mouse.down()
    for index in range(1, 31):
        amount = index / 30
        point = [rail["start"][0] + (rail["end"][0] - rail["start"][0]) * amount, rail["start"][1]]
        page.mouse.move(*_screen(box, point), steps=1)
        page.wait_for_timeout(25)
    page.mouse.up()


def _arrange(page, art: dict, slots: list[dict]) -> None:
    racks = {item["token_id"]: item for item in art["rack_rects"]}
    for slot, token in zip(slots, reversed(art["stack"])):
        _place(page, racks[token["id"]], slot)
        _invert(page, slot)


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#restoration-submit").click()
    _wait_new(state_dir, before)
    expect(page.locator('.restoration-press[data-fresh-failure="true"]')).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_have_text("FAIL")
    _shot(page, out_dir, mechanic, "fail-fresh-film")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    page.wait_for_timeout(1450)
    expect(page.locator('.restoration-press[data-phase="playback"]')).to_be_visible()
    _shot(page, out_dir, mechanic, "active-transformation-film")
    page.wait_for_function("() => modifierRestorationModel.phase === 'work'", timeout=5_000)

    # Spend the one permitted replay and preserve a second transient film state.
    page.locator("#restoration-replay").click()
    page.wait_for_timeout(1750)
    _shot(page, out_dir, mechanic, "costly-film-replay")
    page.wait_for_function("() => modifierRestorationModel.phase === 'work'", timeout=5_000)

    first = truth["artifacts"][0]
    racks = {item["token_id"]: item for item in first["rack_rects"]}
    _place(page, racks[first["rack_order"][0]], truth["slots"][0])
    page.locator("#restoration-reset").click()
    page.wait_for_function("() => Object.keys(modifierRestorationModel.placements).length === 0 && modifierRestorationModel.resetCount === 1")
    _shot(page, out_dir, mechanic, "partial-stack-reset")

    for index, art in enumerate(truth["artifacts"]):
        if index:
            page.wait_for_function("() => modifierRestorationModel.phase === 'work'", timeout=5_000)
        _arrange(page, art, truth["slots"])
        page.wait_for_function("() => document.querySelector('.restoration-press')?.dataset.arranged === 'true'")
        if index == 0:
            _shot(page, out_dir, mechanic, "inverse-stack-armed")
        _run_rail(page, truth["rail"])
        page.wait_for_function("count => modifierRestorationModel.completed.length === count", arg=index + 1, timeout=4_000)
    expect(page.locator('.restoration-press[data-completed="true"]')).to_be_visible()
    state = page.evaluate("() => ({complete:modifierRestorationModel.completed.length,replays:modifierRestorationModel.replayCount,resets:modifierRestorationModel.resetCount,samples:modifierRestorationModel.railSamples})")
    if state["complete"] != 3 or state["replays"] != 1 or state["resets"] != 1 or state["samples"] < truth["requirements"]["minimum_rail_samples"] * 3:
        raise AssertionError(f"restoration physical state is incomplete: {state}")
    _shot(page, out_dir, mechanic, "three-specimens-restored")
    page.locator("#restoration-submit").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
    expect(page.locator(".restoration-verdict")).to_contain_text("PASS")
    expect(page.locator(".restoration-verdict")).not_to_contain_text("FAIL")
