#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from playwright.sync_api import expect, sync_playwright


ROOT = Path(__file__).resolve().parents[3]
BENCH_ROOT = ROOT / "benchmarks" / "weird_captcha_gym"
APP_DIR = BENCH_ROOT / "shared_runtime" / "app"
SERVER = BENCH_ROOT / "shared_runtime" / "server" / "weird_captcha_server.py"
SETUP = BENCH_ROOT / "shared_scripts" / "setup_task.py"
HELPERS = BENCH_ROOT / "shared_runtime" / "verifier_helpers.py"

MECHANICS = (
    "motion_only_ghost_jigsaw",
    "cursor_constellation_hunt",
    "parallel_grillmaster",
    "rotating_keyboard",
    "slot_reel_capture",
)

VERIFY_FUNCTIONS = {
    "motion_only_ghost_jigsaw": "verify_motion_only_ghost_jigsaw",
    "cursor_constellation_hunt": "verify_cursor_constellation_hunt",
    "parallel_grillmaster": "verify_parallel_grillmaster",
    "rotating_keyboard": "verify_rotating_keyboard",
    "slot_reel_capture": "verify_slot_reel_capture",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Exercise and capture the five interaction-first CAPTCHA tasks.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "interaction_first_five_v1"))
    parser.add_argument("--port", type=int, default=8840)
    return parser.parse_args()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def task_json(mechanic: str) -> Path:
    return BENCH_ROOT / "environments" / f"{mechanic}_env" / "tasks" / f"{mechanic}_seed_0001" / "task.json"


def start_server(mechanic: str, port: int, state_dir: Path) -> subprocess.Popen:
    subprocess.run(
        ["python", "-B", str(SETUP), "--task-json", str(task_json(mechanic)), "--state-dir", str(state_dir), "--seed", f"interaction-smoke-{mechanic}"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    proc = subprocess.Popen(
        ["python", "-B", str(SERVER), "--host", "127.0.0.1", "--port", str(port), "--app-dir", str(APP_DIR), "--state-dir", str(state_dir)],
        cwd=ROOT,
        env=os.environ.copy(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            import urllib.request
            urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=0.5).read()
            return proc
        except Exception:
            time.sleep(0.1)
    proc.kill()
    raise RuntimeError(f"server did not start for {mechanic}")


def screenshot(page, out_dir: Path, mechanic: str, name: str) -> None:
    page.screenshot(path=str(out_dir / f"{mechanic}-{name}.png"), full_page=True)


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    before = read_json(state_dir / "ground_truth.json")["challenge_id"]
    button_ids = {
        "motion_only_ghost_jigsaw": "#submit-ghost",
        "cursor_constellation_hunt": "#submit-constellation",
        "parallel_grillmaster": "#submit-grill",
        "rotating_keyboard": "#submit-rotating",
        "slot_reel_capture": "#submit-slot",
    }
    if mechanic == "slot_reel_capture":
        first_target = read_json(state_dir / "ground_truth.json")["sequence"][0]
        wrong_key = "A" if first_target != "A" else "B"
        for _ in range(3):
            page.keyboard.press(wrong_key)
            page.wait_for_timeout(80)
    else:
        page.locator(button_ids[mechanic]).click()
    expect(page.locator(".readout")).to_have_text("FAIL")
    after = read_json(state_dir / "ground_truth.json")["challenge_id"]
    if before == after:
        raise AssertionError(f"{mechanic} did not regenerate after failure")
    screenshot(page, out_dir, mechanic, "fail-refresh")


def solve_ghost(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    expected = read_json(state_dir / "ground_truth.json")["expected_positions"]
    for index, (piece_id, slot_index) in enumerate(expected.items()):
        page.locator(f'.ghost-piece[data-piece-id="{piece_id}"]').drag_to(page.locator(f'.ghost-slot[data-slot-index="{slot_index}"]'))
        if index == 3:
            page.wait_for_timeout(450)
            screenshot(page, out_dir, mechanic, "active")
    if page.locator(".ghost-slot .ghost-piece").count() != 9:
        raise AssertionError("ghost jigsaw did not place all nine pieces")
    screenshot(page, out_dir, mechanic, "solved-state")
    page.locator("#submit-ghost").click()


def solve_constellation(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    state = read_json(state_dir / "public_state.json")
    expected = read_json(state_dir / "ground_truth.json")["expected_click"]
    canvas = page.locator(".constellation-canvas")
    box = canvas.bounding_box()
    if not box:
        raise AssertionError("constellation canvas has no bounding box")
    decoy = state["surface"]["decoys"][0]
    page.mouse.move(box["x"] + decoy["x"] * box["width"] / 680, box["y"] + decoy["y"] * box["height"] / 410)
    page.wait_for_timeout(300)
    screenshot(page, out_dir, mechanic, "active-decoy")
    x = box["x"] + expected["x"] * box["width"] / 680
    y = box["y"] + expected["y"] * box["height"] / 410
    page.mouse.move(x, y)
    page.wait_for_timeout(350)
    page.mouse.click(x, y)
    screenshot(page, out_dir, mechanic, "solved-state")
    page.locator("#submit-constellation").click()


def solve_grill(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    ground_truth = read_json(state_dir / "ground_truth.json")
    grill = page.locator('.grill-zone[data-drop-zone="grill"]')
    tray = page.locator('.grill-zone[data-drop-zone="tray"]')
    due: list[tuple[float, str]] = []
    for food_id, target in ground_truth["targets"].items():
        page.locator(f'.grill-food[data-food-id="{food_id}"]').drag_to(grill)
        started = page.evaluate("foodId => grillModel.records[foodId].startedAt", food_id)
        due.append((float(started) + float(target["target_ms"]), food_id))
    page.wait_for_timeout(700)
    screenshot(page, out_dir, mechanic, "active")
    for due_at, food_id in sorted(due):
        now = float(page.evaluate("performance.now()"))
        if due_at > now:
            page.wait_for_timeout(int(due_at - now))
        page.locator(f'.grill-food[data-food-id="{food_id}"]').drag_to(tray)
    screenshot(page, out_dir, mechanic, "solved-state")
    page.locator("#submit-grill").click()


def click_moving_key(page, key: str, expected_length: int) -> None:
    deadline = time.time() + 12
    while time.time() < deadline:
        box = page.locator(f'.rotating-key[data-key="{key}"]').bounding_box()
        if box and box["width"] > 8 and box["height"] > 8:
            page.mouse.click(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
            length = int(page.evaluate("rotatingKeyboardModel.input.length"))
            if length == expected_length:
                return
            if length > expected_length:
                raise AssertionError(f"moving keyboard clicked the wrong key while targeting {key}")
        page.wait_for_timeout(70)
    raise AssertionError(f"could not physically click moving key {key}")


def solve_rotating(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    target = read_json(state_dir / "ground_truth.json")["target"]
    page.locator(f'.rotating-key[data-key="{target[0]}"]').click()
    page.wait_for_timeout(850)
    screenshot(page, out_dir, mechanic, "active")
    for index, key in enumerate(target[1:], start=2):
        click_moving_key(page, key, index)
    if page.evaluate("rotatingKeyboardModel.input") != target:
        raise AssertionError("rotating keyboard input does not match target")
    screenshot(page, out_dir, mechanic, "solved-state")
    page.locator("#submit-rotating").click()


def solve_slot(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    ground_truth = read_json(state_dir / "ground_truth.json")
    wrong_key = "A" if ground_truth["sequence"][0] != "A" else "B"
    page.keyboard.press(wrong_key)
    expect(page.locator(".slot-strikes-count")).to_have_text("1/3")
    expect(page.locator('.slot-strike-pip[data-active="true"]')).to_have_count(1)
    for index, (reel_id, target) in enumerate(zip(ground_truth["reel_ids"], ground_truth["sequence"])):
        deadline = time.time() + 8
        captured = False
        while time.time() < deadline:
            timing = page.evaluate(
                """({reelId, target}) => {
                    const reel = slotModel.state.reels.find((item) => item.id === reelId);
                    const elapsed = performance.now() - slotModel.startedAt;
                    const tokenIndex = (Math.floor(elapsed / reel.interval_ms) + Number(reel.phase || 0)) % reel.tokens.length;
                    const remaining = reel.interval_ms - (elapsed % reel.interval_ms);
                    const node = document.querySelector(`.slot-reel[data-reel-id="${CSS.escape(reelId)}"]`);
                    const displayedIndex = Number(node?.dataset.tokenIndex ?? tokenIndex);
                    return {token: reel.tokens[displayedIndex], remaining, interval: reel.interval_ms};
                }""",
                {"reelId": reel_id, "target": target},
            )
            safe_window = max(260, float(timing["interval"]) * 0.62)
            if timing["token"] == target and timing["remaining"] > safe_window:
                page.keyboard.press(target)
                if int(page.evaluate("slotModel.frozen.length")) == index + 1:
                    captured = True
                    break
            page.wait_for_timeout(25)
        if not captured:
            raise AssertionError(f"slot reel {index + 1} was not captured")
        if index == 1:
            screenshot(page, out_dir, mechanic, "active")
    if int(page.evaluate("slotModel.wrongKeys")) != 1:
        raise AssertionError("slot strike recovery did not preserve exactly one visible strike")
    screenshot(page, out_dir, mechanic, "solved-state")
    page.locator("#submit-slot").click()


SOLVERS = {
    "motion_only_ghost_jigsaw": solve_ghost,
    "cursor_constellation_hunt": solve_constellation,
    "parallel_grillmaster": solve_grill,
    "rotating_keyboard": solve_rotating,
    "slot_reel_capture": solve_slot,
}


def load_helpers():
    spec = importlib.util.spec_from_file_location("interaction_verifier_helpers", HELPERS)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {HELPERS}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    temp_root = Path(tempfile.mkdtemp(prefix="interaction-first-five-"))
    helpers = load_helpers()
    summary: dict[str, dict] = {}

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        for index, mechanic in enumerate(MECHANICS):
            state_dir = temp_root / mechanic
            state_dir.mkdir(parents=True, exist_ok=True)
            proc = start_server(mechanic, args.port + index, state_dir)
            errors: list[str] = []
            try:
                page = browser.new_page(viewport={"width": 1280, "height": 820}, device_scale_factor=1)
                page.on("pageerror", lambda exc: errors.append(str(exc)))
                page.goto(f"http://127.0.0.1:{args.port + index}")
                page.wait_for_load_state("networkidle")
                page.wait_for_selector(".interaction-captcha")
                screenshot(page, out_dir, mechanic, "initial")
                if mechanic == "motion_only_ghost_jigsaw":
                    for frame_index in range(1, 4):
                        page.wait_for_timeout(180)
                        screenshot(page, out_dir, mechanic, f"motion-frame-{frame_index}")
                fail_once(page, state_dir, out_dir, mechanic)
                SOLVERS[mechanic](page, state_dir, out_dir, mechanic)
                expect(page.locator(".readout")).to_have_text("PASS")
                screenshot(page, out_dir, mechanic, "pass")
                result = read_json(state_dir / "result.json")
                ground_truth = read_json(state_dir / "ground_truth.json")
                if not (result.get("server_grade") or {}).get("passed"):
                    raise AssertionError(f"{mechanic} server grade did not pass: {result!r}")
                verifier = getattr(helpers, VERIFY_FUNCTIONS[mechanic])
                verified = verifier({"result": result, "ground_truth": ground_truth})
                if verified.get("score") != 100 or not verified.get("passed"):
                    raise AssertionError(f"{mechanic} outcome verifier did not score 100: {verified!r}")
                if errors:
                    raise AssertionError(f"{mechanic} browser errors: {errors}")
                summary[mechanic] = {
                    "ok": True,
                    "challenge_id": ground_truth["challenge_id"],
                    "server_grade": result["server_grade"],
                    "verifier": verified,
                    "screenshots": sorted(path.name for path in out_dir.glob(f"{mechanic}-*.png")),
                }
                page.close()
            finally:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
        browser.close()

    (out_dir / "summary.json").write_text(json.dumps({"ok": True, "mechanics": summary}, indent=2, sort_keys=True), encoding="utf-8")
    shutil.rmtree(temp_root)
    print(json.dumps({"ok": True, "mechanics": summary, "out_dir": str(out_dir)}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
