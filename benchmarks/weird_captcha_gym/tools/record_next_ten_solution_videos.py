#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from playwright.sync_api import expect, sync_playwright


ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from benchmarks.weird_captcha_gym.tools.smoke_incubator_batch_one_ui import (  # noqa: E402
    BENCH_ROOT,
    GRADER_ROOT,
    SOLVER_ROOT,
    exported_payload,
    load_module,
    run_task_verifier,
    start_server,
)


MECHANICS = (
    "impossible_panorama",
    "flat_pack_compliance",
    "crash_deadline_hovercar",
    "robot_art_critic",
    "wrong_number",
    "bomb_manual_from_hell",
    "dead_mans_switch",
    "blind_dice_courier",
    "input_lag_forklift",
    "insider_trading_captcha",
)

WALKTHROUGHS = {
    "impossible_panorama": (
        "Impossible Panorama",
        "Search the full deep-field plate, tune zoom and focal depth, center the transient ring event, then sustain the shutter hold.",
    ),
    "flat_pack_compliance": (
        "Flat-Pack Compliance",
        "Place and orient all seven rigid parts, mate all six keyed joints, then survive the complete 36-step load test.",
    ),
    "crash_deadline_hovercar": (
        "Crash-Deadline Hovercar",
        "Drive around six collision obstacles while keeping the pointer over all five moving authentication beacons, then reach the finish.",
    ),
    "robot_art_critic": (
        "Robot Art Critic",
        "Construct the requested object with 10–14 continuous mouse strokes and submit the complete topology to the critic.",
    ),
    "wrong_number": (
        "Wrong Number",
        "Find the authentic carrier, then continuously correct phase and skew until it survives the complete drifting lock trial.",
    ),
    "bomb_manual_from_hell": (
        "Bomb Manual From Hell",
        "Drag, rotate, and flip all five acetate plates onto their asymmetric pins; cut the one wire exposed by all 25 apertures.",
    ),
    "dead_mans_switch": (
        "Dead Man's Switch",
        "Track the moving pressure pad with the mouse while steering a 45–57 move route through all five barriers by keyboard.",
    ),
    "blind_dice_courier": (
        "Blind Dice Courier",
        "Track the hidden die orientation across roughly 60 rolls, using four scanners to satisfy all five face gates before delivery.",
    ),
    "input_lag_forklift": (
        "Input-Lag Forklift",
        "Plan a two-crate Sokoban route around one-command input delay, then flush the final queued direction with both crates docked.",
    ),
    "insider_trading_captcha": (
        "Insider Trading CAPTCHA",
        "Trade the irregular live tape through a three-tick settlement queue, exceed the causal profit target, and close flat with no pending orders.",
    ),
}

# These delays affect only the recording harness. They make short keyboard-only
# solutions legible without changing any task, generator, runtime, or verifier.
PACE = {
    "impossible_panorama": {"key_press_ms": 10, "minimum_short_wait_ms": 0},
    "wrong_number": {"key_press_ms": 8, "minimum_short_wait_ms": 0},
    "dead_mans_switch": {"key_press_ms": 0, "minimum_short_wait_ms": 170},
    "blind_dice_courier": {"key_press_ms": 0, "minimum_short_wait_ms": 190},
    "input_lag_forklift": {"key_press_ms": 0, "minimum_short_wait_ms": 190},
}


class _PacedKeyboard:
    def __init__(self, page: Any, pause_ms: int) -> None:
        self._page = page
        self._keyboard = page.keyboard
        self._pause_ms = pause_ms

    def press(self, key: str, **kwargs: Any) -> None:
        self._keyboard.press(key, **kwargs)
        if self._pause_ms:
            self._page.wait_for_timeout(self._pause_ms)

    def __getattr__(self, name: str) -> Any:
        return getattr(self._keyboard, name)


class _PacedPage:
    def __init__(self, page: Any, *, key_press_ms: int, minimum_short_wait_ms: int) -> None:
        self._page = page
        self.keyboard = _PacedKeyboard(page, key_press_ms)
        self.mouse = page.mouse
        self._minimum_short_wait_ms = minimum_short_wait_ms

    def wait_for_timeout(self, milliseconds: float) -> None:
        delay = milliseconds
        if 0 < milliseconds <= 150 and self._minimum_short_wait_ms:
            delay = max(milliseconds, self._minimum_short_wait_ms)
        self._page.wait_for_timeout(delay)

    def __getattr__(self, name: str) -> Any:
        return getattr(self._page, name)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Record paced solution videos for the frozen next-ten v3 difficulty cohort.")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=BENCH_ROOT / "evidence" / "next_ten_difficulty_v3" / "solution_videos",
    )
    parser.add_argument("--port", type=int, default=9180)
    parser.add_argument("--seed-prefix", default="next-ten-difficulty-v3-solution-video")
    parser.add_argument("--mechanic", action="append", choices=MECHANICS)
    return parser.parse_args()


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _frozen_contract_files(mechanic: str) -> dict[str, Path]:
    return {
        "task": BENCH_ROOT / "environments" / f"{mechanic}_env" / "tasks" / f"{mechanic}_seed_0001" / "task.json",
        "generator": BENCH_ROOT / "shared_scripts" / "incubator_generators" / f"{mechanic}.py",
        "frontend": BENCH_ROOT / "shared_runtime" / "app" / "mechanics" / f"{mechanic}.js",
        "grader": GRADER_ROOT / f"{mechanic}.py",
        "solver": SOLVER_ROOT / f"{mechanic}.py",
    }


def _frozen_contract_snapshot(mechanics: tuple[str, ...]) -> dict[str, dict[str, str]]:
    return {
        mechanic: {
            label: _sha256(path)
            for label, path in _frozen_contract_files(mechanic).items()
        }
        for mechanic in mechanics
    }


def _inject_walkthrough_chrome(
    page: Any, title: str, description: str, *, show_intro: bool = True
) -> None:
    page.evaluate(
        """config => {
          document.querySelectorAll('[data-solution-video-overlay]').forEach(node => node.remove());

          const cursor = document.createElement('div');
          cursor.dataset.solutionVideoOverlay = 'cursor';
          cursor.style.cssText = [
            'position:fixed', 'left:0', 'top:0', 'width:22px', 'height:22px',
            'border:3px solid #d9ff57', 'border-radius:50%', 'translate:-50% -50%',
            'box-shadow:0 0 0 4px rgba(3,10,14,.78),0 0 18px rgba(217,255,87,.95)',
            'pointer-events:none', 'z-index:2147483647', 'opacity:0'
          ].join(';');

          const intro = document.createElement('section');
          intro.dataset.solutionVideoOverlay = 'intro';
          intro.style.cssText = [
            'position:fixed', 'inset:0', 'display:grid', 'place-items:center',
            'background:rgba(2,8,12,.78)', 'backdrop-filter:blur(5px)',
            'pointer-events:none', 'z-index:2147483646',
            'font-family:ui-monospace,SFMono-Regular,Menlo,monospace',
            'transition:opacity .28s ease'
          ].join(';');
          const panel = document.createElement('div');
          panel.style.cssText = [
            'width:min(760px,calc(100vw - 80px))', 'padding:30px 34px',
            'border:1px solid rgba(217,255,87,.8)', 'background:rgba(4,14,18,.96)',
            'box-shadow:0 24px 80px rgba(0,0,0,.6)', 'color:#f4f7e8'
          ].join(';');
          const eyebrow = document.createElement('div');
          eyebrow.textContent = 'SOLUTION WALKTHROUGH · ORDINARY BROWSER INPUT';
          eyebrow.style.cssText = 'color:#d9ff57;font-size:12px;letter-spacing:.18em;margin-bottom:14px';
          const heading = document.createElement('div');
          heading.textContent = config.title;
          heading.style.cssText = 'font:700 36px/1.1 Georgia,serif;margin-bottom:15px';
          const body = document.createElement('div');
          body.textContent = config.description;
          body.style.cssText = 'font:500 17px/1.55 Georgia,serif;color:#e5e8da';
          panel.append(eyebrow, heading, body);
          intro.append(panel);

          const outro = document.createElement('div');
          outro.dataset.solutionVideoOverlay = 'outro';
          outro.style.cssText = [
            'position:fixed', 'left:50%', 'bottom:24px', 'translate:-50% 0',
            'max-width:min(880px,calc(100vw - 48px))', 'padding:13px 22px',
            'border:1px solid #d9ff57', 'background:rgba(4,14,18,.96)',
            'color:#f4f7e8', 'font:700 15px/1.35 ui-monospace,SFMono-Regular,Menlo,monospace',
            'box-shadow:0 14px 45px rgba(0,0,0,.55)', 'pointer-events:none',
            'z-index:2147483647', 'opacity:0', 'transition:opacity .25s ease',
            'text-align:center'
          ].join(';');

          const overlays = [cursor];
          if (config.showIntro) overlays.push(intro);
          overlays.push(outro);
          document.body.append(...overlays);
          window.addEventListener('pointermove', event => {
            cursor.style.left = `${event.clientX}px`;
            cursor.style.top = `${event.clientY}px`;
            cursor.style.opacity = '1';
          });
          window.__solutionVideoOverlay = {
            hideIntro() {
              if (intro.isConnected) {
                intro.style.opacity = '0';
                setTimeout(() => intro.remove(), 320);
              }
            },
            showOutro(message) {
              outro.textContent = message;
              outro.style.opacity = '1';
            }
          };
        }""",
        {"title": title, "description": description, "showIntro": show_intro},
    )


def _transcode(raw_path: Path, mp4_path: Path) -> None:
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(raw_path), "-an", "-c:v", "libx264", "-preset", "medium",
            "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(mp4_path),
        ],
        check=True,
    )


def _probe(path: Path) -> dict[str, Any]:
    process = subprocess.run(
        [
            "ffprobe", "-v", "error", "-show_entries",
            "format=duration,size:stream=codec_name,width,height,avg_frame_rate",
            "-select_streams", "v:0", "-of", "json", str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(process.stdout)
    stream = payload["streams"][0]
    return {
        "duration_seconds": round(float(payload["format"]["duration"]), 3),
        "bytes": int(payload["format"]["size"]),
        "codec": stream["codec_name"],
        "width": int(stream["width"]),
        "height": int(stream["height"]),
        "frame_rate": stream["avg_frame_rate"],
    }


def _solve_hovercar_with_capture_margin(
    page: Any, state_dir: Path, capture_dir: Path, mechanic: str, solver: Any
) -> None:
    """Use the legal after-check sprint that video capture overhead requires."""
    truth = json.loads((state_dir / "ground_truth.json").read_text(encoding="utf-8"))
    physics = truth["physics"]
    box = page.locator(".hover-canvas").bounding_box()
    if not box:
        raise AssertionError("hovercar flight canvas missing")
    held: set[str] = set()
    first_dwell_shot = False
    deadline = time.time() + 22
    while time.time() < deadline:
        snapshot = page.evaluate(
            """() => {
              const m = window.crashDeadlineHovercarModel;
              const active = m.state.targets.find(
                target => !m.checks.has(target.id) && m.tick >= target.window_start && m.tick <= target.window_end
              );
              return {
                tick:m.tick, progress:m.progress, lateral:m.lateral,
                velocity:m.lateralVelocity, speed:m.speed, checks:[...m.checks],
                crashed:m.crashed, finished:m.finished,
                active:active ? {id:active.id, point:m.targetPoint(active)} : null
              };
            }"""
        )
        if snapshot["crashed"]:
            raise AssertionError(f"hovercar crashed during recorded solve at {snapshot}")
        if snapshot["finished"]:
            break

        # Maintain the same humane control band as the canonical v3 solver.
        # Full throttle after the final beacon is unsafe around the remaining
        # physical obstacles and is not needed for the 330-tick deadline.
        solver._set_key(page, held, "w", snapshot["speed"] < 45)
        solver._set_key(page, held, "s", snapshot["speed"] > 53)
        desired_offset = 0.0
        for obstacle in truth["obstacles"]:
            distance = float(obstacle["world_x"]) - snapshot["progress"]
            if -42 <= distance <= 105:
                desired_offset = -62.0 if float(obstacle["lane_offset"]) > 0 else 62.0
                break
        desired = solver._road(snapshot["progress"] + 20, physics) + desired_offset
        control = desired - snapshot["lateral"] - snapshot["velocity"] * 1.7
        solver._set_key(page, held, "d", control > 2.0)
        solver._set_key(page, held, "a", control < -2.0)
        if snapshot["active"]:
            point = snapshot["active"]["point"]
            page.mouse.move(
                box["x"] + point[0] / truth["stage"]["width"] * box["width"],
                box["y"] + point[1] / truth["stage"]["height"] * box["height"],
                steps=2,
            )
            if not first_dwell_shot and snapshot["tick"] > truth["targets"][0]["window_start"] + 4:
                solver._shot(page, capture_dir, mechanic, "simultaneous-drive-hover-dwell")
                first_dwell_shot = True
        page.wait_for_timeout(24)

    for key in list(held):
        page.keyboard.up(key)
    expect(page.locator(".hover-finish[data-visible='true']")).to_be_visible(timeout=4_000)
    finished = page.evaluate(
        """() => ({
          checks:[...window.crashDeadlineHovercarModel.checks].sort(),
          finished:window.crashDeadlineHovercarModel.finished,
          crashes:window.crashDeadlineHovercarModel.crashes,
          retries:window.crashDeadlineHovercarModel.retries,
          samples:window.crashDeadlineHovercarModel.pointerSamples,
          tick:window.crashDeadlineHovercarModel.tick
        })"""
    )
    if (
        not finished["finished"]
        or len(finished["checks"]) != len(truth["targets"])
        or finished["crashes"] != 0
        or finished["retries"] != 0
        or finished["samples"] < 20
    ):
        raise AssertionError(f"clean recorded divided-attention run incomplete: {finished}")
    solver._shot(page, capture_dir, mechanic, "solved-pre-submit")
    page.locator(".hover-submit").click()
    expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)


def main() -> None:
    args = parse_args()
    mechanics = tuple(args.mechanic or MECHANICS)
    frozen_contract_before = _frozen_contract_snapshot(mechanics)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    ffmpeg = shutil.which("ffmpeg")
    ffprobe = shutil.which("ffprobe")
    if not ffmpeg or not ffprobe:
        raise RuntimeError("solution video export requires ffmpeg and ffprobe")

    manifest: dict[str, Any] = {
        "ok": True,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "task_implementations_modified": False,
        "capture_contract": "Paced Playwright recording with ordinary mouse and keyboard input against the live frozen v3 task server.",
        "frozen_contract_files": frozen_contract_before,
        "videos": {},
    }

    with tempfile.TemporaryDirectory(prefix="next-ten-solution-video-") as temp_name, sync_playwright() as playwright:
        temporary = Path(temp_name)
        browser = playwright.chromium.launch(headless=True)
        for index, mechanic in enumerate(mechanics):
            print(f"[{index + 1}/{len(mechanics)}] recording {mechanic}", flush=True)
            state_dir = temporary / mechanic / "state"
            capture_dir = temporary / mechanic / "captures"
            browser_video_dir = temporary / mechanic / "browser-video"
            state_dir.mkdir(parents=True)
            capture_dir.mkdir(parents=True)
            browser_video_dir.mkdir(parents=True)
            raw_path = args.out_dir / f"{mechanic}-solution.webm"
            mp4_path = args.out_dir / f"{mechanic}-solution.mp4"
            raw_path.unlink(missing_ok=True)
            mp4_path.unlink(missing_ok=True)

            server = start_server(mechanic, args.port + index, state_dir, args.seed_prefix)
            context = browser.new_context(
                viewport={"width": 1280, "height": 720},
                device_scale_factor=1,
                record_video_dir=str(browser_video_dir),
                record_video_size={"width": 1280, "height": 720},
            )
            page = context.new_page()
            console_errors: list[str] = []
            page.on(
                "console",
                lambda message, errors=console_errors: errors.append(message.text)
                if message.type == "error"
                else None,
            )
            page.on("pageerror", lambda error, errors=console_errors: errors.append(str(error)))
            video = page.video
            try:
                title, description = WALKTHROUGHS[mechanic]
                page.set_content("<!doctype html><html><body></body></html>")
                _inject_walkthrough_chrome(page, title, description, show_intro=True)
                page.wait_for_timeout(1_900)

                page.goto(f"http://127.0.0.1:{args.port + index}/", wait_until="networkidle")
                page.wait_for_function(
                    "mechanic => Boolean(window.WeirdCaptchaMechanics?.[mechanic]?.rootSelector)",
                    arg=mechanic,
                )
                root_selector = page.evaluate(
                    "mechanic => window.WeirdCaptchaMechanics[mechanic].rootSelector",
                    mechanic,
                )
                expect(page.locator(root_selector)).to_be_visible()
                _inject_walkthrough_chrome(page, title, description, show_intro=False)

                pace = PACE.get(mechanic, {"key_press_ms": 0, "minimum_short_wait_ms": 0})
                paced_page = _PacedPage(page, **pace)
                solver = load_module(SOLVER_ROOT / f"{mechanic}.py", f"solution_video_solver_{mechanic}")
                if mechanic == "crash_deadline_hovercar":
                    _solve_hovercar_with_capture_margin(
                        paced_page, state_dir, capture_dir, mechanic, solver
                    )
                else:
                    solver.solve(paced_page, state_dir, capture_dir, mechanic)

                exported = exported_payload(state_dir)
                server_grade = exported["result"].get("server_grade") or {}
                grader = load_module(GRADER_ROOT / f"{mechanic}.py", f"solution_video_grader_{mechanic}")
                direct_grade = grader.grade(
                    exported["result"], exported["ground_truth"], exported["public_state"]
                )
                verifier = run_task_verifier(mechanic, exported, temporary)
                for label, grade in (
                    ("server", server_grade), ("direct", direct_grade), ("verifier", verifier)
                ):
                    if grade.get("passed") is not True:
                        raise AssertionError(f"{mechanic} {label} grade rejected recorded solve: {grade}")
                if console_errors:
                    raise AssertionError(f"{mechanic} browser errors: {console_errors}")

                feedback = str(server_grade.get("feedback") or "accepted")
                page.evaluate(
                    "message => window.__solutionVideoOverlay.showOutro(message)",
                    f"PASS · LIVE SERVER ACCEPTED · {feedback}",
                )
                page.wait_for_timeout(2_000)
            finally:
                page.close()
                if video is not None:
                    video.save_as(str(raw_path))
                context.close()
                server.terminate()
                try:
                    server.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    server.kill()

            _transcode(raw_path, mp4_path)
            manifest["videos"][mechanic] = {
                "title": WALKTHROUGHS[mechanic][0],
                "approach": WALKTHROUGHS[mechanic][1],
                "webm": raw_path.name,
                "mp4": mp4_path.name,
                "webm_sha256": _sha256(raw_path),
                "mp4_sha256": _sha256(mp4_path),
                "media": _probe(mp4_path),
                "server_grade": server_grade,
                "direct_grade": direct_grade,
                "verifier": verifier,
                "console_errors": console_errors,
            }
            print(
                f"[{index + 1}/{len(mechanics)}] PASS {mechanic} "
                f"({_probe(mp4_path)['duration_seconds']:.1f}s)",
                flush=True,
            )
        browser.close()

    frozen_contract_after = _frozen_contract_snapshot(mechanics)
    if frozen_contract_after != frozen_contract_before:
        raise AssertionError("a frozen task, generator, frontend, grader, or solver changed during video capture")
    manifest["frozen_contract_verified"] = True

    manifest_path = args.out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
    print(manifest_path, flush=True)


if __name__ == "__main__":
    main()
