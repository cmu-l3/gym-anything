"""Offline unit tests for verify_quicklink_tab_reuse."""

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

GOOD_QUICKLINK = {
    "name": "Recipe Search",
    "link": 'https://duckduckgo.com/?q={argument name="ingredient"}+recipe+{argument name="servings"}+servings',
    "description": "",
}


def _result(**overrides):
    base = {
        "task_start":         NOW,
        "safari_tab_urls":    ["https://duckduckgo.com/?q=tofu+recipe+4+servings"],
        "safari_tab_count":   1,
        "export_file_exists": True,
        "export_file_is_new": True,
        "quicklinks":         [GOOD_QUICKLINK],
        "quicklink_count":    1,
        "raycast_wal_mtime":  NOW + 30,
        "raycast_wal_changed_after_setup": True,
    }
    base.update(overrides)
    return base


def test_missing_result_file():
    r = mod.verify_quicklink_tab_reuse([], _make_env_missing(), {})
    assert r["passed"] is False and r["score"] == 0
    print("PASS test_missing_result_file")


def test_all_correct():
    r = mod.verify_quicklink_tab_reuse([], _make_env(_result()), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_do_nothing():
    r = mod.verify_quicklink_tab_reuse([], _make_env(_result(
        safari_tab_urls=["https://duckduckgo.com/?q=salmon+recipe+2+servings"],
        export_file_exists=False, export_file_is_new=False,
        quicklinks=[], quicklink_count=0,
        raycast_wal_changed_after_setup=False,
    )), {})
    # C1=0, C2=0, C3=30 (single tab kept, but it's salmon), C4=0, C5=0 -> 30
    assert r["score"] == 30, f"Expected 30, got {r['score']}"
    print(f"PASS test_do_nothing (score={r['score']})")


def test_duplicate_tab_created():
    """Agent invoked quicklink but it opened a NEW tab instead of reusing."""
    r = mod.verify_quicklink_tab_reuse([], _make_env(_result(
        safari_tab_urls=[
            "https://duckduckgo.com/?q=salmon+recipe+2+servings",
            "https://duckduckgo.com/?q=tofu+recipe+4+servings",
        ],
        safari_tab_count=2,
    )), {})
    # C3 fails: 100-30 = 70
    assert r["score"] == 70, f"Expected 70, got {r['score']}"
    assert r["passed"] is True  # borderline pass
    print(f"PASS test_duplicate_tab_created (score={r['score']})")


def test_literal_braces_not_dynamic():
    """Agent created quicklink with literal {ingredient} not Raycast {argument name=...}."""
    bad_link = "https://duckduckgo.com/?q={ingredient}+recipe+{servings}+servings"
    r = mod.verify_quicklink_tab_reuse([], _make_env(_result(
        quicklinks=[{"name": "Recipe Search", "link": bad_link, "description": ""}],
    )), {})
    # C2 fails: 100-25 = 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    print(f"PASS test_literal_braces_not_dynamic (score={r['score']})")


def test_bookmark_instead_of_quicklink():
    """Agent created a Safari bookmark instead of Raycast Quicklink — export empty."""
    r = mod.verify_quicklink_tab_reuse([], _make_env(_result(
        quicklinks=[], quicklink_count=0,
        export_file_exists=False, export_file_is_new=False,
    )), {})
    # C1 fails, C2 fails, C3 passes (1 tab), C4 passes (tofu URL), C5 passes
    # Score: 0+0+30+20+10 = 60
    assert r["score"] == 60, f"Expected 60, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_bookmark_instead_of_quicklink (score={r['score']})")


def test_tofu_wrong_servings():
    """Agent invoked with tofu but wrong servings (2 instead of 4)."""
    r = mod.verify_quicklink_tab_reuse([], _make_env(_result(
        safari_tab_urls=["https://duckduckgo.com/?q=tofu+recipe+2+servings"],
    )), {})
    # C4 fails: 100-20 = 80
    assert r["score"] == 80, f"Expected 80, got {r['score']}"
    print(f"PASS test_tofu_wrong_servings (score={r['score']})")


def test_three_tabs_after_invocation():
    r = mod.verify_quicklink_tab_reuse([], _make_env(_result(
        safari_tab_urls=[
            "https://duckduckgo.com/?q=salmon+recipe+2+servings",
            "https://duckduckgo.com/?q=tofu+recipe+4+servings",
            "https://example.com/",
        ],
        safari_tab_count=3,
    )), {})
    # C3 fails: 70
    assert r["score"] == 70, f"Expected 70, got {r['score']}"
    print(f"PASS test_three_tabs_after_invocation (score={r['score']})")


if __name__ == "__main__":
    test_missing_result_file()
    test_all_correct()
    test_do_nothing()
    test_duplicate_tab_created()
    test_literal_braces_not_dynamic()
    test_bookmark_instead_of_quicklink()
    test_tofu_wrong_servings()
    test_three_tabs_after_invocation()
    print("\nAll #9 offline tests passed.")
