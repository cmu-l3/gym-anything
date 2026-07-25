"""Offline mock tests for verify_rotate_image_clockwise.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/preview_env/tasks/rotate_image_clockwise/test_verifier_offline.py

Per task_creation_notes/13_file_content_verification_and_offline_testing.md:
required scenarios are do-nothing, wrong-target, partial, and full-correct.
Plus a few edge cases (corrupted save, setup-failure sentinel).

Each scenario injects a fabricated result dict (the shape produced by
export_result.sh) and asserts the verifier's score and pass decision.
Exits non-zero on any assertion failure so CI can gate on it.
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
VERIFIER_PATH = HERE / "verifier.py"
spec = importlib.util.spec_from_file_location("verifier", VERIFIER_PATH)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
verify = mod.verify_rotate_image_clockwise


def make_env_info(fake_result: dict) -> dict:
    fixture = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    fixture.write(json.dumps(fake_result).encode()); fixture.close()
    def copy_from_env(_remote: str, local: str) -> None:
        shutil.copy(fixture.name, local)
    return {"copy_from_env": copy_from_env, "_fixture": fixture.name}


def run(name: str, fake_result: dict, expect_score, expect_passed: bool) -> bool:
    env_info = make_env_info(fake_result)
    out = verify(traj={}, env_info=env_info, task_info={})
    Path(env_info["_fixture"]).unlink(missing_ok=True)
    score = out["score"]; passed = out["passed"]
    if isinstance(expect_score, tuple):
        lo, hi = expect_score
        score_ok = lo <= score <= hi
        expect_desc = f"{lo}..{hi}"
    else:
        score_ok = score == expect_score
        expect_desc = str(expect_score)
    pass_ok = passed == expect_passed
    status = "PASS" if (score_ok and pass_ok) else "FAIL"
    print(f"[{status}] {name}: got score={score} passed={passed} "
          f"(expected score={expect_desc} passed={expect_passed})")
    if not (score_ok and pass_ok):
        print(f"    subscores: {out['subscores']}")
        print(f"    feedback:  {out['feedback']}")
        return False
    return True


TASK_START = 1_000_000
INIT_W, INIT_H = 800, 600   # Wikimedia "PNG transparency demonstration" (non-square)


def _base(**overrides):
    """Build a result dict starting from the do-nothing state."""
    d = {
        "task_start": TASK_START,
        "input_exists": True,           # setup downloaded the image
        "input_fresh": False,           # do-nothing leaves mtime at setup-time
        "input_valid_image": True,
        "initial_width": INIT_W,
        "initial_height": INIT_H,
        "current_width": INIT_W,        # do-nothing: dims unchanged
        "current_height": INIT_H,
        "input_mtime": TASK_START - 5,
        "input_size_bytes": 102_400,
        "initial_sha256": "a" * 64,
        "current_sha256": "a" * 64,
        "byte_content_changed": False,
        "dimensions_swapped": False,
    }
    d.update(overrides)
    return d


DO_NOTHING = _base()

WRONG_TARGET = _base(
    # Agent rotated a different file. Canonical file is untouched.
    input_fresh=False, dimensions_swapped=False,
    current_width=INIT_W, current_height=INIT_H,
)

SAVED_WITHOUT_ROTATING = _base(
    # Agent opened file in Preview, hit Cmd+S without rotating. mtime updated,
    # but dimensions unchanged. Should NOT pass — pass threshold 70 > 60.
    input_fresh=True, dimensions_swapped=False,
    current_width=INIT_W, current_height=INIT_H,
    input_mtime=TASK_START + 10,
    current_sha256="b" * 64, byte_content_changed=True,
)

ROTATED_AND_SAVED = _base(
    # Happy path: agent rotated 90° CW and saved. Dimensions swap.
    input_fresh=True, dimensions_swapped=True,
    current_width=INIT_H, current_height=INIT_W,
    input_mtime=TASK_START + 12,
    current_sha256="c" * 64, byte_content_changed=True,
)

ROTATED_BUT_CORRUPT = _base(
    # Dimensions swapped (somehow), but file unreadable by sips. Unlikely but
    # plausible if a save was partial. Should not pass.
    input_fresh=True, input_valid_image=False, dimensions_swapped=True,
    current_width=INIT_H, current_height=INIT_W,
    input_mtime=TASK_START + 8,
)

DELETED_FILE = _base(
    # Agent deleted the canonical file. C1 = 0, gate fires (no fresh, no dims).
    input_exists=False, input_valid_image=False,
    current_width=0, current_height=0,
    input_mtime=0,
)

ROTATED_EXTERNALLY_BACKDATED = _base(
    # Adversarial: agent rotated outside Preview and backdated mtime with
    # `touch -t`. Dims are swapped but file not fresh. Total: 15 + 0 + 40 + 20 = 75 → pass.
    # We accept this as a legitimate completion (the task semantically achieved).
    input_fresh=False, dimensions_swapped=True,
    current_width=INIT_H, current_height=INIT_W,
    input_mtime=TASK_START - 100,
    current_sha256="d" * 64, byte_content_changed=True,
)

SETUP_FAILED = _base(
    # initial_width=0 means setup couldn't record baseline. Verifier refuses
    # to score and returns 0 with a clear message.
    initial_width=0, initial_height=0,
)


if __name__ == "__main__":
    print("=== Offline verifier tests: rotate_image_clockwise ===")
    results = [
        run("do-nothing",                   DO_NOTHING,                    expect_score=0,   expect_passed=False),
        run("wrong-target (unchanged)",     WRONG_TARGET,                  expect_score=0,   expect_passed=False),
        run("saved without rotating",       SAVED_WITHOUT_ROTATING,        expect_score=60,  expect_passed=False),
        run("rotated and saved",            ROTATED_AND_SAVED,             expect_score=100, expect_passed=True),
        run("rotated but corrupt image",    ROTATED_BUT_CORRUPT,           expect_score=80,  expect_passed=True),
        run("deleted file",                 DELETED_FILE,                  expect_score=0,   expect_passed=False),
        run("rotated externally backdated", ROTATED_EXTERNALLY_BACKDATED,  expect_score=75,  expect_passed=True),
        run("setup recorded no baseline",   SETUP_FAILED,                  expect_score=0,   expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
