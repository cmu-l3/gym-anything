"""Offline unit tests for verify_calendar_visibility_revert."""

import importlib.util
import json
import os

_spec = importlib.util.spec_from_file_location(
    "verifier",
    os.path.join(os.path.dirname(__file__), "verifier.py"),
)
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)


def _make_env(result_data):
    def copy_from_env(src, dst):
        with open(dst, "w") as f:
            json.dump(result_data, f)
    return {"copy_from_env": copy_from_env}


def _make_env_missing():
    def copy_from_env(src, dst):
        raise FileNotFoundError(src)
    return {"copy_from_env": copy_from_env}


NOW = 1748300000

SEEDED_DRAFT = (
    "Hi Alex,\n\n"
    "Coffee next week sounds great. Here are the times that work for me next Thursday:\n\n\n"
    "Let me know which works best for you.\n\n"
    "Thanks,\n"
)

CORRECT_DRAFT = (
    "Hi Alex,\n\n"
    "Coffee next week sounds great. Here are the times that work for me next Thursday:\n\n"
    "- 1:00 PM - 2:00 PM\n"
    "- 3:00 PM - 3:30 PM\n"
    "- 4:30 PM - 5:00 PM\n\n"
    "Let me know which works best for you.\n\n"
    "Thanks,\n"
)


def _result(**overrides):
    base = {
        "task_start":          NOW,
        "next_thursday":       "2026-05-21",
        "next_thursday_human": "Thursday, May 21, 2026",
        "mail_draft_present":  True,
        "mail_draft_content":  CORRECT_DRAFT,
        "mail_draft_length":   len(CORRECT_DRAFT),
        "events_seen":         [],
        "event_count":         0,
        "raycast_wal_size_bytes":          5000,
        "raycast_wal_mtime":               NOW + 30,
        "raycast_wal_changed_after_setup": True,
    }
    base.update(overrides)
    return base


def test_missing_result_file():
    r = mod.verify_calendar_visibility_revert([], _make_env_missing(), {})
    assert r["passed"] is False and r["score"] == 0
    print("PASS test_missing_result_file")


def test_do_nothing_blank_draft():
    """Agent did nothing — draft is still the seeded template."""
    r = mod.verify_calendar_visibility_revert([], _make_env(_result(
        mail_draft_content=SEEDED_DRAFT,
        mail_draft_length=len(SEEDED_DRAFT),
        raycast_wal_changed_after_setup=False,
    )), {})
    # Seeded len is ~145 chars < 200 baseline → C1 fails
    # No time blocks, no traps → C2/C3 fail, C4 passes (no traps)
    # WAL didn't change → C5 fails
    # Score: 0+0+0+15+0 = 15
    assert r["score"] == 15, f"Expected 15, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_do_nothing_blank_draft (score={r['score']})")


def test_all_correct():
    r = mod.verify_calendar_visibility_revert([], _make_env(_result()), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_included_work_calendar():
    """Agent included Work calendar → first block 1-2pm is missing AND draft mentions 'Team retro'."""
    bad_draft = (
        SEEDED_DRAFT.rstrip()
        + "\n\n- 3:00 PM - 3:30 PM (between Team retro and pickup)"
        + "\n- 4:30 PM - 5:00 PM\n\nThanks,\n"
    )
    r = mod.verify_calendar_visibility_revert([], _make_env(_result(
        mail_draft_content=bad_draft, mail_draft_length=len(bad_draft),
    )), {})
    # C1 passes (length grew), C2 fails (no 1-2pm), C3 passes (4:30-5pm),
    # C4 fails (Team retro trap), C5 passes (WAL changed)
    # Score: 20+0+25+0+10 = 55
    assert r["score"] == 55, f"Expected 55, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_included_work_calendar (score={r['score']})")


def test_included_yoga_tentative():
    """Agent forgot to exclude tentative event → mentions yoga."""
    bad_draft = CORRECT_DRAFT.rstrip() + "\n\n(Note: I have yoga at 5 PM so before that.)\n"
    r = mod.verify_calendar_visibility_revert([], _make_env(_result(
        mail_draft_content=bad_draft, mail_draft_length=len(bad_draft),
    )), {})
    # C1 passes, C2 passes, C3 passes, C4 fails (yoga trap), C5 passes
    # Score: 20+30+25+0+10 = 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    assert r["passed"] is True  # still passes
    print(f"PASS test_included_yoga_tentative (score={r['score']})")


def test_first_block_only():
    """Agent reported only the 1-2pm block."""
    draft = (
        SEEDED_DRAFT.rstrip()
        + "\n\n- 1:00 PM - 2:00 PM\n\nThanks,\n"
    )
    # Add enough text to clear the baseline-length gate
    draft = draft + "\n\n" + "Looking forward to it!\n\n" * 4
    r = mod.verify_calendar_visibility_revert([], _make_env(_result(
        mail_draft_content=draft, mail_draft_length=len(draft),
    )), {})
    # C1 passes, C2 passes, C3 fails, C4 passes, C5 passes
    # Score: 20+30+0+15+10 = 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    assert r["passed"] is True
    print(f"PASS test_first_block_only (score={r['score']})")


def test_no_wal_change():
    """Agent used macOS Calendar.app directly without touching Raycast."""
    r = mod.verify_calendar_visibility_revert([], _make_env(_result(
        raycast_wal_changed_after_setup=False,
    )), {})
    # All else correct, just C5 fails: 100 - 10 = 90
    assert r["score"] == 90, f"Expected 90, got {r['score']}"
    assert r["passed"] is True
    print(f"PASS test_no_wal_change (score={r['score']})")


def test_24h_format_accepted():
    """Agent used 24-hour time format."""
    draft_24 = (
        SEEDED_DRAFT.rstrip()
        + "\n\n- 13:00 - 14:00\n- 15:00 - 15:30\n- 16:30 - 17:00\n\nThanks,\n"
    )
    r = mod.verify_calendar_visibility_revert([], _make_env(_result(
        mail_draft_content=draft_24, mail_draft_length=len(draft_24),
    )), {})
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_24h_format_accepted (score={r['score']})")


def test_wrong_window_outside_1_to_6():
    """Agent reported availability outside the 1-6 PM window."""
    bad_draft = (
        SEEDED_DRAFT.rstrip()
        + "\n\n- 8:00 PM - 10:00 PM (after dinner)\n- 6:30 AM - 7:30 AM (morning)\n\nThanks,\n"
    )
    r = mod.verify_calendar_visibility_revert([], _make_env(_result(
        mail_draft_content=bad_draft, mail_draft_length=len(bad_draft),
    )), {})
    # C1 passes (length grew), C2 fails, C3 fails, C4 passes (no traps), C5 passes
    # Score: 20+0+0+15+10 = 45
    assert r["score"] == 45, f"Expected 45, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_wrong_window_outside_1_to_6 (score={r['score']})")


if __name__ == "__main__":
    test_missing_result_file()
    test_do_nothing_blank_draft()
    test_all_correct()
    test_included_work_calendar()
    test_included_yoga_tentative()
    test_first_block_only()
    test_no_wal_change()
    test_24h_format_accepted()
    test_wrong_window_outside_1_to_6()
    print("\nAll #5 offline tests passed.")
