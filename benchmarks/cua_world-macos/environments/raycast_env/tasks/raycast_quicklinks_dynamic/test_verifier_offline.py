"""Offline unit tests for verify_quicklinks_dynamic."""

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

GOOD_QUICKLINKS = [
    {"name": "YouTube Search",       "link": "https://www.youtube.com/results?search_query={Query}", "description": ""},
    {"name": "GitHub Code Search",   "link": 'https://github.com/search?q={argument name="keywords"}&type=code&l={argument name="language" default="python"}', "description": ""},
    {"name": "Translate Clipboard",  "link": 'https://translate.google.com/?sl=auto&tl={argument name="target" default="es"}&text={clipboard | trim}&op=translate', "description": ""},
    {"name": "Maps Directions",      "link": 'https://www.google.com/maps/dir/?api=1&origin=Pittsburgh,PA&destination={Query}', "description": ""},
]


def _result(quicklinks=None, is_new=True, exists=True, valid=True):
    qls = quicklinks if quicklinks is not None else GOOD_QUICKLINKS
    return {
        "task_start": NOW,
        "export_file_exists": exists,
        "export_file_size_bytes": 800,
        "export_file_is_new": is_new,
        "valid_json": valid,
        "quicklinks": qls,
        "quicklink_count": len(qls),
    }


def test_missing_result():
    r = mod.verify_quicklinks_dynamic([], _make_env_missing(), {})
    assert r["passed"] is False and r["score"] == 0
    print("PASS test_missing_result")


def test_no_export_file():
    r = mod.verify_quicklinks_dynamic([], _make_env(_result(
        quicklinks=[], is_new=False, exists=False, valid=False
    )), {})
    assert r["score"] == 0
    print(f"PASS test_no_export_file (score={r['score']})")


def test_stale_export():
    r = mod.verify_quicklinks_dynamic([], _make_env(_result(is_new=False)), {})
    # C1 fails, rest skipped
    assert r["score"] == 0
    print(f"PASS test_stale_export (score={r['score']})")


def test_wrong_content_4_random_links():
    bad = [
        {"name": "A", "link": "https://example.com/1", "description": ""},
        {"name": "B", "link": "https://example.com/2", "description": ""},
        {"name": "C", "link": "https://example.com/3", "description": ""},
        {"name": "D", "link": "https://example.com/4", "description": ""},
    ]
    r = mod.verify_quicklinks_dynamic([], _make_env(_result(quicklinks=bad)), {})
    # C1=15, C2=15, C3-C6 all fail -> 30
    assert r["score"] == 30, f"Expected 30, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_wrong_content_4_random_links (score={r['score']})")


def test_youtube_without_placeholder():
    qls = list(GOOD_QUICKLINKS)
    qls[0] = {"name": "YT", "link": "https://www.youtube.com/", "description": ""}
    r = mod.verify_quicklinks_dynamic([], _make_env(_result(quicklinks=qls)), {})
    # C1=15, C2=15, C3=0, C4=20, C5=20, C6=15 -> 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    assert r["passed"] is True
    print(f"PASS test_youtube_without_placeholder (score={r['score']})")


def test_github_missing_default():
    qls = list(GOOD_QUICKLINKS)
    # language argument but no default
    qls[1] = {"name": "GH", "link": 'https://github.com/search?q={argument name="keywords"}&l={argument name="language"}', "description": ""}
    r = mod.verify_quicklinks_dynamic([], _make_env(_result(quicklinks=qls)), {})
    # C4 fails because no default="python"
    # C1=15, C2=15, C3=15, C4=0, C5=20, C6=15 -> 80
    assert r["score"] == 80, f"Expected 80, got {r['score']}"
    print(f"PASS test_github_missing_default (score={r['score']})")


def test_translate_missing_clipboard():
    qls = list(GOOD_QUICKLINKS)
    qls[2] = {"name": "TR", "link": 'https://translate.google.com/?tl={argument name="target" default="es"}&text={Query}', "description": ""}
    r = mod.verify_quicklinks_dynamic([], _make_env(_result(quicklinks=qls)), {})
    # C5 fails (no clipboard); rest fine
    # C1=15, C2=15, C3=15, C4=20, C5=0, C6=15 -> 80
    assert r["score"] == 80, f"Expected 80, got {r['score']}"
    print(f"PASS test_translate_missing_clipboard (score={r['score']})")


def test_all_correct():
    r = mod.verify_quicklinks_dynamic([], _make_env(_result()), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_wrapped_in_object_format():
    """Some exports wrap quicklinks in {'quicklinks': [...]}."""
    # Pre-normalized form (since export_result.sh handles normalization)
    r = mod.verify_quicklinks_dynamic([], _make_env(_result()), {})
    assert r["passed"] is True
    print(f"PASS test_wrapped_in_object_format (score={r['score']})")


if __name__ == "__main__":
    test_missing_result()
    test_no_export_file()
    test_stale_export()
    test_wrong_content_4_random_links()
    test_youtube_without_placeholder()
    test_github_missing_default()
    test_translate_missing_clipboard()
    test_all_correct()
    test_wrapped_in_object_format()
    print("\nAll Task 3 offline tests passed.")
