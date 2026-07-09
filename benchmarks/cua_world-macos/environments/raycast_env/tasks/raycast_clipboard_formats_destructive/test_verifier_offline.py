"""Offline unit tests for verify_clipboard_formats_destructive."""

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

CORRECT_DRAFT = (
    "Hi team,\n\n"
    "Sharing the May 2026 newsletter draft below for review.\n\n"
    "[newsletter body — see attached PDF]\n\n"
    "Best,\n"
    "Margaret Lin\n"
    "Newsletter Coordinator\n"
    "Westside Community Center\n"
)

HTML_LEAKED_DRAFT = (
    "Hi team,\n\nSharing the May 2026 newsletter draft below for review.\n\n"
    "<html><body><p>Best,<br><b>Margaret Lin</b><br>"
    "Newsletter Coordinator<br>Westside Community Center</p></body></html>"
)


def _result(**overrides):
    base = {
        "task_start":         NOW,
        "final_clipboard":    "call mom after 6",
        "mail_draft_content": CORRECT_DRAFT,
        "mail_draft_length":  len(CORRECT_DRAFT),
        "inbox_path":         "/Users/lume/Desktop/Household Inbox",
        "inbox_exists":       True,
        "inbox_files": [
            {"name": "receipt.pdf",  "size_bytes": 12000, "mtime": NOW + 30, "is_new": True},
            {"name": "warranty.png", "size_bytes": 18000, "mtime": NOW + 30, "is_new": True},
        ],
        "inbox_file_count":   2,
        "raycast_wal_size_bytes":          50000,
        "raycast_wal_mtime":               NOW + 60,
        "raycast_wal_changed_after_setup": True,
    }
    base.update(overrides)
    return base


def test_missing_result_file():
    r = mod.verify_clipboard_formats_destructive([], _make_env_missing(), {})
    assert r["passed"] is False and r["score"] == 0
    print("PASS test_missing_result_file")


def test_do_nothing():
    """Agent did nothing — clipboard unchanged (still 'call mom after 6' from setup),
    but everything else is missing."""
    r = mod.verify_clipboard_formats_destructive([], _make_env(_result(
        mail_draft_content="Hi team,\n\nSharing the May 2026 newsletter draft below for review.\n\nBest,\n",
        mail_draft_length=80,
        inbox_files=[], inbox_file_count=0,
        raycast_wal_changed_after_setup=False,
    )), {})
    # C1 passes (clipboard still preserved by setup), C2/C3/C4 fail, C5 passes
    # (no HTML leak since no signature pasted), C6 fails
    # Score: 25+0+0+0+15+0 = 40
    assert r["score"] == 40, f"Expected 40, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_do_nothing (score={r['score']})")


def test_all_correct():
    r = mod.verify_clipboard_formats_destructive([], _make_env(_result()), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_forgot_to_pin_clipboard_lost():
    """Agent deleted last 15 min without pinning — clipboard cleared."""
    r = mod.verify_clipboard_formats_destructive([], _make_env(_result(
        final_clipboard="",
    )), {})
    # C1 fails (-25), rest pass: 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    print(f"PASS test_forgot_to_pin_clipboard_lost (score={r['score']})")


def test_pasted_rich_html_leaked():
    """Agent did default rich paste instead of Paste-as-Plain."""
    r = mod.verify_clipboard_formats_destructive([], _make_env(_result(
        mail_draft_content=HTML_LEAKED_DRAFT,
        mail_draft_length=len(HTML_LEAKED_DRAFT),
    )), {})
    # C1 passes, C2/C3 pass, C4 passes (Margaret Lin still present),
    # C5 fails (HTML fragments), C6 passes
    # Score: 25+15+15+15+0+15 = 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    print(f"PASS test_pasted_rich_html_leaked (score={r['score']})")


def test_grouped_paste_lost_one_file():
    """Agent split the grouped paste — only one file landed in inbox."""
    r = mod.verify_clipboard_formats_destructive([], _make_env(_result(
        inbox_files=[
            {"name": "receipt.pdf", "size_bytes": 12000, "mtime": NOW + 30, "is_new": True},
        ],
        inbox_file_count=1,
    )), {})
    # C3 fails (-15), rest pass: 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    print(f"PASS test_grouped_paste_lost_one_file (score={r['score']})")


def test_wrong_clipboard_at_end():
    """Agent ended with wrong clipboard value (forgot to pin, deleted OTP, OTP became last)."""
    r = mod.verify_clipboard_formats_destructive([], _make_env(_result(
        final_clipboard="123456",
    )), {})
    # C1 fails: 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    print(f"PASS test_wrong_clipboard_at_end (score={r['score']})")


def test_signature_not_pasted():
    """Agent didn't paste signature into Mail at all."""
    r = mod.verify_clipboard_formats_destructive([], _make_env(_result(
        mail_draft_content="Hi team,\n\nNo signature here.\n",
        mail_draft_length=30,
    )), {})
    # C4 fails: 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    print(f"PASS test_signature_not_pasted (score={r['score']})")


def test_no_raycast_use():
    """Agent did everything via Finder + Mail, bypassed Raycast entirely."""
    r = mod.verify_clipboard_formats_destructive([], _make_env(_result(
        raycast_wal_changed_after_setup=False,
    )), {})
    # C6 fails: 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    print(f"PASS test_no_raycast_use (score={r['score']})")


def test_empty_inbox():
    """Inbox is empty (agent didn't paste grouped files)."""
    r = mod.verify_clipboard_formats_destructive([], _make_env(_result(
        inbox_files=[], inbox_file_count=0,
    )), {})
    # C2 and C3 fail (-30): 70
    assert r["score"] == 70, f"Expected 70, got {r['score']}"
    assert r["passed"] is True  # exactly at threshold
    print(f"PASS test_empty_inbox (score={r['score']})")


if __name__ == "__main__":
    test_missing_result_file()
    test_do_nothing()
    test_all_correct()
    test_forgot_to_pin_clipboard_lost()
    test_pasted_rich_html_leaked()
    test_grouped_paste_lost_one_file()
    test_wrong_clipboard_at_end()
    test_signature_not_pasted()
    test_no_raycast_use()
    test_empty_inbox()
    print("\nAll #4 offline tests passed.")
