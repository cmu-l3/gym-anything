#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from playwright.sync_api import expect, sync_playwright


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
    "cheat",
    "answer",
    "reveal",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Smoke-test the Weird CAPTCHA cursor-lens UI.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8794")
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--cheat-password", help="also verify dev-only target reveal")
    return parser.parse_args()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def assert_no_visible_hints(text: str) -> None:
    lowered = text.lower()
    leaked = [snippet for snippet in FORBIDDEN_VISIBLE_SNIPPETS if snippet in lowered]
    if leaked:
        raise AssertionError(f"visible UI leaks forbidden text: {leaked}; visible={text!r}")


def canvas_nonblank_ratio(page) -> float:
    return float(page.evaluate(
        """
        () => {
          const canvas = document.querySelector(".lens-canvas");
          const ctx = canvas.getContext("2d");
          const img = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
          let changed = 0;
          let sampled = 0;
          for (let i = 0; i < img.length; i += 96) {
            const r = img[i], g = img[i + 1], b = img[i + 2], a = img[i + 3];
            if (a > 0 && (r > 15 || g > 20 || b > 24)) changed += 1;
            sampled += 1;
          }
          return sampled ? changed / sampled : 0;
        }
        """,
    ))


def click_canvas_point(page, x: float, y: float) -> None:
    move_canvas_point(page, x, y)
    page.mouse.down()
    page.mouse.up()


def move_canvas_point(page, x: float, y: float) -> None:
    canvas = page.locator(".lens-canvas")
    box = canvas.bounding_box()
    if not box:
        raise AssertionError("lens canvas has no bounding box")
    size = canvas.evaluate("(node) => ({width: node.width, height: node.height})")
    page.mouse.move(
        box["x"] + x * box["width"] / size["width"],
        box["y"] + y * box["height"] / size["height"],
    )


def challenge_id(page) -> str:
    value = page.locator(".lens-captcha").get_attribute("data-challenge-id")
    if not value:
        raise AssertionError("missing challenge id")
    return value


def main() -> None:
    args = parse_args()
    state_dir = Path(args.state_dir)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1360, "height": 980}, device_scale_factor=1)
        page.goto(args.base_url)
        page.wait_for_load_state("networkidle")
        expect(page.locator(".lens-canvas")).to_be_visible()
        initial_text = page.locator("body").inner_text()
        assert_no_visible_hints(initial_text)
        ratio = canvas_nonblank_ratio(page)
        if ratio < 0.15:
            raise AssertionError(f"lens canvas render appears blank; nonblank ratio={ratio:.4f}")
        initial_challenge = challenge_id(page)
        page.screenshot(path=str(out_dir / "cursor-lens-initial.png"), full_page=True)

        page.reload()
        page.wait_for_load_state("networkidle")
        expect(page.locator(".lens-canvas")).to_be_visible()
        refreshed_challenge = challenge_id(page)
        if refreshed_challenge == initial_challenge:
            raise AssertionError("browser refresh did not generate a fresh cursor-lens challenge")
        assert_no_visible_hints(page.locator("body").inner_text())
        page.screenshot(path=str(out_dir / "cursor-lens-refresh.png"), full_page=True)

        ground_truth = read_json(state_dir / "ground_truth.json")
        expected = ground_truth.get("expected_click") or {}
        move_canvas_point(page, float(expected["x"]), float(expected["y"]))
        page.screenshot(path=str(out_dir / "cursor-lens-target-scan.png"), full_page=True)

        if args.cheat_password:
            cheat_page = browser.new_page(viewport={"width": 1360, "height": 980}, device_scale_factor=1)
            cheat_page.goto(f"{args.base_url.rstrip('/')}/?cheat=1")
            cheat_page.wait_for_load_state("networkidle")
            expect(cheat_page.locator(".lens-canvas")).to_be_visible()
            expect(cheat_page.locator(".cheat-panel")).to_be_visible()
            cheat_page.locator("#cheat-password").fill(args.cheat_password)
            cheat_page.locator(".cheat-submit").click()
            expect(cheat_page.locator("#cheat-output")).to_contain_text("Target:")
            cheat_page.screenshot(path=str(out_dir / "cursor-lens-cheat.png"), full_page=True)
            cheat_page.close()

        click_canvas_point(page, 8, 8)
        page.locator("#submit-lens-click").click()
        expect(page.locator(".readout")).to_have_text("FAIL")
        fail_challenge = challenge_id(page)
        if fail_challenge == refreshed_challenge:
            raise AssertionError("failed cursor-lens attempt did not load a fresh challenge")
        assert_no_visible_hints(page.locator("body").inner_text())
        if (state_dir / "result.json").exists():
            raise AssertionError("failed attempt should not leave final result.json")
        page.screenshot(path=str(out_dir / "cursor-lens-fail-refresh.png"), full_page=True)

        ground_truth = read_json(state_dir / "ground_truth.json")
        expected = ground_truth.get("expected_click") or {}
        x = float(expected["x"])
        y = float(expected["y"])
        click_canvas_point(page, x, y)
        page.locator("#submit-lens-click").click()
        expect(page.locator(".readout")).to_have_text("PASS")
        assert_no_visible_hints(page.locator("body").inner_text())
        page.screenshot(path=str(out_dir / "cursor-lens-pass.png"), full_page=True)
        result = read_json(state_dir / "result.json")
        if not (result.get("server_grade") or {}).get("passed"):
            raise AssertionError(f"server did not mark solved result as passed: {result!r}")
        browser.close()

    print(json.dumps({
        "ok": True,
        "initial": str(out_dir / "cursor-lens-initial.png"),
        "target_scan": str(out_dir / "cursor-lens-target-scan.png"),
        "fail": str(out_dir / "cursor-lens-fail-refresh.png"),
        "pass": str(out_dir / "cursor-lens-pass.png"),
        "nonblank_ratio": ratio,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
