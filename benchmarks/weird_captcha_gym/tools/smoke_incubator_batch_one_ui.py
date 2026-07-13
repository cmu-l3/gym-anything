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
from types import ModuleType
from urllib.request import urlopen

from playwright.sync_api import expect, sync_playwright


ROOT = Path(__file__).resolve().parents[3]
BENCH_ROOT = ROOT / "benchmarks" / "weird_captcha_gym"
APP_DIR = BENCH_ROOT / "shared_runtime" / "app"
SERVER = BENCH_ROOT / "shared_runtime" / "server" / "weird_captcha_server.py"
SETUP = BENCH_ROOT / "shared_scripts" / "setup_task.py"
GRADER_ROOT = BENCH_ROOT / "shared_runtime" / "server" / "incubator_graders"
SOLVER_ROOT = BENCH_ROOT / "tools" / "incubator_solvers"

MECHANICS = (
    "wrong_number",
    "bomb_manual_from_hell",
    "dead_mans_switch",
    "blind_dice_courier",
    "input_lag_forklift",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Exercise and capture Incubator Batch 1.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "incubator_batch_one_v1"))
    parser.add_argument("--port", type=int, default=8860)
    return parser.parse_args()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def task_json(mechanic: str) -> Path:
    return BENCH_ROOT / "environments" / f"{mechanic}_env" / "tasks" / f"{mechanic}_seed_0001" / "task.json"


def load_module(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def start_server(mechanic: str, port: int, state_dir: Path, seed_prefix: str) -> subprocess.Popen:
    subprocess.run(
        [
            "python", "-B", str(SETUP), "--task-json", str(task_json(mechanic)),
            "--state-dir", str(state_dir), "--seed", f"{seed_prefix}-{mechanic}",
        ],
        cwd=ROOT,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    proc = subprocess.Popen(
        [
            "python", "-B", str(SERVER), "--host", "127.0.0.1", "--port", str(port),
            "--app-dir", str(APP_DIR), "--state-dir", str(state_dir),
        ],
        cwd=ROOT,
        env={**os.environ, "WEIRD_CAPTCHA_CHEAT_PASSWORD": "incubator-smoke-only"},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            urlopen(f"http://127.0.0.1:{port}/health", timeout=0.5).read()
            return proc
        except Exception:
            time.sleep(0.1)
    proc.kill()
    raise RuntimeError(f"server did not start for {mechanic}")


def exported_payload(state_dir: Path) -> dict:
    return {
        "public_state": read_json(state_dir / "public_state.json"),
        "ground_truth": read_json(state_dir / "ground_truth.json"),
        "result": read_json(state_dir / "result.json"),
    }


def run_task_verifier(mechanic: str, exported: dict, temporary: Path) -> dict:
    verifier_path = task_json(mechanic).parent / "verifier.py"
    verifier = load_module(verifier_path, f"incubator_task_verifier_{mechanic}")
    export_path = temporary / f"{mechanic}-export.json"
    export_path.write_text(json.dumps(exported), encoding="utf-8")

    def copy_from_env(source: str, destination: str) -> None:
        if source != "/tmp/task_result.json":
            raise ValueError(f"unexpected verifier source: {source}")
        shutil.copyfile(export_path, destination)

    result = verifier.verify_task(env_info={"copy_from_env": copy_from_env})
    if not isinstance(result, dict):
        raise AssertionError(f"{mechanic} verifier returned {result!r}")
    return result


def screenshot(page, out_dir: Path, mechanic: str, name: str) -> None:
    page.screenshot(path=str(out_dir / f"{mechanic}-{name}.png"), full_page=True)


def run_batch(*, mechanics: tuple[str, ...], out_dir: Path, port: int, seed_prefix: str) -> dict[str, object]:
    out_dir.mkdir(parents=True, exist_ok=True)
    for mechanic in mechanics:
        for stale in out_dir.glob(f"{mechanic}-*.png"):
            stale.unlink()
    summary: dict[str, object] = {"ok": True, "mechanics": {}}

    with tempfile.TemporaryDirectory(prefix="incubator-batch-one-") as temp_name, sync_playwright() as playwright:
        temporary = Path(temp_name)
        browser = playwright.chromium.launch(headless=True)
        for index, mechanic in enumerate(mechanics):
            state_dir = temporary / mechanic
            state_dir.mkdir()
            mechanic_port = port + index
            server = start_server(mechanic, mechanic_port, state_dir, seed_prefix)
            page = browser.new_page(viewport={"width": 1280, "height": 720}, device_scale_factor=1)
            console_errors: list[str] = []
            page.on("console", lambda message, errors=console_errors: errors.append(message.text) if message.type == "error" else None)
            page.on("pageerror", lambda error, errors=console_errors: errors.append(str(error)))
            try:
                page.goto(f"http://127.0.0.1:{mechanic_port}/", wait_until="networkidle")
                page.wait_for_function(
                    "mechanic => Boolean(window.WeirdCaptchaMechanics?.[mechanic]?.rootSelector)",
                    arg=mechanic,
                )
                root_selector = page.evaluate(
                    "mechanic => window.WeirdCaptchaMechanics[mechanic].rootSelector",
                    mechanic,
                )
                expect(page.locator(root_selector)).to_be_visible()
                screenshot(page, out_dir, mechanic, "initial")

                solver = load_module(SOLVER_ROOT / f"{mechanic}.py", f"incubator_solver_{mechanic}")
                solver.fail_once(page, state_dir, out_dir, mechanic)
                solver.solve(page, state_dir, out_dir, mechanic)
                expect(page.locator(".readout")).to_contain_text("PASS", timeout=12_000)
                expect(page.locator(".readout")).to_have_attribute("data-status", "passed")
                screenshot(page, out_dir, mechanic, "pass")

                exported = exported_payload(state_dir)
                server_grade = exported["result"].get("server_grade") or {}
                grader = load_module(GRADER_ROOT / f"{mechanic}.py", f"incubator_grader_smoke_{mechanic}")
                direct_grade = grader.grade(exported["result"], exported["ground_truth"], exported["public_state"])
                verifier_result = run_task_verifier(mechanic, exported, temporary)
                if server_grade.get("passed") is not True:
                    raise AssertionError(f"{mechanic} server rejected solved UI path: {server_grade}")
                if direct_grade.get("passed") is not True:
                    raise AssertionError(f"{mechanic} independent grader rejected solved UI path: {direct_grade}")
                if verifier_result.get("passed") is not True:
                    raise AssertionError(f"{mechanic} task verifier rejected solved UI path: {verifier_result}")
                if console_errors:
                    raise AssertionError(f"{mechanic} browser errors: {console_errors}")
                summary["mechanics"][mechanic] = {
                    "ok": True,
                    "server_grade": server_grade,
                    "direct_grade": direct_grade,
                    "verifier": verifier_result,
                    "screenshots": sorted(path.name for path in out_dir.glob(f"{mechanic}-*.png")),
                }
            except Exception as exc:
                summary["ok"] = False
                summary["mechanics"][mechanic] = {"ok": False, "error": str(exc), "console_errors": console_errors}
                screenshot(page, out_dir, mechanic, "unexpected-failure")
                raise
            finally:
                page.close()
                server.terminate()
                try:
                    server.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    server.kill()
        browser.close()

    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def main() -> None:
    args = parse_args()
    run_batch(
        mechanics=MECHANICS,
        out_dir=Path(args.out_dir),
        port=args.port,
        seed_prefix="incubator-batch-one-smoke",
    )


if __name__ == "__main__":
    main()
