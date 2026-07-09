"""Offline unit tests for verify_snippet_placeholders_live."""

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
TODAY = "2026-05-17"

GOOD_SNIPPETS = [
    {"name": "ISO Date", "keyword": "!iso", "text": '{date format="YYYY-MM-DD"}'},
    {"name": "Signature", "keyword": "!sig", "text": "Best,\n{cursor}\nClaude"},
    {"name": "Review",   "keyword": "!rev", "text": "Reviewing: {clipboard}"},
]

GOOD_EXP = f"{TODAY}\nBest,\n\nClaude\nReviewing: PR #42\n"


def _result(**overrides):
    base = {
        "task_start": NOW,
        "today_iso": TODAY,
        "exp_file_exists": True,
        "exp_file_is_new": True,
        "exp_file_size_bytes": len(GOOD_EXP),
        "exp_content": GOOD_EXP,
        "snip_file_exists": True,
        "snip_file_is_new": True,
        "snip_file_size_bytes": 200,
        "snip_valid_json": True,
        "snippets": list(GOOD_SNIPPETS),
    }
    base.update(overrides)
    return base


def test_missing_result():
    r = mod.verify_snippet_placeholders_live([], _make_env_missing(), {})
    assert r["passed"] is False and r["score"] == 0
    print("PASS test_missing_result")


def test_nothing_done():
    r = mod.verify_snippet_placeholders_live([], _make_env(_result(
        exp_file_exists=False, exp_file_is_new=False, exp_content="",
        snip_file_exists=False, snip_file_is_new=False, snip_valid_json=False, snippets=[]
    )), {})
    assert r["score"] == 0
    print(f"PASS test_nothing_done (score={r['score']})")


def test_only_snippets_no_expansion():
    """Agent stored the snippets but didn't actually expand them in TextEdit."""
    r = mod.verify_snippet_placeholders_live([], _make_env(_result(
        exp_file_exists=False, exp_file_is_new=False, exp_content=""
    )), {})
    # C1=15, C2=10, C3=10, C4=10, C5-C8=0 -> 45
    assert r["score"] == 45, f"Expected 45, got {r['score']}"
    assert r["passed"] is False  # 45 < 70
    print(f"PASS test_only_snippets_no_expansion (score={r['score']})")


def test_expansion_no_snippets_export():
    """Agent did the expansions in TextEdit but didn't export snippets."""
    r = mod.verify_snippet_placeholders_live([], _make_env(_result(
        snip_file_exists=False, snip_file_is_new=False, snip_valid_json=False, snippets=[]
    )), {})
    # C1=0, C2=0, C3=0, C4=0, C5=15, C6=15, C7=10, C8=15 -> 55
    assert r["score"] == 55, f"Expected 55, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_expansion_no_snippets_export (score={r['score']})")


def test_iso_missing_placeholder():
    snippets = list(GOOD_SNIPPETS)
    snippets[0] = {"name": "Iso", "keyword": "!iso", "text": "2026-05-17"}  # hardcoded, no placeholder
    r = mod.verify_snippet_placeholders_live([], _make_env(_result(snippets=snippets)), {})
    # C2 fails: 100 - 10 = 90
    assert r["score"] == 90, f"Expected 90, got {r['score']}"
    assert r["passed"] is True
    print(f"PASS test_iso_missing_placeholder (score={r['score']})")


def test_rev_clipboard_not_substituted():
    """!rev snippet has the placeholder but expansion file shows literal '{clipboard}' (didn't actually substitute)."""
    r = mod.verify_snippet_placeholders_live([], _make_env(_result(
        exp_content=f"{TODAY}\nBest,\n\nClaude\nReviewing: {{clipboard}}\n"
    )), {})
    # C8 fails (no 'PR #42'): 100 - 15 = 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    print(f"PASS test_rev_clipboard_not_substituted (score={r['score']})")


def test_sig_didnt_expand():
    """Only iso and rev expanded; sig was skipped."""
    r = mod.verify_snippet_placeholders_live([], _make_env(_result(
        exp_content=f"{TODAY}\nReviewing: PR #42\n"
    )), {})
    # C7 fails: 100 - 10 = 90
    assert r["score"] == 90, f"Expected 90, got {r['score']}"
    print(f"PASS test_sig_didnt_expand (score={r['score']})")


def test_all_correct():
    r = mod.verify_snippet_placeholders_live([], _make_env(_result()), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_date_drift_accepted():
    """If date ticked over by midnight, any ISO date in the file still counts."""
    r = mod.verify_snippet_placeholders_live([], _make_env(_result(
        exp_content="2026-05-18\nBest,\n\nClaude\nReviewing: PR #42\n",
        today_iso="2026-05-17"  # set day -- agent expanded next day
    )), {})
    # C6 falls back to any ISO date match -> still passes
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_date_drift_accepted (score={r['score']})")


def test_no_iso_date_at_all():
    r = mod.verify_snippet_placeholders_live([], _make_env(_result(
        exp_content="Best,\n\nClaude\nReviewing: PR #42\n"
    )), {})
    # C6 fails: 100 - 15 = 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    print(f"PASS test_no_iso_date_at_all (score={r['score']})")


if __name__ == "__main__":
    test_missing_result()
    test_nothing_done()
    test_only_snippets_no_expansion()
    test_expansion_no_snippets_export()
    test_iso_missing_placeholder()
    test_rev_clipboard_not_substituted()
    test_sig_didnt_expand()
    test_all_correct()
    test_date_drift_accepted()
    test_no_iso_date_at_all()
    print("\nAll Task 5 offline tests passed.")
