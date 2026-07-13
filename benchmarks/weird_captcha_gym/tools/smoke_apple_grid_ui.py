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
    parser = argparse.ArgumentParser(description="Smoke-test the Weird CAPTCHA apple grid UI.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8793")
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--cheat-password", help="also verify dev-only answer reveal")
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
          const canvases = [...document.querySelectorAll("canvas")];
          let changed = 0;
          let sampled = 0;
          for (const canvas of canvases) {
            const ctx = canvas.getContext("2d");
            const img = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
            for (let i = 0; i < img.length; i += 64) {
              const r = img[i], g = img[i + 1], b = img[i + 2], a = img[i + 3];
              if (a > 0 && (r < 245 || g < 245 || b < 245)) changed += 1;
              sampled += 1;
            }
          }
          return sampled ? changed / sampled : 0;
        }
        """,
    ))


def click_tile(page, tile_id: str) -> None:
    page.locator(f'[data-tile-id="{tile_id}"]').click()


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
        expect(page.locator(".apple-tile")).to_have_count(9)
        initial_text = page.locator("body").inner_text()
        assert_no_visible_hints(initial_text)
        ratio = canvas_nonblank_ratio(page)
        if ratio < 0.08:
            raise AssertionError(f"canvas render appears blank; nonblank ratio={ratio:.4f}")
        initial_tile_ids = page.locator(".apple-tile").evaluate_all(
            "(tiles) => tiles.map((tile) => tile.dataset.tileId)",
        )
        page.screenshot(path=str(out_dir / "apple-grid-initial.png"), full_page=True)

        page.reload()
        page.wait_for_load_state("networkidle")
        expect(page.locator(".apple-tile")).to_have_count(9)
        refreshed_tile_ids = page.locator(".apple-tile").evaluate_all(
            "(tiles) => tiles.map((tile) => tile.dataset.tileId)",
        )
        if refreshed_tile_ids == initial_tile_ids:
            raise AssertionError("browser refresh did not generate a fresh challenge")
        assert_no_visible_hints(page.locator("body").inner_text())
        page.screenshot(path=str(out_dir / "apple-grid-refresh.png"), full_page=True)

        if args.cheat_password:
            cheat_page = browser.new_page(viewport={"width": 1360, "height": 980}, device_scale_factor=1)
            cheat_page.goto(f"{args.base_url.rstrip('/')}/?cheat=1")
            cheat_page.wait_for_load_state("networkidle")
            expect(cheat_page.locator(".apple-tile")).to_have_count(9)
            expect(cheat_page.locator(".cheat-panel")).to_be_visible()
            cheat_page.locator("#cheat-password").fill(args.cheat_password)
            cheat_page.locator(".cheat-submit").click()
            ground_truth = read_json(state_dir / "ground_truth.json")
            expected_ids = ground_truth.get("expected_tile_ids")
            if not isinstance(expected_ids, list):
                raise AssertionError(f"unexpected expected tile set: {expected_ids!r}")
            expect(cheat_page.locator('.apple-tile[data-cheat-answer="true"]')).to_have_count(len(expected_ids))
            cheat_page.screenshot(path=str(out_dir / "apple-grid-cheat.png"), full_page=True)
            cheat_page.close()

        first_id = page.locator(".apple-tile").first.get_attribute("data-tile-id")
        if not first_id:
            raise AssertionError("first tile has no tile id")
        click_tile(page, first_id)
        page.locator("#submit-apple-grid").click()
        expect(page.locator(".readout")).to_have_text("FAIL")
        page.wait_for_timeout(150)
        fail_text = page.locator("body").inner_text()
        assert_no_visible_hints(fail_text)
        refreshed_first_id = page.locator(".apple-tile").first.get_attribute("data-tile-id")
        if refreshed_first_id == first_id:
            raise AssertionError("failed attempt did not load a fresh generated grid")
        if (state_dir / "result.json").exists():
            raise AssertionError("failed attempt should not leave final result.json")
        page.screenshot(path=str(out_dir / "apple-grid-fail-refresh.png"), full_page=True)

        ground_truth = read_json(state_dir / "ground_truth.json")
        expected_ids = ground_truth.get("expected_tile_ids")
        if not isinstance(expected_ids, list) or not 3 <= len(expected_ids) <= 5:
            raise AssertionError(f"unexpected expected tile set: {expected_ids!r}")
        for tile_id in expected_ids:
            click_tile(page, str(tile_id))
        page.locator("#submit-apple-grid").click()
        expect(page.locator(".readout")).to_have_text("PASS")
        pass_text = page.locator("body").inner_text()
        assert_no_visible_hints(pass_text)
        page.screenshot(path=str(out_dir / "apple-grid-pass.png"), full_page=True)
        result = read_json(state_dir / "result.json")
        if not (result.get("server_grade") or {}).get("passed"):
            raise AssertionError(f"server did not mark solved result as passed: {result!r}")
        browser.close()

    print(json.dumps({
        "ok": True,
        "initial": str(out_dir / "apple-grid-initial.png"),
        "fail": str(out_dir / "apple-grid-fail-refresh.png"),
        "pass": str(out_dir / "apple-grid-pass.png"),
        "nonblank_ratio": ratio,
        "expected_count": len(expected_ids),
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
