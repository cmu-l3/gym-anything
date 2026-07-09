"""Offline unit tests for verify_screenshot_ocr_clipboard."""

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

CORRECT_NOTE = (
    "Equipment Inventory Product: LG French-door refrigerator "
    "Serial: REF-9X4Q-22847"
)


def _result(**overrides):
    base = {
        "task_start":      NOW,
        "final_clipboard": "call mom after 6",
        "note_body_raw":   "<div>Equipment Inventory</div><div>Serial: REF-9X4Q-22847</div>",
        "note_body_plain": CORRECT_NOTE,
        "raycast_wal_size_bytes":          5000,
        "raycast_wal_mtime":               NOW + 30,
        "raycast_wal_changed_after_setup": True,
    }
    base.update(overrides)
    return base


def test_missing_result_file():
    r = mod.verify_screenshot_ocr_clipboard([], _make_env_missing(), {})
    assert r["passed"] is False and r["score"] == 0
    print("PASS test_missing_result_file")


def test_all_correct():
    r = mod.verify_screenshot_ocr_clipboard([], _make_env(_result()), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_do_nothing():
    """Note still has only 'Serial: ' (no value pasted), clipboard preserved by setup."""
    r = mod.verify_screenshot_ocr_clipboard([], _make_env(_result(
        note_body_plain="Equipment Inventory Product: LG French-door refrigerator Serial:",
        raycast_wal_changed_after_setup=False,
    )), {})
    # C1=0, C2=15 (no distractors), C3=15 (no WTY), C4=25 (clipboard preserved), C5=0
    # Score: 55
    assert r["score"] == 55, f"Expected 55, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_do_nothing (score={r['score']})")


def test_pasted_wrong_serial_distractor():
    """Agent picked a distractor screenshot (TV one) and pasted its serial."""
    r = mod.verify_screenshot_ocr_clipboard([], _make_env(_result(
        note_body_plain="Equipment Inventory Product: LG French-door refrigerator Serial: TV-2293-OLED",
    )), {})
    # C1 fails, C2 fails, C3 passes, C4 passes, C5 passes: 0+0+15+25+15 = 55
    assert r["score"] == 55, f"Expected 55, got {r['score']}"
    print(f"PASS test_pasted_wrong_serial_distractor (score={r['score']})")


def test_copied_too_much_warranty_code_too():
    """Agent copied both the warranty claim AND the serial."""
    r = mod.verify_screenshot_ocr_clipboard([], _make_env(_result(
        note_body_plain="Serial: Warranty Claim: WTY-8X4 Serial: REF-9X4Q-22847",
    )), {})
    # C1 passes, C2 passes, C3 fails (WTY-8X4 present), C4 passes, C5 passes: 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    print(f"PASS test_copied_too_much_warranty_code_too (score={r['score']})")


def test_clipboard_not_restored():
    """Agent forgot to restore clipboard — final clipboard is the serial."""
    r = mod.verify_screenshot_ocr_clipboard([], _make_env(_result(
        final_clipboard="REF-9X4Q-22847",
    )), {})
    # C4 fails: 100 - 25 = 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    print(f"PASS test_clipboard_not_restored (score={r['score']})")


def test_clipboard_empty():
    r = mod.verify_screenshot_ocr_clipboard([], _make_env(_result(
        final_clipboard="",
    )), {})
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    print(f"PASS test_clipboard_empty (score={r['score']})")


def test_used_file_search_not_ocr():
    """Agent found nothing (File Search by filename doesn't match OCR text)."""
    r = mod.verify_screenshot_ocr_clipboard([], _make_env(_result(
        note_body_plain="Equipment Inventory Serial:",  # nothing pasted
        raycast_wal_changed_after_setup=True,  # Raycast WAS used (search), just wrong feature
    )), {})
    # C1 fails, C2 passes, C3 passes, C4 passes, C5 passes: 0+15+15+25+15 = 70
    assert r["score"] == 70, f"Expected 70, got {r['score']}"
    assert r["passed"] is True  # exactly at threshold — borderline pass
    print(f"PASS test_used_file_search_not_ocr (score={r['score']})")


def test_full_serial_plus_too_much():
    """Agent pasted entire warranty line, including the serial."""
    r = mod.verify_screenshot_ocr_clipboard([], _make_env(_result(
        note_body_plain="Serial: WTY-8X4 REF-9X4Q-22847 LG fridge",
    )), {})
    # C1 passes, C2 passes, C3 fails: 30+15+0+25+15 = 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    print(f"PASS test_full_serial_plus_too_much (score={r['score']})")


if __name__ == "__main__":
    test_missing_result_file()
    test_all_correct()
    test_do_nothing()
    test_pasted_wrong_serial_distractor()
    test_copied_too_much_warranty_code_too()
    test_clipboard_not_restored()
    test_clipboard_empty()
    test_used_file_search_not_ocr()
    test_full_serial_plus_too_much()
    print("\nAll #1 offline tests passed.")
