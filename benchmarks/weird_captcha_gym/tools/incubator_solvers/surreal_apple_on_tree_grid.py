from __future__ import annotations

import json
import math
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "surreal_apple_on_tree_grid"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_new(state_dir: Path, old: str) -> None:
    deadline = time.time() + 8
    while time.time() < deadline:
        if str(_read(state_dir / "ground_truth.json").get("challenge_id")) != old:
            return
        time.sleep(0.05)
    raise AssertionError("parallax orchard did not issue a fresh challenge")


def _box(page) -> dict:
    box = page.locator("#orchard-canvas").bounding_box()
    if not box:
        raise AssertionError("orchard canvas is not visible")
    return box


def _screen(box: dict, point: list[float]) -> tuple[float, float]:
    return box["x"] + point[0] / 960 * box["width"], box["y"] + point[1] / 520 * box["height"]


def _project(point: list[float], angle: float) -> list[float]:
    radians = math.radians(angle)
    x, y, z = point
    return [430 + x * math.cos(radians) + z * math.sin(radians), 246 + y + 0.10 * z * math.cos(radians) - 0.05 * x * math.sin(radians)]


def _depth(point: list[float], angle: float) -> float:
    radians = math.radians(angle)
    return point[2] * math.cos(radians) - point[0] * math.sin(radians)


def _frontmost(candidates: list[dict], all_apples: list[dict], angle: float) -> dict:
    for apple in sorted(candidates, key=lambda item: _depth(item["position"], angle), reverse=True):
        center = _project(apple["position"], angle)
        blockers = [
            other for other in all_apples
            if other["id"] != apple["id"]
            and _depth(other["position"], angle) > _depth(apple["position"], angle)
            and math.hypot(*[a - b for a, b in zip(center, _project(other["position"], angle))]) <= max(apple["radius"], other["radius"]) + 8
        ]
        if not blockers:
            return apple
    raise AssertionError("no candidate fruit has an unobstructed pointer hit")


def _orbit(page, start: list[float], end: list[float], steps: int = 12) -> None:
    box = _box(page)
    page.mouse.move(*_screen(box, start))
    page.mouse.down()
    page.mouse.move(*_screen(box, end), steps=steps)
    page.mouse.up()


def _pluck(page, apple: dict, angle: float, basket: dict) -> None:
    box = _box(page)
    start = _project(apple["position"], angle)
    end = [basket["x"] + basket["width"] / 2, basket["y"] + basket["height"] / 2]
    page.mouse.move(*_screen(box, start))
    page.mouse.down()
    page.wait_for_timeout(30)
    page.mouse.move(*_screen(box, end), steps=8)
    page.wait_for_timeout(110)
    page.mouse.up()


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator("#orchard-submit").click()
    _wait_new(state_dir, before)
    expect(page.locator('.parallax-orchard[data-fresh-failure="true"]')).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_have_text("FAIL")
    _shot(page, out_dir, mechanic, "fail-fresh-orchard")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    page.wait_for_function("() => document.querySelector('.parallax-orchard')?.dataset.freshFailure === 'false'", timeout=4_000)
    by_id = {apple["id"]: apple for apple in truth["apples"]}
    attached = set(truth["attached_ids"])

    # Three real drags sweep both sides and then return to a useful harvest view.
    _orbit(page, [430, 270], [710, 270], 14)
    _orbit(page, [620, 300], [90, 300], 24)
    _orbit(page, [240, 250], [610, 250], 18)
    page.wait_for_function("() => document.querySelector('.parallax-orchard')?.dataset.ready === 'true'")
    angle = float(page.evaluate("() => parallaxOrchardModel.angle"))
    audit = page.evaluate("() => ({samples:parallaxOrchardModel.orbitSamples,sectors:parallaxOrchardModel.sectors.size})")
    if audit["samples"] < truth["requirements"]["minimum_orbit_samples"] or audit["sectors"] < truth["requirements"]["minimum_view_sectors"]:
        raise AssertionError(f"parallax exploration is insufficient: {audit}")
    _shot(page, out_dir, mechanic, "active-side-parallax")

    detached = _frontmost([apple for apple in truth["apples"] if apple["id"] not in attached], truth["apples"], angle)
    _pluck(page, detached, angle, truth["basket"])
    expect(page.locator('.parallax-orchard[data-strike="true"]')).to_be_visible()
    _shot(page, out_dir, mechanic, "false-contact-recovery")
    page.locator("#orchard-reset").click()
    expect(page.locator('.parallax-orchard[data-strike="false"]')).to_be_visible()

    harvest = sorted((by_id[apple_id] for apple_id in attached), key=lambda item: _depth(item["position"], angle), reverse=True)
    for index, apple in enumerate(harvest):
        _pluck(page, apple, angle, truth["basket"])
        page.wait_for_function("count => parallaxOrchardModel.plucked.size === count", arg=index + 1)
    expect(page.locator('.parallax-orchard[data-completed="true"]')).to_be_visible()
    _shot(page, out_dir, mechanic, "three-true-stems-harvested")
    page.locator("#orchard-submit").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
    expect(page.locator(".orchard-verdict")).to_contain_text("PASS")
    expect(page.locator(".orchard-verdict")).not_to_contain_text("FAIL")
