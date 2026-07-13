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
    parser = argparse.ArgumentParser(description="Smoke-test the Weird CAPTCHA board-game UI.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8795")
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--cheat-password", help="also verify dev-only move reveal")
    return parser.parse_args()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def assert_no_visible_hints(text: str) -> None:
    lowered = text.lower()
    leaked = [snippet for snippet in FORBIDDEN_VISIBLE_SNIPPETS if snippet in lowered]
    if leaked:
        raise AssertionError(f"visible UI leaks forbidden text: {leaked}; visible={text!r}")


def challenge_id(page) -> str:
    value = page.locator(".board-captcha").get_attribute("data-challenge-id")
    if not value:
        raise AssertionError("missing challenge id")
    return value


def empty_cell_ids(page) -> list[str]:
    return page.locator(".board-cell:not([disabled])").evaluate_all(
        "(cells) => cells.map((cell) => cell.dataset.cellId)",
    )


def click_cell(page, cell_id: str) -> None:
    page.locator(f'.board-cell[data-cell-id="{cell_id}"]').click()


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
        expect(page.locator(".board-cell")).to_have_count(9)
        assert_no_visible_hints(page.locator("body").inner_text())
        initial_challenge = challenge_id(page)
        page.screenshot(path=str(out_dir / "board-game-initial.png"), full_page=True)

        page.reload()
        page.wait_for_load_state("networkidle")
        expect(page.locator(".board-cell")).to_have_count(9)
        refreshed_challenge = challenge_id(page)
        if refreshed_challenge == initial_challenge:
            raise AssertionError("browser refresh did not generate a fresh board-game challenge")
        assert_no_visible_hints(page.locator("body").inner_text())
        page.screenshot(path=str(out_dir / "board-game-refresh.png"), full_page=True)

        if args.cheat_password:
            cheat_page = browser.new_page(viewport={"width": 1360, "height": 980}, device_scale_factor=1)
            cheat_page.goto(f"{args.base_url.rstrip('/')}/?cheat=1")
            cheat_page.wait_for_load_state("networkidle")
            expect(cheat_page.locator(".board-cell")).to_have_count(9)
            expect(cheat_page.locator(".cheat-panel")).to_be_visible()
            cheat_page.locator("#cheat-password").fill(args.cheat_password)
            cheat_page.locator(".cheat-submit").click()
            expect(cheat_page.locator("#cheat-output")).to_contain_text("Move:")
            expect(cheat_page.locator('.board-cell[data-cheat-answer="true"]')).to_have_count(1)
            cheat_page.screenshot(path=str(out_dir / "board-game-cheat.png"), full_page=True)
            cheat_page.close()

        ground_truth = read_json(state_dir / "ground_truth.json")
        solution_id = str(ground_truth["solution_cell_id"])
        wrong_ids = [cell_id for cell_id in empty_cell_ids(page) if cell_id != solution_id]
        if not wrong_ids:
            raise AssertionError("no wrong empty cell available for fail test")
        click_cell(page, wrong_ids[0])
        page.locator("#submit-board-move").click()
        expect(page.locator(".readout")).to_have_text("FAIL")
        fail_challenge = challenge_id(page)
        if fail_challenge == refreshed_challenge:
            raise AssertionError("failed board-game attempt did not load a fresh challenge")
        assert_no_visible_hints(page.locator("body").inner_text())
        if (state_dir / "result.json").exists():
            raise AssertionError("failed attempt should not leave final result.json")
        page.screenshot(path=str(out_dir / "board-game-fail-refresh.png"), full_page=True)

        ground_truth = read_json(state_dir / "ground_truth.json")
        solution_id = str(ground_truth["solution_cell_id"])
        click_cell(page, solution_id)
        page.screenshot(path=str(out_dir / "board-game-solution-selected.png"), full_page=True)
        page.locator("#submit-board-move").click()
        expect(page.locator(".readout")).to_have_text("PASS")
        assert_no_visible_hints(page.locator("body").inner_text())
        page.screenshot(path=str(out_dir / "board-game-pass.png"), full_page=True)
        result = read_json(state_dir / "result.json")
        if not (result.get("server_grade") or {}).get("passed"):
            raise AssertionError(f"server did not mark solved result as passed: {result!r}")
        browser.close()

    print(json.dumps({
        "ok": True,
        "initial": str(out_dir / "board-game-initial.png"),
        "selected": str(out_dir / "board-game-solution-selected.png"),
        "pass": str(out_dir / "board-game-pass.png"),
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
