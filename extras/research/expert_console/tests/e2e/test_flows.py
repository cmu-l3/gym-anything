"""End-to-end flow tests for the expert console.

These tests drive the real Next.js production build through the real
FastAPI backend. They:

- exercise the picker -> inspection flow
- exercise the chat composer end-to-end (memory-only submission, since
  full dispatch needs a real claude binary)
- exercise the memory diff panel
- capture screenshots into `tests/e2e/screenshots/` for visual review
"""

from __future__ import annotations

from pathlib import Path

import pytest

SCREENSHOTS_DIR = Path(__file__).resolve().parent / "screenshots"
SCREENSHOTS_DIR.mkdir(parents=True, exist_ok=True)


def _shot(page, name: str) -> None:
    page.screenshot(path=str(SCREENSHOTS_DIR / f"{name}.png"))


def _open_picker(page) -> None:
    # Robust to either the initial "software: all" chip or a re-opened
    # picker after a previous selection that left a chip like "moodle_env".
    chip = page.get_by_text("software: all").first
    if chip.count() == 0:
        chip = page.get_by_role("button").filter(has_text="moodle_env").first
    chip.click()
    page.wait_for_selector("input[placeholder^='Search software']", timeout=10_000)


def _select_moodle(page) -> None:
    _open_picker(page)
    page.locator("input[placeholder^='Search software']").fill("moodle")
    page.wait_for_selector("[role='listbox'] button:has-text('moodle_env')")
    page.locator("[role='listbox'] button:has-text('moodle_env')").first.click(
        force=True
    )
    page.keyboard.press("Escape")
    page.wait_for_load_state("networkidle")


def test_initial_render(page) -> None:
    page.wait_for_selector("text=Expert Console")
    assert page.get_by_role("heading", name="Expert Console").is_visible()
    _shot(page, "01_initial")


def test_picker_opens_and_lists_software(page) -> None:
    _open_picker(page)
    _shot(page, "02a_picker_open")
    page.locator("input[placeholder^='Search software']").fill("moodle")
    page.wait_for_timeout(400)
    _shot(page, "02b_picker_filtered_intermediate")
    page.wait_for_selector("[role='listbox'] button:has-text('moodle_env')")
    _shot(page, "02_picker_filtered")


def test_pick_env_renders_inspection(page) -> None:
    _select_moodle(page)
    page.wait_for_selector("text=ENVIRONMENT SPEC")
    assert page.locator("text=moodle_env@").first.is_visible()
    assert page.locator("text=SCRIPTS").first.is_visible()
    _shot(page, "03_env_selected")


def test_memory_panel_shows_diff(page) -> None:
    page.get_by_role("button", name="Inspect Memory").click()
    page.wait_for_selector("text=Pending Changes")
    # General memory listing is always rendered.
    assert page.locator("text=General Memory").is_visible()
    _shot(page, "04_memory_panel")


def test_memory_panel_env_section_appears_after_pick(page) -> None:
    _select_moodle(page)
    page.get_by_role("button", name="Inspect Memory").click()
    page.wait_for_selector("text=Pending Changes")
    page.wait_for_selector("text=Environment · moodle_env", timeout=10_000)
    _shot(page, "04b_memory_env_section")


def test_vnc_right_slot_shows_start_affordance(page) -> None:
    _select_moodle(page)
    # VNC is the persistent right slot when an env is picked.
    page.wait_for_selector("text=VNC is not running")
    assert page.locator("button", has_text="Start").is_visible()
    _shot(page, "05_vnc_right_slot")


def test_submit_memory_only_feedback(page, backend_url: str) -> None:
    msg = "E2E test: prefer real datasets globally; demo data is FAIL."
    page.locator("textarea").fill(msg)
    page.get_by_role("button", name="Send").click()
    # Backend persists synchronously; verify through the API.
    import urllib.request
    import json
    import time

    deadline = time.monotonic() + 8
    sessions: list[dict] = []
    while time.monotonic() < deadline:
        with urllib.request.urlopen(f"{backend_url}/api/sessions") as r:
            sessions = json.load(r)
        if any("general feedback" in s["title"] for s in sessions):
            break
        time.sleep(0.25)
    assert any("general feedback" in s["title"] for s in sessions), sessions
    _shot(page, "06_after_memory_only_submit")


def test_inspection_history_renders_after_submission(page) -> None:
    _select_moodle(page)
    msg = "another e2e note about moodle"
    page.locator("textarea").fill(msg)
    page.get_by_role("button", name="Send").click()
    page.wait_for_timeout(800)
    page.get_by_role("tab", name="Interaction History").click()
    page.wait_for_selector(f"text={msg[:24]}", timeout=10_000)
    _shot(page, "07_interaction_history")
