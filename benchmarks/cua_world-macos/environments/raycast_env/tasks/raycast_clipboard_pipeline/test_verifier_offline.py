"""Offline unit tests for verify_clipboard_pipeline."""

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


def _result(**overrides):
    base = {
        "task_start": NOW,
        "clip_file_exists": True,
        "clip_file_is_new": True,
        "clip_file_size_bytes": 20,
        "clip_content": "alpha\nbeta\ngamma\n",
        "snip_file_exists": True,
        "snip_file_is_new": True,
        "snip_file_size_bytes": 100,
        "snip_valid_json": True,
        "snippets": [{"name": "Beta", "keyword": "!greek", "text": "beta"}],
    }
    base.update(overrides)
    return base


def test_missing_result():
    r = mod.verify_clipboard_pipeline([], _make_env_missing(), {})
    assert r["passed"] is False and r["score"] == 0
    print("PASS test_missing_result")


def test_nothing_done():
    r = mod.verify_clipboard_pipeline([], _make_env(_result(
        clip_file_exists=False, clip_file_is_new=False, clip_content="",
        snip_file_exists=False, snip_file_is_new=False, snip_valid_json=False, snippets=[]
    )), {})
    assert r["score"] == 0
    print(f"PASS test_nothing_done (score={r['score']})")


def test_only_clipboard_done():
    r = mod.verify_clipboard_pipeline([], _make_env(_result(
        snip_file_exists=False, snip_file_is_new=False, snip_valid_json=False, snippets=[]
    )), {})
    # C1=15, C2=12, C3=12, C4=12, C5=9, C6=0, C7=0 -> 60
    assert r["score"] == 60, f"Expected 60, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_only_clipboard_done (score={r['score']})")


def test_only_snippets_done():
    r = mod.verify_clipboard_pipeline([], _make_env(_result(
        clip_file_exists=False, clip_file_is_new=False, clip_content=""
    )), {})
    # C1-C5 fail (0), C6=15, C7=25 -> 40
    assert r["score"] == 40, f"Expected 40, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_only_snippets_done (score={r['score']})")


def test_wrong_order():
    r = mod.verify_clipboard_pipeline([], _make_env(_result(
        clip_content="gamma\nbeta\nalpha\n"
    )), {})
    # C1=15, C2=12, C3=12, C4=12, C5=0 (wrong order), C6=15, C7=25 -> 91
    assert r["score"] == 91, f"Expected 91, got {r['score']}"
    assert r["passed"] is True  # still passes
    print(f"PASS test_wrong_order (score={r['score']})")


def test_missing_gamma():
    r = mod.verify_clipboard_pipeline([], _make_env(_result(
        clip_content="alpha\nbeta\n"
    )), {})
    # C1=15, C2=12, C3=12, C4=0, C5=0 (gamma missing -> order check fails), C6=15, C7=25 -> 79
    assert r["score"] == 79, f"Expected 79, got {r['score']}"
    assert r["passed"] is True  # still passes
    print(f"PASS test_missing_gamma (score={r['score']})")


def test_snippet_wrong_keyword():
    r = mod.verify_clipboard_pipeline([], _make_env(_result(
        snippets=[{"name": "Beta", "keyword": "!b", "text": "beta"}]
    )), {})
    # C1=15, C2=12, C3=12, C4=12, C5=9, C6=15, C7=0 (wrong keyword) -> 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    assert r["passed"] is True
    print(f"PASS test_snippet_wrong_keyword (score={r['score']})")


def test_snippet_wrong_text():
    r = mod.verify_clipboard_pipeline([], _make_env(_result(
        snippets=[{"name": "Greek", "keyword": "!greek", "text": "beta is the 2nd greek letter"}]
    )), {})
    # C7 fails because text != 'beta'
    # C1=15, C2=12, C3=12, C4=12, C5=9, C6=15, C7=0 -> 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    print(f"PASS test_snippet_wrong_text (score={r['score']})")


def test_all_correct():
    r = mod.verify_clipboard_pipeline([], _make_env(_result()), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_snippet_with_alt_field_names():
    """Snippet uses 'shortcut' instead of 'keyword' and 'content' instead of 'text'."""
    # The export script normalizes these to keyword/text, so by the time the verifier
    # sees the data, it should be normalized. Test the normalized form.
    r = mod.verify_clipboard_pipeline([], _make_env(_result(
        snippets=[{"name": "Beta", "keyword": "!greek", "text": "beta"}]
    )), {})
    assert r["score"] == 100
    print(f"PASS test_snippet_with_alt_field_names (score={r['score']})")


if __name__ == "__main__":
    test_missing_result()
    test_nothing_done()
    test_only_clipboard_done()
    test_only_snippets_done()
    test_wrong_order()
    test_missing_gamma()
    test_snippet_wrong_keyword()
    test_snippet_wrong_text()
    test_all_correct()
    test_snippet_with_alt_field_names()
    print("\nAll Task 4 offline tests passed.")
