from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "fake_desktop_automation_inversion"


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
    raise AssertionError("automation-inversion desktop did not regenerate after failure")


def _physical_for_remote(remote: tuple[float, float], mapping: str, width: float, height: float) -> tuple[float, float]:
    x, y = remote
    if mapping == "mirror_x":
        return width - x, y
    if mapping == "mirror_y":
        return x, height - y
    if mapping == "rotate_180":
        return width - x, height - y
    return x, y


def _screen_point(desktop_box: dict, remote: tuple[float, float], mapping: str, width: float, height: float) -> tuple[float, float]:
    physical = _physical_for_remote(remote, mapping, width, height)
    return (
        desktop_box["x"] + physical[0] / width * desktop_box["width"],
        desktop_box["y"] + physical[1] / height * desktop_box["height"],
    )


def _click_remote(page, desktop_box: dict, remote: tuple[float, float], mapping: str, width: float, height: float) -> None:
    x, y = _screen_point(desktop_box, remote, mapping, width, height)
    page.mouse.click(x, y)


def _drag_remote(
    page,
    desktop_box: dict,
    start: tuple[float, float],
    end: tuple[float, float],
    mapping: str,
    width: float,
    height: float,
    *,
    steps: int = 10,
) -> None:
    start_x, start_y = _screen_point(desktop_box, start, mapping, width, height)
    end_x, end_y = _screen_point(desktop_box, end, mapping, width, height)
    page.mouse.move(start_x, start_y)
    page.mouse.down()
    page.mouse.move(end_x, end_y, steps=steps)
    page.mouse.up()


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read_json(state_dir / "ground_truth.json")["challenge_id"])
    page.locator(".fd-submit").click()
    _wait_for_new_challenge(state_dir, before)
    expect(page.locator(".fake-desktop-captcha[data-fresh-failure='true']")).to_be_visible(timeout=8_000)
    expect(page.locator(".readout")).to_contain_text("FAIL")
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read_json(state_dir / "ground_truth.json")
    desktop_box = page.locator(".fd-desktop").bounding_box()
    if not desktop_box:
        raise AssertionError("transformed desktop is not visible")
    width = float(truth["desktop"]["width"])
    height = float(truth["desktop"]["height"])
    first_mapping, second_mapping = [str(item) for item in truth["mapping_sequence"]]
    windows = {item["id"]: dict(item) for item in truth["initial_windows"]}
    geometry = truth["geometry"]

    blocker = windows[truth["required_blocker_id"]]
    close_remote = (
        blocker["x"] + blocker["width"] - geometry["close_width"] / 2,
        blocker["y"] + geometry["title_height"] / 2,
    )
    _click_remote(page, desktop_box, close_remote, first_mapping, width, height)
    page.wait_for_timeout(90)

    vault = windows["vault"]
    title_start = (vault["x"] + 42, vault["y"] + geometry["title_height"] / 2)
    title_end = (title_start[0] + 70, title_start[1] - 20)
    _drag_remote(page, desktop_box, title_start, title_end, first_mapping, width, height, steps=8)
    vault["x"] += 70
    vault["y"] -= 20
    page.wait_for_timeout(90)
    _screenshot(page, out_dir, mechanic, "active-window-reorder")

    target_file = next(item for item in truth["files"] if item["id"] == truth["target_file_id"])
    file_width, file_height = geometry["file_size"]
    file_remote = (
        vault["x"] + geometry["file_origin"][0] + target_file["slot"] * (file_width + geometry["file_gap"]) + file_width / 2,
        vault["y"] + geometry["file_origin"][1] + file_height / 2,
    )
    verifier = windows["verifier"]
    drop = geometry["drop_zone"]
    drop_remote = (verifier["x"] + drop[0] + drop[2] / 2, verifier["y"] + drop[1] + drop[3] / 2)
    _drag_remote(page, desktop_box, file_remote, drop_remote, first_mapping, width, height, steps=12)
    page.wait_for_timeout(140)
    expect(page.locator(".fd-mapping-badge")).to_contain_text("CHANNEL 2/2")
    _screenshot(page, out_dir, mechanic, "active-workflow-remap")

    arm = geometry["arm_control"]
    arm_remote = (verifier["x"] + arm[0] + arm[2] / 2, verifier["y"] + arm[1] + arm[3] / 2)
    _click_remote(page, desktop_box, arm_remote, second_mapping, width, height)
    page.wait_for_timeout(100)
    expect(page.locator(".fd-arm-control.is-armed")).to_be_visible()
    state = page.evaluate("""() => ({
        boundary: window.fakeDesktopInversionModel.boundary,
        loaded: window.fakeDesktopInversionModel.loadedFileId,
        armed: window.fakeDesktopInversionModel.armed,
        moved: window.fakeDesktopInversionModel.moveCount,
        closed: window.fakeDesktopInversionModel.closedCount,
        z: window.fakeDesktopInversionModel.zOrderChanges,
    })""")
    if not (
        state["boundary"] == 1
        and state["loaded"] == truth["target_file_id"]
        and state["armed"] is True
        and state["moved"] >= 1
        and state["closed"] >= 1
        and state["z"] >= 2
    ):
        raise AssertionError(f"automation-inversion physical workflow ended in unexpected state: {state}")
    _screenshot(page, out_dir, mechanic, "solved")
    page.locator(".fd-submit").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
