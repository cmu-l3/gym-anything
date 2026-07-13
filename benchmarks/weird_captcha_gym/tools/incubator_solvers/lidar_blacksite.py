from __future__ import annotations

import json
import math
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "lidar_blacksite"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _position(page) -> tuple[float, float]:
    value = page.evaluate("() => [window.lidarBlacksiteModel.player.x, window.lidarBlacksiteModel.player.y]")
    return float(value[0]), float(value[1])


def _heading(page) -> float:
    return float(page.evaluate("() => window.lidarBlacksiteModel.player.heading"))


def _normalize(angle: float) -> float:
    return (angle + math.pi) % (2 * math.pi) - math.pi


def _turn_to(page, target: tuple[float, float] | float) -> None:
    if isinstance(target, tuple):
        x, y = _position(page)
        desired = math.atan2(target[1] - y, target[0] - x)
    else:
        desired = target
    for _ in range(5):
        difference = _normalize(desired - _heading(page))
        if abs(difference) <= .02:
            return
        key = "ArrowRight" if difference > 0 else "ArrowLeft"
        page.keyboard.down(key)
        try:
            page.wait_for_function(
                "([desired, initial]) => { const h=window.lidarBlacksiteModel.player.heading; const n=(v)=>((v+Math.PI)%(2*Math.PI)+2*Math.PI)%(2*Math.PI)-Math.PI; const d=n(desired-h); return Math.abs(d)<=.02 || Math.sign(d)!==Math.sign(initial); }",
                arg=[desired, difference],
                timeout=4_000,
            )
        finally:
            page.keyboard.up(key)
        page.wait_for_timeout(28)
    difference = abs(_normalize(desired - _heading(page)))
    if difference > .04:
        raise AssertionError(f"continuous turn stopped {difference:.4f} radians from its target")


def _move_to(page, point: list[float] | tuple[float, float], tolerance: float = .15) -> None:
    target = (float(point[0]), float(point[1]))
    stalls = 0
    for _ in range(180):
        x, y = _position(page)
        remaining = math.dist((x, y), target)
        if remaining <= tolerance:
            return
        _turn_to(page, target)
        speed = float(page.evaluate("() => window.lidarBlacksiteModel.state.controls.move_speed"))
        pulse_ms = max(80, min(220, round(max(.04, remaining - tolerance * .45) / speed * 1000)))
        page.keyboard.down("w")
        try:
            page.wait_for_timeout(pulse_ms)
        finally:
            page.keyboard.up("w")
        page.wait_for_timeout(28)
        next_remaining = math.dist(_position(page), target)
        if next_remaining < remaining - .025:
            stalls = 0
            continue
        stalls += 1
        if stalls >= 2:
            # A human releases the key instead of grinding against the wall,
            # backs out of a corner by one short physical pulse, and re-aims.
            page.keyboard.down("s")
            try:
                page.wait_for_timeout(100)
            finally:
                page.keyboard.up("s")
            page.wait_for_timeout(28)
            stalls = 0
    x, y = _position(page)
    heading = _heading(page)
    collisions = int(page.evaluate("() => window.lidarBlacksiteModel.player.collisions"))
    raise AssertionError(
        f"continuous movement stalled before {target}: position=({x:.3f}, {y:.3f}), "
        f"heading={heading:.4f}, remaining={math.dist((x, y), target):.3f}, collisions={collisions}"
    )


def _scan(page) -> None:
    before = int(page.evaluate("() => window.lidarBlacksiteModel.scanCount"))
    page.locator("#lidar-scan").click()
    page.wait_for_function(
        "count => window.lidarBlacksiteModel.scanCount === count + 1",
        arg=before,
        timeout=3_000,
    )


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    expect(page.locator(".lidar-blacksite")).to_be_visible()
    page.locator("#lidar-abandon").click()
    expect(page.locator(".lidar-verdict.is-fail")).to_be_visible(timeout=7_000)
    expect(page.locator(".lidar-foot .readout")).to_contain_text("FAIL", timeout=7_000)
    deadline = time.time() + 7
    while time.time() < deadline:
        if str(_read(state_dir / "ground_truth.json")["challenge_id"]) != before:
            break
        time.sleep(.05)
    else:
        raise AssertionError("aborted blacksite did not issue a fresh facility")
    _shot(page, out_dir, mechanic, "fail-fresh-facility")
    expect(page.locator(".lidar-verdict.is-fresh")).to_be_hidden(timeout=3_500)


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    expect(page.locator(".lidar-blacksite")).to_be_visible(timeout=6_000)
    truth = _read(state_dir / "ground_truth.json")
    route = [list(map(float, point)) for point in truth["solution"]["route_points"]]
    scan_indices = set(map(int, truth["solution"]["scan_route_indices"]))
    beacon_index = int(truth["solution"]["beacon_route_index"])
    if scan_indices != {0, 2, 4, 5} or beacon_index != 5:
        raise AssertionError("hidden LIDAR verification route violates its solver contract")
    _shot(page, out_dir, mechanic, "initial-lightless-facility")

    # Prove that movement is fixed-tick and collision-backed: walk into the
    # side wall, observe a real collision, then physically return to intake.
    first_heading = math.atan2(route[1][1] - route[0][1], route[1][0] - route[0][0])
    _turn_to(page, first_heading + math.pi / 2)
    prior_collisions = int(page.evaluate("() => window.lidarBlacksiteModel.player.collisions"))
    page.keyboard.down("w")
    try:
        page.wait_for_function(
            "before => window.lidarBlacksiteModel.player.collisions > before",
            arg=prior_collisions,
            timeout=3_000,
        )
    finally:
        page.keyboard.up("w")
    _shot(page, out_dir, mechanic, "swept-wall-collision")

    # The collision above is evidence for the swept geometry, not part of the
    # accepted solve. Discard that transcript and prove the authoritative path
    # on a genuinely fresh facility with a zeroed collision ledger.
    before = str(truth["challenge_id"])
    page.locator("#lidar-abandon").click()
    expect(page.locator(".lidar-verdict.is-fail")).to_be_visible(timeout=7_000)
    deadline = time.time() + 7
    while time.time() < deadline:
        if str(_read(state_dir / "ground_truth.json")["challenge_id"]) != before:
            break
        time.sleep(.05)
    else:
        raise AssertionError("collision smoke was not replaced by a fresh facility")
    truth = _read(state_dir / "ground_truth.json")
    route = [list(map(float, point)) for point in truth["solution"]["route_points"]]
    scan_indices = set(map(int, truth["solution"]["scan_route_indices"]))
    beacon_index = int(truth["solution"]["beacon_route_index"])
    if scan_indices != {0, 2, 4, 5} or beacon_index != 5:
        raise AssertionError("fresh LIDAR verification route violates its solver contract")
    page.wait_for_function(
        "id => document.querySelector('.lidar-blacksite')?.dataset.challengeId === id",
        arg=str(truth["challenge_id"]),
        timeout=7_000,
    )
    expect(page.locator(".lidar-verdict.is-fresh")).to_be_hidden(timeout=3_500)
    expect(page.locator("#lidar-collisions")).to_have_text("00")
    _shot(page, out_dir, mechanic, "clean-acceptance-facility")
    first_heading = math.atan2(route[1][1] - route[0][1], route[1][0] - route[0][0])
    _turn_to(page, first_heading)

    for index, waypoint in enumerate(route):
        if index:
            _move_to(page, waypoint)
        if index in scan_indices:
            if index < len(route) - 1:
                _turn_to(page, (float(route[index + 1][0]), float(route[index + 1][1])))
            _scan(page)
            if index == 0:
                _shot(page, out_dir, mechanic, "world-anchored-point-cloud")
            elif index == 2:
                _shot(page, out_dir, mechanic, "multi-station-rescan")
            elif index == 4:
                page.wait_for_function("() => window.lidarBlacksiteModel.targetSeen === true", timeout=2_500)
                expect(page.locator("#lidar-pickup")).to_be_disabled()
                _shot(page, out_dir, mechanic, "occluded-beacon-revealed")
            elif index == beacon_index:
                expect(page.locator("#lidar-pickup")).to_be_enabled()
                page.locator("#lidar-pickup").click()
                page.wait_for_function("() => window.lidarBlacksiteModel.carrying === true", timeout=2_500)
                _shot(page, out_dir, mechanic, "physical-beacon-carry")

    expect(page.locator("#lidar-verify")).to_be_enabled(timeout=3_000)
    collisions = int(page.evaluate("() => window.lidarBlacksiteModel.player.collisions"))
    if collisions != 0:
        raise AssertionError(f"authoritative LIDAR solve was not clean: collisions={collisions}")
    _shot(page, out_dir, mechanic, "extraction-gate-arrival")
    page.locator("#lidar-verify").click()
    expect(page.locator(".lidar-verdict.is-pass")).to_be_visible(timeout=10_000)
    expect(page.locator(".lidar-foot .readout")).to_have_text("PASS", timeout=10_000)
    expect(page.locator(".lidar-foot .readout")).to_have_attribute("data-status", "passed")
    _shot(page, out_dir, mechanic, "authoritative-pass")
