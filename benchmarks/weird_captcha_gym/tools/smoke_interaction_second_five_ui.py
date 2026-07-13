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

MECHANICS = ("domino_autopsy", "consequences_boss", "popup_exorcist", "funeral_ritual", "slime_commute")
VERIFY_FUNCTIONS = {mechanic: f"verify_{mechanic}" for mechanic in MECHANICS}
ROOT_SELECTORS = {
    "domino_autopsy": ".domino-captcha",
    "consequences_boss": ".consequence-captcha",
    "popup_exorcist": ".popup-captcha",
    "funeral_ritual": ".funeral-captcha",
    "slime_commute": ".slime-captcha",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Exercise and capture the second five interaction-first CAPTCHA tasks.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "interaction_second_five_v1"))
    parser.add_argument("--port", type=int, default=8860)
    return parser.parse_args()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def task_json(mechanic: str) -> Path:
    return BENCH_ROOT / "environments" / f"{mechanic}_env" / "tasks" / f"{mechanic}_seed_0001" / "task.json"


def start_server(mechanic: str, port: int, state_dir: Path) -> subprocess.Popen:
    subprocess.run(["python", "-B", str(SETUP), "--task-json", str(task_json(mechanic)), "--state-dir", str(state_dir), "--seed", f"interaction-second-smoke-{mechanic}"], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    proc = subprocess.Popen(["python", "-B", str(SERVER), "--host", "127.0.0.1", "--port", str(port), "--app-dir", str(APP_DIR), "--state-dir", str(state_dir)], cwd=ROOT, env=os.environ.copy(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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


def invalid_submit(page, mechanic: str) -> None:
    renderers = {
        "domino_autopsy": "renderDominoAutopsy",
        "popup_exorcist": "renderPopupExorcist",
        "funeral_ritual": "renderFuneralRitual",
        "slime_commute": "renderSlimeCommute",
    }
    page.evaluate(
        """async ({mechanic, renderer}) => {
            const response = await fetch('/result', {method:'POST', headers:{'content-type':'application/json'}, body:JSON.stringify({mechanic_id:mechanic, challenge_id:'invalid-smoke'})});
            const outcome = await response.json();
            if (outcome.state) window[renderer](outcome.state);
            setReadout('FAIL', 'error');
        }""",
        {"mechanic": mechanic, "renderer": renderers[mechanic]},
    )


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    before = read_json(state_dir / "ground_truth.json")["challenge_id"]
    if mechanic == "consequences_boss":
        for _ in range(4):
            page.locator(".consequence-choices [data-choice]").first.click()
            page.wait_for_timeout(430)
        for _ in range(4):
            page.locator('[data-action="exploit"]').click()
            page.wait_for_timeout(390)
    else:
        invalid_submit(page, mechanic)
    expect(page.locator(".readout")).to_have_text("FAIL")
    after = read_json(state_dir / "ground_truth.json")["challenge_id"]
    if before == after:
        raise AssertionError(f"{mechanic} did not regenerate after failure")
    screenshot(page, out_dir, mechanic, "fail-refresh")


def solve_domino(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    truth = read_json(state_dir / "ground_truth.json")
    bell_contract = page.evaluate("""() => ({
        label: dominoModel.bellBody?.label,
        isSensor: dominoModel.bellBody?.isSensor,
        isStatic: dominoModel.bellBody?.isStatic,
        mass: dominoModel.bellBody?.mass,
        clapperMass: dominoModel.clapperBody?.mass,
        constraints: Matter.Composite.allConstraints(dominoModel.engine.world).map(item => item.label),
    })""")
    if (
        bell_contract["label"] != truth["bell_body_id"]
        or bell_contract["isSensor"] is not False
        or bell_contract["isStatic"] is not False
        or not (0 < float(bell_contract["mass"]) < 1000)
        or not (0 < float(bell_contract["clapperMass"]) < 1000)
        or not {"bell-pivot", "clapper-link"} <= set(bell_contract["constraints"])
    ):
        raise AssertionError(f"bell is not a finite-mass constrained physics assembly: {bell_contract}")
    canvas = page.locator(".domino-physics-canvas")
    board = canvas.bounding_box()
    if not board:
        raise AssertionError("domino physics canvas has no bounds")
    for domino_index, (domino_id, target) in enumerate(zip(truth["loose_ids"], truth["target_slots"])):
        position = page.evaluate("id => ({x: dominoModel.bodiesById[id].position.x, y: dominoModel.bodiesById[id].position.y})", domino_id)
        page.mouse.move(board["x"] + position["x"] * board["width"] / 720, board["y"] + position["y"] * board["height"] / 410)
        page.mouse.down()
        page.mouse.move(board["x"] + target["x"] * board["width"] / 720, board["y"] + target["y"] * board["height"] / 410, steps=8)
        page.mouse.up()
        for _ in range(12):
            axis_angle = float(page.evaluate("id => dominoAxisAngle(dominoModel.bodiesById[id].angle * 180 / Math.PI)", domino_id))
            if abs(axis_angle) <= 8:
                break
            page.locator("#domino-rotate-right").click()
        else:
            raise AssertionError(f"could not level domino {domino_id}")
        if domino_index == 0:
            page.locator("#domino-flip").click()
    page.locator("#domino-run").click()
    page.wait_for_timeout(1050)
    screenshot(page, out_dir, mechanic, "active-simulation")
    try:
        page.wait_for_function("dominoModel.physicsPassed === true", timeout=10000)
    except Exception as exc:
        debug = page.evaluate("""() => ({mode: dominoModel.mode, bellHit: dominoModel.bellHit, bellPeakAngle: dominoModel.bellPeakAngle, bell: dominoModel.bellBody && {x: dominoModel.bellBody.position.x, y: dominoModel.bellBody.position.y, angle: dominoModel.bellBody.angle, vx: dominoModel.bellBody.velocity.x, vy: dominoModel.bellBody.velocity.y, omega: dominoModel.bellBody.angularVelocity}, pairs: Array.from(dominoModel.collisionPairs), bodies: Object.fromEntries(dominoModel.dominoIds.map(id => { const body = dominoModel.bodiesById[id]; return [id, {x: body.position.x, y: body.position.y, angle: body.angle, vx: body.velocity.x, vy: body.velocity.y, omega: body.angularVelocity}]; }))})""")
        screenshot(page, out_dir, mechanic, "physics-failure")
        raise AssertionError(f"rigid-body chain did not reach bell: {debug}") from exc
    minimum_swing = float(truth["minimum_bell_swing_radians"])
    page.wait_for_function("minimum => dominoModel.bellPeakAngle >= minimum", arg=minimum_swing, timeout=3500)
    screenshot(page, out_dir, mechanic, "bell-impact")
    page.wait_for_function("dominoModel.mode === 'result'", timeout=11000)
    expect(page.locator(".domino-verdict")).to_contain_text("PHYSICS PASS")
    expect(page.locator(".domino-controls .readout")).to_have_text("PHYSICS PASS")
    expect(page.locator("#domino-submit")).to_contain_text("CERTIFY PASS")
    expect(page.locator("#domino-submit")).to_be_enabled()
    page.locator("#domino-submit").click()


def solve_consequences(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    state = read_json(state_dir / "public_state.json")
    truth = read_json(state_dir / "ground_truth.json")
    choices: dict[str, str] = {}
    for index, scene in enumerate(state["scenes"]):
        choice = scene["choices"][index % 2]
        choices[scene["id"]] = choice
        page.locator(f'[data-choice="{choice}"]').click()
        page.wait_for_timeout(430)
    screenshot(page, out_dir, mechanic, "boss-arrival")
    for index, scene_id in enumerate(state["boss_order"]):
        action = "protect" if choices[scene_id] == truth["kind_choices"][scene_id] else "exploit"
        page.locator(f'[data-action="{action}"]').click()
        if index == 1:
            page.wait_for_timeout(650)
            screenshot(page, out_dir, mechanic, "active-judgment")
        page.wait_for_timeout(380)


def solve_popup(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    state = read_json(state_dir / "public_state.json")
    truth = read_json(state_dir / "ground_truth.json")
    blocker = next(item for item in state["popups"] if item["id"] == truth["blocker_id"])
    for popup in sorted((item for item in state["popups"] if item["z"] > blocker["z"]), key=lambda item: item["z"], reverse=True):
        page.locator(f'.chaos-popup[data-popup-id="{popup["id"]}"] .popup-close').click()
        page.wait_for_timeout(90)
    screenshot(page, out_dir, mechanic, "kill-switch-exposed")
    page.locator(f'.chaos-popup[data-popup-id="{truth["blocker_id"]}"] .popup-close').click()
    page.wait_for_timeout(1050)


def solve_funeral(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    state = read_json(state_dir / "public_state.json")
    page.locator(".tombstone").click(position={"x": 110, "y": 245})
    page.wait_for_timeout(500)
    for index in range(int(state["brush_threshold"])):
        page.locator(f'.moss-cell[data-moss-index="{index}"]').click(force=True)
    screenshot(page, out_dir, mechanic, "epitaph-revealed")
    page.locator(".grave-candle").click()
    for flower in state["flowers"]:
        page.locator(f'.ritual-flower[data-flower-id="{flower["id"]}"]').click()
    screenshot(page, out_dir, mechanic, "bouquet-ready")
    page.locator(".ritual-bouquet").drag_to(page.locator(".grave-bed"))
    page.wait_for_timeout(850)


def wait_for_safe_lane(page, x: int, row: int) -> None:
    deadline = time.time() + 12
    while time.time() < deadline:
        first = bool(page.evaluate("({x,row}) => slimeLaneSafe(x,row)", {"x": x, "row": row}))
        if first:
            page.wait_for_timeout(70)
            if bool(page.evaluate("({x,row}) => slimeLaneSafe(x,row)", {"x": x, "row": row})):
                return
        page.wait_for_timeout(35)
    raise AssertionError(f"lane {row} never became safe at x={x}")


def solve_slime(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    state = read_json(state_dir / "public_state.json")
    for target_row in range(9, 0, -1):
        x = int(page.evaluate("slimeModel.player.x"))
        wait_for_safe_lane(page, x, target_row)
        page.keyboard.press("w")
        page.wait_for_timeout(90)
        actual_row = int(page.evaluate("slimeModel.player.y"))
        if actual_row != target_row:
            raise AssertionError(f"slime failed to enter row {target_row}; at {actual_row}")
        if target_row == 6:
            screenshot(page, out_dir, mechanic, "active-crossing")
    goal_x = int(state["board"]["goal_x"])
    current_x = int(page.evaluate("slimeModel.player.x"))
    key = "d" if goal_x > current_x else "a"
    for _ in range(abs(goal_x - current_x)):
        page.keyboard.press(key)
        page.wait_for_timeout(70)
    page.keyboard.press("w")
    page.wait_for_timeout(650)


SOLVERS = {
    "domino_autopsy": solve_domino,
    "consequences_boss": solve_consequences,
    "popup_exorcist": solve_popup,
    "funeral_ritual": solve_funeral,
    "slime_commute": solve_slime,
}


def load_helpers():
    spec = importlib.util.spec_from_file_location("interaction_second_verifier_helpers", HELPERS)
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
    temp_root = Path(tempfile.mkdtemp(prefix="interaction-second-five-"))
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
                page.wait_for_selector(ROOT_SELECTORS[mechanic])
                screenshot(page, out_dir, mechanic, "initial")
                fail_once(page, state_dir, out_dir, mechanic)
                SOLVERS[mechanic](page, state_dir, out_dir, mechanic)
                expect(page.locator(".readout")).to_have_text("PASS", timeout=5000)
                screenshot(page, out_dir, mechanic, "pass")
                result = read_json(state_dir / "result.json")
                ground_truth = read_json(state_dir / "ground_truth.json")
                if not (result.get("server_grade") or {}).get("passed"):
                    raise AssertionError(f"{mechanic} server grade did not pass: {result!r}")
                verified = getattr(helpers, VERIFY_FUNCTIONS[mechanic])({"result": result, "ground_truth": ground_truth})
                if verified.get("score") != 100 or not verified.get("passed"):
                    raise AssertionError(f"{mechanic} verifier did not score 100: {verified!r}")
                if errors:
                    raise AssertionError(f"{mechanic} browser errors: {errors}")
                summary[mechanic] = {"ok": True, "challenge_id": ground_truth["challenge_id"], "server_grade": result["server_grade"], "verifier": verified, "screenshots": sorted(path.name for path in out_dir.glob(f"{mechanic}-*.png"))}
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
