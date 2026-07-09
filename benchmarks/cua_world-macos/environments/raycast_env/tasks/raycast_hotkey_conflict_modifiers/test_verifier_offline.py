"""Offline unit tests for verify_hotkey_conflict_modifiers."""

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
        "task_start":                NOW,
        "macos_hotkey_64_unchanged": True,
        "wal_size_delta":            2000,
        "wal_changed_after_setup":   True,
        "export_file_exists":        True,
        "export_file_is_new":        True,
        "export_file_size_bytes":    5000,
        "export_content_preview":    '{"hotkey":{"raycast_notes":"fn","quick_ai":"ctrl+space","clipboard_history":"alt+v"}}',
    }
    base.update(overrides)
    return base


def test_missing_result_file():
    r = mod.verify_hotkey_conflict_modifiers([], _make_env_missing(), {})
    assert r["passed"] is False and r["score"] == 0
    print("PASS test_missing_result_file")


def test_all_correct():
    r = mod.verify_hotkey_conflict_modifiers([], _make_env(_result()), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_do_nothing():
    r = mod.verify_hotkey_conflict_modifiers([], _make_env(_result(
        wal_size_delta=0,
        export_file_exists=False,
        export_file_is_new=False,
        export_content_preview="",
    )), {})
    # C1 passes (macOS untouched), C2 fails (no WAL delta), C3 fails, C4 fails: 40
    assert r["score"] == 40, f"Expected 40, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_do_nothing (score={r['score']})")


def test_overwrote_macos_shortcut():
    r = mod.verify_hotkey_conflict_modifiers([], _make_env(_result(
        macos_hotkey_64_unchanged=False,
    )), {})
    # C1 fails: 60
    assert r["score"] == 60, f"Expected 60, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_overwrote_macos_shortcut (score={r['score']})")


def test_minor_wal_change():
    """Background WAL writes happened but no real settings edits."""
    r = mod.verify_hotkey_conflict_modifiers([], _make_env(_result(
        wal_size_delta=200,
    )), {})
    # C2 fails: 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    print(f"PASS test_minor_wal_change (score={r['score']})")


def test_no_export():
    r = mod.verify_hotkey_conflict_modifiers([], _make_env(_result(
        export_file_exists=False,
        export_file_is_new=False,
        export_content_preview="",
    )), {})
    # C3 + C4 fail: 65
    assert r["score"] == 65, f"Expected 65, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_no_export (score={r['score']})")


def test_export_but_no_keywords():
    r = mod.verify_hotkey_conflict_modifiers([], _make_env(_result(
        export_content_preview="random binary data with no keywords",
    )), {})
    # C4 fails: 80
    assert r["score"] == 80, f"Expected 80, got {r['score']}"
    print(f"PASS test_export_but_no_keywords (score={r['score']})")


if __name__ == "__main__":
    test_missing_result_file()
    test_all_correct()
    test_do_nothing()
    test_overwrote_macos_shortcut()
    test_minor_wal_change()
    test_no_export()
    test_export_but_no_keywords()
    print("\nAll #3 offline tests passed.")
