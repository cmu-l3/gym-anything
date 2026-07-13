from __future__ import annotations

import json
import time
from pathlib import Path


MECHANIC_ID = "polyrhythm_customs"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _wait_new_challenge(state_dir: Path, old_challenge: str) -> None:
    deadline = time.time() + 8
    while time.time() < deadline:
        current = str(_read(state_dir / "ground_truth.json").get("challenge_id") or "")
        if current and current != old_challenge:
            return
        time.sleep(0.05)
    raise AssertionError("polyrhythm challenge did not regenerate after failure")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"])
    page.locator(".rhythm-start").click()
    page.wait_for_selector('.rhythm-score-lane[data-active="true"]', timeout=5_000)
    page.wait_for_timeout(420)
    _screenshot(page, out_dir, mechanic, "active-single-lane-preview")
    page.wait_for_function(
        "() => document.querySelector('.polyrhythm-customs-captcha')?.dataset.phase === 'performance'",
        timeout=18_000,
    )
    page.locator(".rhythm-certify-now").click()
    _wait_new_challenge(state_dir, before)
    page.wait_for_function("() => document.querySelector('.readout')?.textContent.includes('FAIL')", timeout=8_000)
    page.wait_for_selector('.polyrhythm-customs-captcha[data-fresh-failure="true"]')
    _screenshot(page, out_dir, mechanic, "fail-refresh")


def _elapsed(page) -> float:
    return float(page.evaluate("() => performance.now() - window.polyrhythmCustomsModel.performanceStartedAt"))


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(state_dir / "ground_truth.json")
    key_by_lane = {str(lane["id"]): str(lane["key"]) for lane in truth["lanes"]}
    events: list[tuple[float, int, str, str]] = []
    for note in truth["expected_notes"]:
        lane = str(note["lane"])
        start = float(note["start_ms"])
        end = start + float(note["duration_ms"])
        events.append((start, 1, lane, "down"))
        events.append((end, 0, lane, "up"))
    events.sort(key=lambda event: (event[0], event[1], event[2]))

    page.locator(".rhythm-start").click()
    page.wait_for_function(
        "() => document.querySelector('.polyrhythm-customs-captcha')?.dataset.phase === 'performance'",
        timeout=18_000,
    )
    captured = False
    for index, (target_ms, _order, lane, event_type) in enumerate(events):
        remaining = target_ms - _elapsed(page)
        if remaining > 4:
            page.wait_for_timeout(max(1, int(remaining - 3)))
        while _elapsed(page) < target_ms - 1:
            page.wait_for_timeout(1)
        key = key_by_lane[lane]
        if event_type == "down":
            page.keyboard.down(key)
        else:
            page.keyboard.up(key)
        if not captured and index + 1 < len(events):
            gap = events[index + 1][0] - target_ms
            if target_ms > 1_200 and gap > 430:
                _screenshot(page, out_dir, mechanic, "active-combined-performance")
                captured = True

    _screenshot(page, out_dir, mechanic, "solved-transcript")
    page.wait_for_function("() => document.querySelector('.readout')?.textContent.startsWith('PASS')", timeout=8_000)
    result = _read(state_dir / "result.json")
    transcript = result.get("transcript") or []
    if len(transcript) != len(events):
        raise AssertionError(f"expected {len(events)} physical input events, captured {len(transcript)}")
    if {str(event.get("source")) for event in transcript} != {"keyboard"}:
        raise AssertionError("polyrhythm solver did not use the real keyboard path")
