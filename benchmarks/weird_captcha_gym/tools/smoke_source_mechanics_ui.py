#!/usr/bin/env python3
from __future__ import annotations

import argparse
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

MECHANICS = (
    "semantic_drag_drop_absurdity",
    "reload_interruption",
    "rotate_wrong_thing_upright",
    "bureaucratic_signature_trap",
    "wonky_text_hostile_rendering",
    "temporal_memory_first_change",
)

FORBIDDEN_VISIBLE_SNIPPETS = (
    "correct ",
    "extra ",
    "missed ",
    "submitted",
    "hint",
    "tutorial",
    "try again",
    "new images loaded",
    "score",
    "answer",
    "reveal",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Smoke-test source-grounded Weird CAPTCHA mechanics.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "source_mechanics_v1"))
    parser.add_argument("--port", type=int, default=8810)
    parser.add_argument("--cheat-password", default="source-dev")
    return parser.parse_args()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def task_json(mechanic: str) -> Path:
    return BENCH_ROOT / "environments" / f"{mechanic}_env" / "tasks" / f"{mechanic}_seed_0001" / "task.json"


def assert_no_visible_hints(page) -> None:
    visible = page.locator("body").inner_text().lower()
    leaked = [snippet for snippet in FORBIDDEN_VISIBLE_SNIPPETS if snippet in visible]
    if leaked:
        raise AssertionError(f"visible UI leaks forbidden text: {leaked}; visible={visible!r}")


def start_server(mechanic: str, port: int, state_dir: Path, cheat_password: str) -> subprocess.Popen:
    subprocess.run(
        [
            "python",
            "-B",
            str(SETUP),
            "--task-json",
            str(task_json(mechanic)),
            "--state-dir",
            str(state_dir),
            "--seed",
            f"smoke-{mechanic}",
        ],
        cwd=ROOT,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    env = os.environ.copy()
    env["WEIRD_CAPTCHA_CHEAT_PASSWORD"] = cheat_password
    proc = subprocess.Popen(
        [
            "python",
            "-B",
            str(SERVER),
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
            "--app-dir",
            str(APP_DIR),
            "--state-dir",
            str(state_dir),
        ],
        cwd=ROOT,
        env=env,
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


def solve_semantic(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    ground_truth = read_json(state_dir / "ground_truth.json")
    for object_id, zone_id in ground_truth["expected_assignments"].items():
        source = page.locator(f'.drag-object[data-object-id="{object_id}"]')
        target = page.locator(f'.drop-zone[data-zone-id="{zone_id}"]')
        source.drag_to(target)
    page.locator("#submit-semantic").click()
    expect(page.locator(".readout")).to_have_text("PASS")


def solve_reload(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    state = read_json(state_dir / "public_state.json")
    required = int(state["base_task"]["steps_required"])
    by_step = {int(item["step"]): item for item in state["interruptions"]}
    captured_overlay = False
    for step in range(1, required + 1):
        page.locator("#reload-lever").click()
        if step not in by_step:
            continue
        overlay = by_step[step]
        if not captured_overlay:
            screenshot(page, out_dir, mechanic, f"interruption-step-{step}")
            captured_overlay = True
        if overlay["type"] == "type_code":
            page.locator("#reload-code-input").fill(str(overlay["answer"]))
            page.locator("#reload-overlay-submit").click()
        elif overlay["type"] == "press_lit":
            page.locator(f'.reload-choice[data-value="{overlay["answer"]}"]').click()
        else:
            for value in overlay["answer"]:
                page.locator(f'.reload-choice[data-value="{value}"]').click()
    page.locator("#submit-reload").click()
    expect(page.locator(".readout")).to_have_text("PASS")


def nearest_step(angle: float, step: int = 15) -> int:
    return int(round(angle / step) * step) % 360


def solve_rotate(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    ground_truth = read_json(state_dir / "ground_truth.json")
    angle = nearest_step(float(ground_truth["target_angle"]))
    page.locator("#rotate-slider").evaluate(
        "(el, value) => { el.value = String(value); el.dispatchEvent(new Event('input', {bubbles: true})); }",
        angle,
    )
    page.locator("#submit-rotate").click()
    expect(page.locator(".readout")).to_have_text("PASS")


def solve_form(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    ground_truth = read_json(state_dir / "ground_truth.json")
    mark = ground_truth["required_marks"][0]
    page.locator(f'.form-tool[data-tool="{mark["mark_type"]}"]').click()
    page.locator(f'.form-field[data-field-id="{mark["field_id"]}"]').click()
    page.locator("#submit-form").click()
    expect(page.locator(".readout")).to_have_text("PASS")


def solve_wonky(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    ground_truth = read_json(state_dir / "ground_truth.json")
    page.locator("#wonky-input").fill(str(ground_truth["token"]))
    page.locator("#submit-wonky").click()
    expect(page.locator(".readout")).to_have_text("PASS")


def solve_temporal(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    ground_truth = read_json(state_dir / "ground_truth.json")
    state = read_json(state_dir / "public_state.json")
    target_id = ground_truth["target_object_id"]
    target = next(item for item in state["timeline"]["objects"] if item["id"] == target_id)
    page.wait_for_timeout(int(ground_truth["first_change_ms"]) + 250)
    canvas = page.locator(".temporal-canvas")
    box = canvas.bounding_box()
    if not box:
        raise AssertionError("temporal canvas has no bounding box")
    scale_x = box["width"] / 680
    scale_y = box["height"] / 300
    page.mouse.click(box["x"] + float(target["x"]) * scale_x, box["y"] + float(target["y"]) * scale_y)
    page.locator("#submit-temporal").click()
    expect(page.locator(".readout")).to_have_text("PASS")


SOLVERS = {
    "semantic_drag_drop_absurdity": solve_semantic,
    "reload_interruption": solve_reload,
    "rotate_wrong_thing_upright": solve_rotate,
    "bureaucratic_signature_trap": solve_form,
    "wonky_text_hostile_rendering": solve_wonky,
    "temporal_memory_first_change": solve_temporal,
}


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    temp_root = Path(tempfile.mkdtemp(prefix="weird-source-mechanics-"))
    summary: dict[str, dict] = {}

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        for index, mechanic in enumerate(MECHANICS):
            port = args.port + index
            state_dir = temp_root / mechanic
            state_dir.mkdir(parents=True, exist_ok=True)
            proc = start_server(mechanic, port, state_dir, args.cheat_password)
            try:
                page = browser.new_page(viewport={"width": 1280, "height": 820}, device_scale_factor=1)
                page.goto(f"http://127.0.0.1:{port}")
                page.wait_for_load_state("networkidle")
                assert_no_visible_hints(page)
                screenshot(page, out_dir, mechanic, "initial")
                SOLVERS[mechanic](page, state_dir, out_dir, mechanic)
                assert_no_visible_hints(page)
                screenshot(page, out_dir, mechanic, "pass")
                result = read_json(state_dir / "result.json")
                if not (result.get("server_grade") or {}).get("passed"):
                    raise AssertionError(f"{mechanic} server grade did not pass: {result!r}")
                summary[mechanic] = {
                    "ok": True,
                    "challenge_id": read_json(state_dir / "ground_truth.json").get("challenge_id"),
                }
                page.close()
            finally:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
        browser.close()
    shutil.rmtree(temp_root)
    print(json.dumps({"ok": True, "mechanics": summary, "out_dir": str(out_dir)}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
