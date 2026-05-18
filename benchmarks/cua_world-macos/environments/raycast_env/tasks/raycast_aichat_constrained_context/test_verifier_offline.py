"""Offline unit tests for verify_aichat_constrained_context."""

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

INITIAL_BODY = (
    "Packing constraints\nDay-pack capacity: 18L\nWeight max: 8 lbs\n"
    "Must include: rain shell, change of socks, water bottle, $20 cash, snack bar\n"
    "Constraints: Cooper has a vet appointment at 7:30 PM tonight. Battery pack."
)

CORRECT_PLAIN = (
    INITIAL_BODY
    + "\n\n## Conflict check\n"
    + "Yes — the 5 PM drive to Multnomah Falls overlaps with the 4 PM "
      "quarterly check-in call (16:00-17:00). The vet appointment at 7:30 PM "
      "conflicts with the 9:30 PM dessert plan since the constraints say no "
      "outdoors after 9 PM (early dog feeding)."
)


def _result(**overrides):
    base = {
        "task_start":          NOW,
        "initial_note_length": len(INITIAL_BODY),
        "note_body_raw":       CORRECT_PLAIN,
        "note_body_plain":     CORRECT_PLAIN,
        "note_body_length":    len(CORRECT_PLAIN),
        "note_grew":           True,
        "new_note_count":      0,
        "raycast_wal_changed_after_setup": True,
    }
    base.update(overrides)
    return base


def test_missing_result_file():
    r = mod.verify_aichat_constrained_context([], _make_env_missing(), {})
    assert r["passed"] is False and r["score"] == 0
    print("PASS test_missing_result_file")


def test_all_correct():
    r = mod.verify_aichat_constrained_context([], _make_env(_result()), {})
    assert r["passed"] is True
    assert r["score"] == 100, f"Expected 100, got {r['score']}"
    print(f"PASS test_all_correct (score={r['score']})")


def test_do_nothing():
    r = mod.verify_aichat_constrained_context([], _make_env(_result(
        note_body_raw=INITIAL_BODY, note_body_plain=INITIAL_BODY,
        note_body_length=len(INITIAL_BODY), note_grew=False,
        raycast_wal_changed_after_setup=False,
    )), {})
    # C1=15 (note exists), C2=0, C3=0, C4=15 (original kept), C5=10 (no new note), C6=0 -> 40
    assert r["score"] == 40, f"Expected 40, got {r['score']}"
    assert r["passed"] is False
    print(f"PASS test_do_nothing (score={r['score']})")


def test_appended_but_no_heading():
    r = mod.verify_aichat_constrained_context([], _make_env(_result(
        note_body_plain=INITIAL_BODY + "\n\nConflict: yes the drive overlaps with the call.",
    )), {})
    # C3 fails: 75
    assert r["score"] == 75, f"Expected 75, got {r['score']}"
    print(f"PASS test_appended_but_no_heading (score={r['score']})")


def test_created_new_note_instead():
    r = mod.verify_aichat_constrained_context([], _make_env(_result(
        new_note_count=1,
    )), {})
    # C5 fails: 90
    assert r["score"] == 90, f"Expected 90, got {r['score']}"
    print(f"PASS test_created_new_note_instead (score={r['score']})")


def test_overwrote_existing_content():
    r = mod.verify_aichat_constrained_context([], _make_env(_result(
        note_body_plain="## Conflict check\nYes there are conflicts.",
    )), {})
    # C4 fails (original lost): 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    print(f"PASS test_overwrote_existing_content (score={r['score']})")


def test_no_raycast():
    r = mod.verify_aichat_constrained_context([], _make_env(_result(
        raycast_wal_changed_after_setup=False,
    )), {})
    # C6 fails: 85
    assert r["score"] == 85, f"Expected 85, got {r['score']}"
    print(f"PASS test_no_raycast (score={r['score']})")


def test_note_deleted():
    r = mod.verify_aichat_constrained_context([], _make_env(_result(
        note_body_raw="", note_body_plain="", note_grew=False, note_body_length=0,
    )), {})
    # C1+C2+C3+C4 fail; C5=10, C6=15 -> 25
    assert r["score"] == 25, f"Expected 25, got {r['score']}"
    print(f"PASS test_note_deleted (score={r['score']})")


if __name__ == "__main__":
    test_missing_result_file()
    test_all_correct()
    test_do_nothing()
    test_appended_but_no_heading()
    test_created_new_note_instead()
    test_overwrote_existing_content()
    test_no_raycast()
    test_note_deleted()
    print("\nAll #10 offline tests passed.")
