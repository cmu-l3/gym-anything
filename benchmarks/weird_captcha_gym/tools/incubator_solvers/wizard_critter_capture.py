from __future__ import annotations

import json
from pathlib import Path


MECHANIC_ID = "wizard_critter_capture"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _screenshot(page, out_dir: Path, mechanic: str, label: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    page.screenshot(path=str(out_dir / f"{mechanic}-{label}.png"), full_page=True)


def _arena_click(page, point: list[int]) -> None:
    canvas = page.locator("#wizard-arena")
    box = canvas.bounding_box()
    if box is None:
        raise AssertionError("wizard arena has no visible bounds")
    state = page.evaluate("() => wizardCritterCaptureModel.state.arena")
    x = box["x"] + (float(point[0]) / float(state["width"])) * box["width"]
    y = box["y"] + (float(point[1]) / float(state["height"])) * box["height"]
    page.mouse.click(x, y)


def _wait_ready(page) -> None:
    page.wait_for_function("() => wizardCritterCaptureModel.phase === 'ready'", timeout=6_000)


def _place_lure_and_freeze(page, truth: dict) -> None:
    page.locator("#wizard-lure-arm").click()
    _arena_click(page, list(truth["solver_lure"]))
    page.wait_for_function("() => wizardCritterCaptureModel.phase === 'hunt' && Boolean(wizardCritterCaptureModel.lure)")
    page.keyboard.down("f")
    required = int(truth["solver_freeze_ticks"])
    page.wait_for_function(
        "required => wizardCritterCaptureModel.freezeTicksUsed >= required",
        arg=required,
        timeout=5_000,
    )
    page.keyboard.up("f")
    page.wait_for_function("() => !wizardCritterCaptureModel.freezeActive && wizardCritterCaptureModel.freezeReleases >= 1")


def _future_plan(page, plans: list[dict], margin: int = 3) -> dict:
    current = int(page.evaluate("() => wizardCritterCaptureModel.tick"))
    for plan in plans:
        if int(plan["shot_tick"]) >= current + margin:
            return plan
    raise AssertionError(f"no future interception window remains after tick {current}: {plans}")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    state_dir = Path(state_dir)
    truth = _read(state_dir / "ground_truth.json")
    before = str(truth["challenge_id"])
    _screenshot(page, out_dir, mechanic, "target-observation")
    _wait_ready(page)
    page.locator("#wizard-lure-arm").click()
    _arena_click(page, list(truth["solver_lure"]))
    miss_points = ([18, 420], [822, 420], [30, 414], [810, 414])
    for index, point in enumerate(miss_points, start=1):
        _arena_click(page, list(point))
        if index == 2:
            page.wait_for_function("() => wizardCritterCaptureModel.projectile?.age >= 4", timeout=3_000)
            _screenshot(page, out_dir, mechanic, "deliberate-net-miss")
        if index < len(miss_points):
            page.wait_for_function(
                "expected => wizardCritterCaptureModel.nets === expected && wizardCritterCaptureModel.projectile === null && wizardCritterCaptureModel.cooldown === 0",
                arg=int(truth["requirements"]["net_count"]) - index,
                timeout=5_000,
            )
    page.wait_for_function("() => document.querySelector('.readout')?.textContent.includes('FAIL')", timeout=10_000)
    after = _read(state_dir / "ground_truth.json")["challenge_id"]
    if after == before:
        raise AssertionError("spent-net failure did not produce a fresh observatory")
    _screenshot(page, out_dir, mechanic, "fail-fresh-observatory")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    state_dir = Path(state_dir)
    truth = _read(state_dir / "ground_truth.json")
    challenge = page.locator(".wizard-observatory").get_attribute("data-challenge-id")
    if challenge != truth.get("challenge_id"):
        raise AssertionError(f"UI challenge {challenge!r} differs from hidden challenge {truth.get('challenge_id')!r}")
    page.wait_for_function("() => !document.querySelector('.wizard-verdict-fresh')", timeout=3_000)
    _screenshot(page, out_dir, mechanic, "fresh-target-sigil")
    _wait_ready(page)
    _place_lure_and_freeze(page, truth)
    _screenshot(page, out_dir, mechanic, "lure-and-freeze-proof")
    plan = _future_plan(page, list(truth["solver_plans"]), margin=3)
    page.wait_for_function(
        "shotTick => wizardCritterCaptureModel.tick === shotTick",
        arg=int(plan["shot_tick"]),
        timeout=8_000,
    )
    _arena_click(page, list(plan["aim"]))
    page.wait_for_function("() => wizardCritterCaptureModel.projectile?.age >= 3", timeout=3_000)
    _screenshot(page, out_dir, mechanic, "predictive-net-in-flight")
    page.wait_for_function("() => document.querySelector('.readout')?.textContent === 'PASS · PREDICTIVE INTERCEPTION CONFIRMED'", timeout=10_000)


def exercise_decoy_and_reset(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID:
        raise AssertionError(f"unexpected mechanic {mechanic!r}")
    truth = _read(Path(state_dir) / "ground_truth.json")
    _wait_ready(page)
    _place_lure_and_freeze(page, truth)
    plan = _future_plan(page, list(truth["decoy_plans"]), margin=3)
    page.wait_for_function("tick => wizardCritterCaptureModel.tick === tick", arg=int(plan["shot_tick"]), timeout=8_000)
    _arena_click(page, list(plan["aim"]))
    page.wait_for_function("() => wizardCritterCaptureModel.decoyHits === 1 && wizardCritterCaptureModel.projectile === null", timeout=6_000)
    _screenshot(page, out_dir, mechanic, "deliberate-decoy-strike")
    page.locator("#wizard-reset").click()
    page.wait_for_function(
        "() => wizardCritterCaptureModel.phase === 'preview' && wizardCritterCaptureModel.tick === 0 && wizardCritterCaptureModel.nets === wizardCritterCaptureModel.state.requirements.net_count && wizardCritterCaptureModel.resetCount === 1",
        timeout=3_000,
    )
    _screenshot(page, out_dir, mechanic, "reset-restored")
