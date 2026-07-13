#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
from pathlib import Path

from playwright.sync_api import expect, sync_playwright


ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from benchmarks.weird_captcha_gym.tools.incubator_solvers.reviewed_overhaul_common import center


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Record a paced Semantic Drag-Drop solution walkthrough.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8995")
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    return parser.parse_args()


def caption(page, message: str) -> None:
    page.evaluate("message => { document.querySelector('#walkthrough-caption').textContent = message; }", message)
    page.wait_for_timeout(850)


def move_to(page, locator, *, steps: int = 18) -> tuple[float, float]:
    point = center(locator)
    page.mouse.move(*point, steps=steps)
    page.wait_for_timeout(180)
    return point


def hold_probe(page, object_id: str, kind: str, hold_ms: int) -> None:
    tool = page.locator(f'.probe-tool[data-probe="{kind}"]')
    specimen = page.locator(f'[data-object-id="{object_id}"]')
    start = move_to(page, tool)
    target = center(specimen)
    page.mouse.down()
    page.mouse.move(*target, steps=20)
    page.wait_for_timeout(hold_ms + 180)
    page.mouse.up()
    page.wait_for_timeout(650)


def drag_specimen(page, object_id: str, receiver_id: str) -> None:
    source = page.locator(f'[data-object-id="{object_id}"]')
    receiver = page.locator(f'[data-receiver-id="{receiver_id}"]')
    move_to(page, source)
    page.mouse.down()
    page.mouse.move(*center(receiver), steps=24)
    page.wait_for_timeout(240)
    page.mouse.up()
    page.wait_for_timeout(650)


def main() -> None:
    args = parse_args()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    temporary_video = args.out.with_suffix(".webm")
    record_dir = Path(tempfile.mkdtemp(prefix="semantic-walkthrough-video-"))

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context(
            viewport={"width": 1280, "height": 720},
            record_video_dir=str(record_dir),
            record_video_size={"width": 1280, "height": 720},
        )
        page = context.new_page()
        page.goto(args.base_url, wait_until="networkidle")
        expect(page.locator(".causal-captcha")).to_be_visible()
        # /state intentionally creates a fresh challenge on page load, so the
        # recording must read the identities only after that navigation.
        public = json.loads((args.state_dir / "public_state.json").read_text(encoding="utf-8"))
        truth = json.loads((args.state_dir / "ground_truth.json").read_text(encoding="utf-8"))
        page.evaluate("""() => {
          const pointer = document.createElement('div');
          pointer.id = 'walkthrough-pointer';
          pointer.style.cssText = 'position:fixed;left:0;top:0;width:24px;height:24px;border:3px solid #d8ff5b;border-radius:50%;translate:-50% -50%;z-index:10001;pointer-events:none;box-shadow:0 0 0 4px rgba(7,17,22,.75),0 0 22px #d8ff5b;';
          const caption = document.createElement('div');
          caption.id = 'walkthrough-caption';
          caption.style.cssText = 'position:fixed;left:50%;bottom:88px;translate:-50% 0;max-width:850px;padding:13px 20px;border:1px solid #d8ff5b;background:rgba(5,14,18,.96);color:#f4f6e9;font:700 17px Georgia,serif;line-height:1.35;text-align:center;z-index:10000;pointer-events:none;box-shadow:0 12px 35px #000;';
          document.body.append(pointer, caption);
          window.addEventListener('pointermove', event => { pointer.style.left = `${event.clientX}px`; pointer.style.top = `${event.clientY}px`; });
        }""")

        caption(page, "Each specimen and receiver has two behaviors: thermal size and polarity direction.")
        caption(page, "Hold both probes over a specimen, observe its two reactions, then find a receiver with the same pair.")

        for index, specimen in enumerate(public["objects"], start=1):
            object_id = str(specimen["id"])
            receiver_id = str(truth["expected_assignments"][object_id])
            signature = specimen["runtime_signature"]
            thermal_word = "EXPANDS" if signature["thermal"] == "bloom" else "SHRINKS"
            direction_word = str(signature["polarity"]).upper()

            caption(page, f"Specimen {index}: drag the heat probe onto it and hold.")
            hold_probe(page, object_id, "thermal", int(public["probe_hold_ms"]))
            caption(page, f"Thermal observation: it {thermal_word}.")

            caption(page, "Now hold the polarity probe over the same specimen.")
            hold_probe(page, object_id, "polarity", int(public["probe_hold_ms"]))
            caption(page, f"Polarity observation: its mark shifts {direction_word}.")

            caption(page, "Pulse the matching receiver's small corner button to compare its combined response.")
            receiver = page.locator(f'[data-receiver-id="{receiver_id}"]')
            move_to(page, receiver.locator("button"))
            receiver.locator("button").click()
            page.wait_for_timeout(700)

            caption(page, f"The receiver also {thermal_word.lower()} and shifts {direction_word.lower()}; drag the specimen into it.")
            drag_specimen(page, object_id, receiver_id)

        caption(page, "All four causal signatures are matched. Certify the routing.")
        move_to(page, page.locator(".causal-submit"))
        page.locator(".causal-submit").click()
        expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
        caption(page, "PASS — the mapping came from interaction; the initial screenshot contained no answer.")
        page.wait_for_timeout(1_600)

        video = page.video
        page.close()
        if video is None:
            raise RuntimeError("Playwright did not create a walkthrough video")
        video.save_as(str(temporary_video))
        context.close()
        browser.close()
    shutil.rmtree(record_dir, ignore_errors=True)
    print(temporary_video)


if __name__ == "__main__":
    main()
