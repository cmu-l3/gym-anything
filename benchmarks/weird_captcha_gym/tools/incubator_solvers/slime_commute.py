from __future__ import annotations

from collections import deque
from pathlib import Path

MECHANIC_ID = "slime_commute"
KEYS = {"w": (0, -1), "s": (0, 1), "a": (-1, 0), "d": (1, 0)}


def _distance(a: float, b: float, period: float) -> float:
    raw = abs(a - b)
    return min(raw, period - raw)


def _center(lane: dict, offset: float, tick: int, columns: int) -> float:
    return (float(offset) + float(lane["phase"]) + tick * float(lane["speed"])) % columns


def _lane(board: dict, row: int) -> dict | None:
    return next((item for item in board["lanes"] if int(item["row"]) == row), None)


def _safe(board: dict, x: float, y: int, tick: int) -> bool:
    lane = _lane(board, y)
    if not lane:
        return True
    distances = [_distance(x + .5, _center(lane, offset, tick, int(board["columns"])), int(board["columns"])) for offset in lane["offsets"]]
    if lane["kind"] == "water":
        return any(value <= float(lane["length"]) / 2 - float(board["player_radius"]) * .25 for value in distances)
    return not any(value <= float(lane["length"]) / 2 + float(board["player_radius"]) for value in distances)


def _world_step(board: dict, x: float, y: int, tick: int, cooldown: int) -> tuple[float, int, int, int] | None:
    lane = _lane(board, y)
    if lane and lane["kind"] == "water":
        x += float(lane["speed"])
        radius = float(board["player_radius"])
        if x + .5 < -radius or x + .5 > int(board["columns"]) + radius:
            return None
    tick += 1
    cooldown = max(0, cooldown - 1)
    return (round(x, 4), y, tick, cooldown) if _safe(board, x, y, tick) else None


def _plan(board: dict) -> list[tuple[int, str]]:
    start = (float(board["start_x"]), 10, 0, 0)
    queue = deque([start])
    parent: dict[tuple, tuple[tuple, tuple[int, str] | None] | None] = {start: None}
    goal_state = None
    while queue:
        x, y, tick, cooldown = queue.popleft()
        if tick >= min(int(board["max_ticks"]), 900):
            continue
        choices = [None] + (list(KEYS) if cooldown == 0 else [])
        for key in choices:
            nx, ny, nc = x, y, cooldown
            action = None
            if key is not None:
                dx, dy = KEYS[key]
                nx, ny = x + dx, y + dy
                if not (0 <= nx <= int(board["columns"]) - 1 and 0 <= ny <= 10):
                    continue
                nc = int(board["hop_cooldown_ticks"])
                if not _safe(board, nx, ny, tick):
                    continue
                action = (tick, key)
                if ny == 0 and abs(nx - float(board["goal_x"])) < .42:
                    goal_state = (round(nx, 4), ny, tick, nc, "goal")
                    parent[goal_state] = ((x, y, tick, cooldown), action)
                    queue.clear()
                    break
            nxt = _world_step(board, nx, ny, tick, nc)
            if nxt is not None and nxt not in parent:
                parent[nxt] = ((x, y, tick, cooldown), action)
                queue.append(nxt)
        if goal_state:
            break
    if goal_state is None:
        raise AssertionError("generated crossing had no independently replayable route")
    actions: list[tuple[int, str]] = []
    cursor = goal_state
    while parent[cursor] is not None:
        previous, action = parent[cursor]
        if action is not None:
            actions.append(action)
        cursor = previous
    return list(reversed(actions))


def _tick(page) -> int:
    return int(page.locator(".slime-tick b").inner_text())


def _assert_visible_contact(page) -> None:
    avatar = page.locator('.slime-avatar-v2[data-hit="true"]').bounding_box()
    hazards = [node.bounding_box() for node in page.locator('.moving-entity[data-hit="true"]').all()]
    hazards = [box for box in hazards if box]
    if not avatar or not hazards:
        raise AssertionError("collision did not expose both visible bodies")
    def gap(first: dict, second: dict) -> float:
        horizontal = max(first["x"] - (second["x"] + second["width"]), second["x"] - (first["x"] + first["width"]), 0)
        vertical = max(first["y"] - (second["y"] + second["height"]), second["y"] - (first["y"] + first["height"]), 0)
        return max(horizontal, vertical)
    if min(gap(avatar, hazard) for hazard in hazards) > 1:
        raise AssertionError(f"replay collision has no visible contact: avatar={avatar}, hazards={hazards}")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    from playwright.sync_api import expect

    from benchmarks.weird_captcha_gym.tools.incubator_solvers.reviewed_overhaul_common import (
        expect_fail_and_fresh, read_json, shot,
    )

    assert mechanic == MECHANIC_ID
    state = read_json(state_dir / "public_state.json")
    before, board = state["challenge_id"], state["board"]
    lane = _lane(board, 9)
    assert lane
    page.locator(".slime-start-v2").click()
    for wipe in range(int(board["max_deaths"])):
        deadline = _tick(page) + 220
        while _tick(page) < deadline:
            tick = _tick(page)
            dangerous = not _safe(board, float(board["start_x"]), 9, tick)
            if dangerous:
                page.keyboard.press("w")
                break
            page.wait_for_timeout(25)
        expect(page.locator(".slime-deaths b")).to_have_text(str(wipe + 1), timeout=4_000)
        expect(page.locator(".slime-v2.is-hit")).to_be_visible(timeout=2_000)
        if wipe == 0:
            _assert_visible_contact(page)
            shot(page, out_dir, mechanic, "visible-collision-contact")
        if wipe + 1 < int(board["max_deaths"]):
            expect(page.locator(".slime-v2:not(.is-hit)")).to_be_visible(timeout=2_000)
            page.wait_for_timeout(int(board["tick_ms"]) * 3)
    expect_fail_and_fresh(page, state_dir, before)
    shot(page, out_dir, mechanic, "real-continuous-collision-rejection")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    from benchmarks.weird_captcha_gym.tools.incubator_solvers.reviewed_overhaul_common import read_json, shot

    assert mechanic == MECHANIC_ID
    state = read_json(state_dir / "public_state.json")
    plan = _plan(state["board"])
    page.locator(".slime-start-v2").click()
    for action_tick, key in plan:
        page.wait_for_function("target => Number(document.querySelector('.slime-tick b').textContent) >= target", arg=action_tick, timeout=15_000)
        current = _tick(page)
        if current != action_tick:
            raise AssertionError(f"browser missed deterministic crossing tick {action_tick}; reached {current}")
        page.keyboard.press(key)
    shot(page, out_dir, mechanic, "fixed-step-route-complete")
