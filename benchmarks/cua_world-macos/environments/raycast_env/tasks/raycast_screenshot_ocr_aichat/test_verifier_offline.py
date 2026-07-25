"""Offline unit tests for verify_screenshot_ocr_aichat."""

import importlib.util
import json
import os

_spec = importlib.util.spec_from_file_location(
    "verifier",
    os.path.join(os.path.dirname(__file__), "verifier.py"),
)
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)


def _make_env(d):
    def copy_from_env(src, dst):
        with open(dst, "w") as f:
            json.dump(d, f)
    return {"copy_from_env": copy_from_env}


def _make_env_missing():
    def copy_from_env(src, dst):
        raise FileNotFoundError(src)
    return {"copy_from_env": copy_from_env}


NOW = 1748300000


def _result(**overrides):
    base = {
        "task_start":   NOW,
        "note_exists":  True,
        "note_body_raw":   "<div>UPS Ground · 1Z-9X4-2284-7AB · Arrives Tuesday</div>",
        "note_body_plain": "UPS Ground · 1Z-9X4-2284-7AB · Arrives Tuesday",
        "raycast_wal_changed_after_setup": True,
    }
    base.update(overrides)
    return base


def test_missing_result_file():
    r = mod.verify_screenshot_ocr_aichat([], _make_env_missing(), {})
    assert r["passed"] is False and r["score"] == 0
    print("PASS test_missing_result_file")


def test_all_correct():
    r = mod.verify_screenshot_ocr_aichat([], _make_env(_result()), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_do_nothing():
    r = mod.verify_screenshot_ocr_aichat([], _make_env(_result(
        note_exists=False, note_body_plain="",
        raycast_wal_changed_after_setup=False,
    )), {})
    # C1=0, C2=0, C3=0, C4=15, C5=15, C6=10, C7=0 -> 40
    assert r["score"] == 40, f"Expected 40, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_do_nothing (score={r['score']})")


def test_wrong_tracking_from_distractor():
    r = mod.verify_screenshot_ocr_aichat([], _make_env(_result(
        note_body_plain="USPS · 9405-5111-2345-6789 · Arrives Thursday",
    )), {})
    # C2 fails, C3 fails (no UPS), C4 fails (distractor present): 100-30-10-15 = 45
    assert r["score"] == 45, f"Expected 45, got {r['score']}"
    print(f"PASS test_wrong_tracking_from_distractor (score={r['score']})")


def test_address_leaked():
    r = mod.verify_screenshot_ocr_aichat([], _make_env(_result(
        note_body_plain="UPS Ground · 1Z-9X4-2284-7AB · Arrives Tuesday. Ship to: 2240 SE Yamhill St.",
    )), {})
    # C5 fails: 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    print(f"PASS test_address_leaked (score={r['score']})")


def test_card_leaked():
    r = mod.verify_screenshot_ocr_aichat([], _make_env(_result(
        note_body_plain="UPS Ground · 1Z-9X4-2284-7AB · Arrives Tuesday. Card 8821.",
    )), {})
    # C6 fails: 90
    assert r["score"] == 90, f"Expected 90, got {r['score']}"
    print(f"PASS test_card_leaked (score={r['score']})")


def test_correct_tracking_no_carrier():
    r = mod.verify_screenshot_ocr_aichat([], _make_env(_result(
        note_body_plain="1Z-9X4-2284-7AB Arrives Tuesday",
    )), {})
    # C3 fails (no UPS string): 90
    assert r["score"] == 90, f"Expected 90, got {r['score']}"
    print(f"PASS test_correct_tracking_no_carrier (score={r['score']})")


def test_no_raycast():
    r = mod.verify_screenshot_ocr_aichat([], _make_env(_result(
        raycast_wal_changed_after_setup=False,
    )), {})
    # C7 fails: 95
    assert r["score"] == 95, f"Expected 95, got {r['score']}"
    print(f"PASS test_no_raycast (score={r['score']})")


def test_both_pii_leaked():
    r = mod.verify_screenshot_ocr_aichat([], _make_env(_result(
        note_body_plain="UPS Ground · 1Z-9X4-2284-7AB · Ship to 2240 SE Yamhill, Card 8821",
    )), {})
    # C5+C6 fail: 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    print(f"PASS test_both_pii_leaked (score={r['score']})")


if __name__ == "__main__":
    test_missing_result_file()
    test_all_correct()
    test_do_nothing()
    test_wrong_tracking_from_distractor()
    test_address_leaked()
    test_card_leaked()
    test_correct_tracking_no_carrier()
    test_no_raycast()
    test_both_pii_leaked()
    print("\nAll #6 offline tests passed.")
