"""Offline mock tests for verify_create_meeting_agenda.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/apple_notes_env/tasks/create_meeting_agenda/test_verifier_offline.py

Per task_creation_notes/13_file_content_verification_and_offline_testing.md the
required scenarios are: do-nothing, wrong-target, partial, full-correct. Plus
a couple of anti-gaming edges specific to this task (title-only, all-content-
no-title, multiple matches).

Each scenario injects a fabricated result dict (the shape produced by
export_result.sh) and asserts the verifier's score and pass decision. Exits
non-zero on any assertion failure so CI can gate on it.
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
verify = mod.verify_create_meeting_agenda


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
        print(f"    subscores: {out.get('subscores')}")
        print(f"    feedback:  {out.get('feedback')}")
        return False
    return True


TASK_START = 1_000_000
TARGET = "Q3 Planning Kickoff"

DO_NOTHING = {
    # No notes touched at all.
    "task_start": TASK_START,
    "target_title": TARGET,
    "matching_count": 0,
    "note_title": "",
    "note_body_html": "",
    "note_body_text": "",
    "line_hire": False, "line_okr": False, "line_launch": False,
    "total_notes_post_start": 0,
    "other_post_start_titles": [],
}

WRONG_TARGET = {
    # Agent created notes with a different title.
    "task_start": TASK_START,
    "target_title": TARGET,
    "matching_count": 0,
    "note_title": "",
    "note_body_html": "",
    "note_body_text": "",
    "line_hire": False, "line_okr": False, "line_launch": False,
    "total_notes_post_start": 2,
    "other_post_start_titles": ["Random Note", "Grocery List"],
}

TITLE_ONLY = {
    # Agent created the target note but wrote nothing in the body.
    # Only C1 scores \u2192 20. Below pass threshold.
    "task_start": TASK_START,
    "target_title": TARGET,
    "matching_count": 1,
    "note_title": TARGET,
    "note_body_html": f"<div>{TARGET}</div>",
    "note_body_text": TARGET,
    "line_hire": False, "line_okr": False, "line_launch": False,
    "total_notes_post_start": 1,
    "other_post_start_titles": [],
}

PARTIAL_TWO_LINES = {
    # Title correct + hire line + okr line, but no launch date \u2192 70 \u2192 PASS.
    # We want a TRUE partial below pass; see PARTIAL_ONE_LINE for that.
    "task_start": TASK_START,
    "target_title": TARGET,
    "matching_count": 1,
    "note_title": TARGET,
    "note_body_html": "<div><ul><li>Hire 3 senior engineers</li>"
                       "<li>Q3 OKR target: $5M revenue</li></ul></div>",
    "note_body_text": "Hire 3 senior engineers\nQ3 OKR target: $5M revenue",
    "line_hire": True, "line_okr": True, "line_launch": False,
    "total_notes_post_start": 1,
    "other_post_start_titles": [],
}

PARTIAL_ONE_LINE = {
    # Title correct + only the hire line \u2192 20 + 25 = 45 \u2192 FAIL (< 60).
    "task_start": TASK_START,
    "target_title": TARGET,
    "matching_count": 1,
    "note_title": TARGET,
    "note_body_html": "<div>Hire 3 senior engineers</div>",
    "note_body_text": "Hire 3 senior engineers",
    "line_hire": True, "line_okr": False, "line_launch": False,
    "total_notes_post_start": 1,
    "other_post_start_titles": [],
}

FULL_CORRECT = {
    # All three lines present.
    "task_start": TASK_START,
    "target_title": TARGET,
    "matching_count": 1,
    "note_title": TARGET,
    "note_body_html": (
        "<div><ul><li>Hire 3 senior engineers</li>"
        "<li>Q3 OKR target: $5M revenue</li>"
        "<li>Product launch on 2026-08-15</li></ul></div>"
    ),
    "note_body_text": (
        "Hire 3 senior engineers\n"
        "Q3 OKR target: $5M revenue\n"
        "Product launch on 2026-08-15"
    ),
    "line_hire": True, "line_okr": True, "line_launch": True,
    "total_notes_post_start": 1,
    "other_post_start_titles": [],
}

MULTIPLE_MATCHES_FULL = {
    # Agent created two notes with the same title (because they got confused).
    # Verifier scores the first one's content; should still pass on full content.
    "task_start": TASK_START,
    "target_title": TARGET,
    "matching_count": 2,
    "note_title": TARGET,
    "note_body_html": (
        "<div>Hire 3 senior engineers<br/>"
        "Q3 OKR target: $5M revenue<br/>"
        "Product launch on 2026-08-15</div>"
    ),
    "note_body_text": (
        "Hire 3 senior engineers\n"
        "Q3 OKR target: $5M revenue\n"
        "Product launch on 2026-08-15"
    ),
    "line_hire": True, "line_okr": True, "line_launch": True,
    "total_notes_post_start": 2,
    "other_post_start_titles": [],
}

CONTENT_NO_TITLE_GATE_TEST = {
    # Anti-gaming: agent typed the right content into a wrong-titled note.
    # Strict gate fires because matching_count == 0 and other titles exist.
    # All content flags True would otherwise be 80 pts; gate must zero them.
    "task_start": TASK_START,
    "target_title": TARGET,
    "matching_count": 0,
    "note_title": "",
    "note_body_html": "",
    "note_body_text": "",
    "line_hire": True, "line_okr": True, "line_launch": True,
    "total_notes_post_start": 1,
    "other_post_start_titles": ["My Q3 Notes"],
}


if __name__ == "__main__":
    print("=== Offline verifier tests: create_meeting_agenda ===")
    results = [
        run("do-nothing",                                DO_NOTHING,                expect_score=0,   expect_passed=False),
        run("wrong-target (different titled note)",      WRONG_TARGET,              expect_score=0,   expect_passed=False),
        run("title only (body empty)",                   TITLE_ONLY,                expect_score=20,  expect_passed=False),
        run("partial (1 of 3 content lines)",            PARTIAL_ONE_LINE,          expect_score=45,  expect_passed=False),
        run("partial (2 of 3 content lines, passes)",    PARTIAL_TWO_LINES,         expect_score=70,  expect_passed=True),
        run("full-correct (all three lines)",            FULL_CORRECT,              expect_score=100, expect_passed=True),
        run("multiple matches (first scored, passes)",   MULTIPLE_MATCHES_FULL,     expect_score=100, expect_passed=True),
        run("content-no-title gate (anti-gaming)",       CONTENT_NO_TITLE_GATE_TEST, expect_score=0,  expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
