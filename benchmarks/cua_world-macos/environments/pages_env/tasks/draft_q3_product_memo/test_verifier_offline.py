"""Offline mock tests for verify_draft_q3_product_memo.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/pages_env/tasks/draft_q3_product_memo/test_verifier_offline.py

Per `task_creation_notes/13_file_content_verification_and_offline_testing.md`,
required scenarios are: do-nothing, wrong-target, partial, full-correct. Plus
a couple of anti-gaming edges specific to this task (title-only/empty-body,
stale-mtime full content, content-no-save-gate).

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
verify = mod.verify_draft_q3_product_memo


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
TARGET = "/Users/lume/Documents/Q3 Product Strategy Memo.pages"

DO_NOTHING = {
    # No saving, no typing.
    "task_start": TASK_START,
    "target_path": TARGET,
    "target_doc_name": "Q3 Product Strategy Memo",
    "target_exists": False, "target_mtime": 0, "target_fresh": False,
    "body_text_target": "", "body_text_front": "",
    "phrase_ai": False, "phrase_date": False, "phrase_nps": False, "phrase_p0": False,
    "other_post_start_pages": [],
    "total_pages_post_start": 0,
}

WRONG_TARGET = {
    # Agent saved a different filename. Strict gate fires \u2192 0.
    "task_start": TASK_START,
    "target_path": TARGET,
    "target_doc_name": "Q3 Product Strategy Memo",
    "target_exists": False, "target_mtime": 0, "target_fresh": False,
    "body_text_target": "", "body_text_front": "Some content...",
    "phrase_ai": True, "phrase_date": True, "phrase_nps": True, "phrase_p0": True,
    "other_post_start_pages": ["q3_memo.pages", "draft.pages"],
    "total_pages_post_start": 2,
}

TITLE_ONLY = {
    # Agent saved with the right name but typed nothing. Only C1 (fresh) \u2192 20.
    "task_start": TASK_START,
    "target_path": TARGET,
    "target_doc_name": "Q3 Product Strategy Memo",
    "target_exists": True, "target_mtime": TASK_START + 30, "target_fresh": True,
    "body_text_target": "", "body_text_front": "",
    "phrase_ai": False, "phrase_date": False, "phrase_nps": False, "phrase_p0": False,
    "other_post_start_pages": [],
    "total_pages_post_start": 1,
}

PARTIAL_TWO_PHRASES = {
    # File saved correctly + AI line + date \u2192 C1 (20) + C2 (25) + C3 (25) = 70 PASS.
    "task_start": TASK_START,
    "target_path": TARGET,
    "target_doc_name": "Q3 Product Strategy Memo",
    "target_exists": True, "target_mtime": TASK_START + 60, "target_fresh": True,
    "body_text_target": "Launch AI-assisted onboarding by 2026-09-30",
    "body_text_front": "",
    "phrase_ai": True, "phrase_date": True, "phrase_nps": False, "phrase_p0": False,
    "other_post_start_pages": [],
    "total_pages_post_start": 1,
}

PARTIAL_ONE_PHRASE = {
    # File saved + only the AI line \u2192 C1 (20) + C2 (25) = 45 FAIL.
    "task_start": TASK_START,
    "target_path": TARGET,
    "target_doc_name": "Q3 Product Strategy Memo",
    "target_exists": True, "target_mtime": TASK_START + 30, "target_fresh": True,
    "body_text_target": "Launch AI-assisted onboarding by next quarter",
    "body_text_front": "",
    "phrase_ai": True, "phrase_date": False, "phrase_nps": False, "phrase_p0": False,
    "other_post_start_pages": [],
    "total_pages_post_start": 1,
}

PARTIAL_NPS_ONLY = {
    # File saved + AI + NPS half (no P0) \u2192 20 + 25 + 15 = 60 PASS (boundary).
    "task_start": TASK_START,
    "target_path": TARGET,
    "target_doc_name": "Q3 Product Strategy Memo",
    "target_exists": True, "target_mtime": TASK_START + 30, "target_fresh": True,
    "body_text_target": "Launch AI-assisted onboarding ... Raise NPS from 42 to 55 ...",
    "body_text_front": "",
    "phrase_ai": True, "phrase_date": False, "phrase_nps": True, "phrase_p0": False,
    "other_post_start_pages": [],
    "total_pages_post_start": 1,
}

FULL_CORRECT = {
    # All four criteria satisfied \u2192 100.
    "task_start": TASK_START,
    "target_path": TARGET,
    "target_doc_name": "Q3 Product Strategy Memo",
    "target_exists": True, "target_mtime": TASK_START + 90, "target_fresh": True,
    "body_text_target": (
        "Launch AI-assisted onboarding by 2026-09-30\n"
        "Raise NPS from 42 to 55 with quarterly user-research sprints\n"
        "Reduce P0 incident rate by 30% via on-call rotation overhaul"
    ),
    "body_text_front": "",
    "phrase_ai": True, "phrase_date": True, "phrase_nps": True, "phrase_p0": True,
    "other_post_start_pages": [],
    "total_pages_post_start": 1,
}

STALE_FILE_FULL_CONTENT = {
    # File exists at target path but mtime predates task_start (10 pts partial
    # for C1), with all content present. 10 + 25 + 25 + 30 = 90 \u2192 PASS.
    # This is the verifier's intentional behavior for unusual clock-skew /
    # pre-existing-file cases where the body is clearly the agent's work.
    "task_start": TASK_START,
    "target_path": TARGET,
    "target_doc_name": "Q3 Product Strategy Memo",
    "target_exists": True, "target_mtime": TASK_START - 100, "target_fresh": False,
    "body_text_target": (
        "Launch AI-assisted onboarding by 2026-09-30\n"
        "Raise NPS from 42 to 55\n"
        "Reduce P0 incident rate by 30%"
    ),
    "body_text_front": "",
    "phrase_ai": True, "phrase_date": True, "phrase_nps": True, "phrase_p0": True,
    "other_post_start_pages": [],
    "total_pages_post_start": 1,
}

CONTENT_NO_SAVE_GATE = {
    # Agent typed all the right content but never saved. The file doesn't
    # exist, no other .pages created. do-nothing gate fires (since
    # total_pages_post_start == 0). \u2192 0.
    "task_start": TASK_START,
    "target_path": TARGET,
    "target_doc_name": "Q3 Product Strategy Memo",
    "target_exists": False, "target_mtime": 0, "target_fresh": False,
    "body_text_target": "",
    "body_text_front": (
        "Launch AI-assisted onboarding by 2026-09-30\n"
        "Raise NPS from 42 to 55\n"
        "Reduce P0 incident rate by 30%"
    ),
    "phrase_ai": True, "phrase_date": True, "phrase_nps": True, "phrase_p0": True,
    "other_post_start_pages": [],
    "total_pages_post_start": 0,
}


if __name__ == "__main__":
    print("=== Offline verifier tests: draft_q3_product_memo ===")
    results = [
        run("do-nothing",                                   DO_NOTHING,                expect_score=0,   expect_passed=False),
        run("wrong-target (saved different filename)",      WRONG_TARGET,              expect_score=0,   expect_passed=False),
        run("title only (saved but empty body)",            TITLE_ONLY,                expect_score=20,  expect_passed=False),
        run("partial (1 of 3 content checks)",              PARTIAL_ONE_PHRASE,        expect_score=45,  expect_passed=False),
        run("partial (NPS half no P0)",                     PARTIAL_NPS_ONLY,          expect_score=60,  expect_passed=True),
        run("partial (2 phrases AI+date)",                  PARTIAL_TWO_PHRASES,       expect_score=70,  expect_passed=True),
        run("full-correct (all four checks)",               FULL_CORRECT,              expect_score=100, expect_passed=True),
        run("stale file but full content (clock-skew)",     STALE_FILE_FULL_CONTENT,   expect_score=90,  expect_passed=True),
        run("content but never saved (do-nothing gate)",    CONTENT_NO_SAVE_GATE,      expect_score=0,   expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
