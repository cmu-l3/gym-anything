"""Offline mock tests for verify_devtools_security_header_audit.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/safari_env/tasks/devtools_security_header_audit/test_verifier_offline.py

Per task_creation_notes/13_file_content_verification_and_offline_testing.md:
required scenarios are do-nothing, wrong-target, partial, and full-correct.
Plus the Safari-specific anti-gaming scenarios for fabricated-JSON-no-visits
and the strict wrong-target gate.

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
verify = mod.verify_devtools_security_header_audit


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

DO_NOTHING = {
    "task_start": TASK_START, "github_visits": 0, "gitlab_visits": 0,
    "bitbucket_visits": 0, "npm_visits": 0, "pypi_visits": 0,
    "report_exists": False, "report_fresh": False, "report_valid_json": False,
    "sites_present": [], "non_required_sites": [], "per_site_header_count": {},
    "total_non_empty_headers": 0, "hsts_looks_valid": 0, "csp_looks_valid": 0,
}

WRONG_TARGET_EMPTY_REPORT = {
    # Agent wrote some report but the export saw no required-site keys AND
    # no other top-level keys (e.g., the agent wrote {"note": "done"}).
    # The strict gate needs `non_required_sites` to be non-empty to fire,
    # so this scenario falls through to scoring: C2 awards 15 for fresh
    # valid JSON, everything else gated to 0.
    "task_start": TASK_START, "github_visits": 0, "gitlab_visits": 0,
    "bitbucket_visits": 0, "npm_visits": 0, "pypi_visits": 0,
    "report_exists": True, "report_fresh": True, "report_valid_json": True,
    "sites_present": [], "non_required_sites": [], "per_site_header_count": {},
    "total_non_empty_headers": 0, "hsts_looks_valid": 0, "csp_looks_valid": 0,
}

WRONG_TARGET_STRICT = {
    # Agent audited e.g. google.com / facebook.com. Export populates
    # non_required_sites; sites_present is empty (no required matched).
    # Strict gate fires → score 0.
    "task_start": TASK_START, "github_visits": 0, "gitlab_visits": 0,
    "bitbucket_visits": 0, "npm_visits": 0, "pypi_visits": 0,
    "report_exists": True, "report_fresh": True, "report_valid_json": True,
    "sites_present": [], "non_required_sites": ["google.com", "facebook.com"],
    "per_site_header_count": {},
    "total_non_empty_headers": 0, "hsts_looks_valid": 0, "csp_looks_valid": 0,
}

PARTIAL = {
    # github.com + gitlab.com done end-to-end. Others untouched.
    # C1: 2*5=10  C2: 15  C3: 2*4=8  C4: 2*5=10  C5: 4+3=7 → total 50.
    "task_start": TASK_START, "github_visits": 3, "gitlab_visits": 2,
    "bitbucket_visits": 0, "npm_visits": 0, "pypi_visits": 0,
    "report_exists": True, "report_fresh": True, "report_valid_json": True,
    "sites_present": ["github.com", "gitlab.com"], "non_required_sites": [],
    "per_site_header_count": {"github.com": 4, "gitlab.com": 4},
    "total_non_empty_headers": 8, "hsts_looks_valid": 2, "csp_looks_valid": 2,
}

FULL_CORRECT = {
    # All 5 done correctly. C1:25 C2:15 C3:20 C4:25 C5:15 → 100.
    "task_start": TASK_START, "github_visits": 5, "gitlab_visits": 5,
    "bitbucket_visits": 5, "npm_visits": 5, "pypi_visits": 5,
    "report_exists": True, "report_fresh": True, "report_valid_json": True,
    "sites_present": ["github.com", "gitlab.com", "bitbucket.org", "npmjs.com", "pypi.org"],
    "non_required_sites": [],
    "per_site_header_count": {"github.com": 4, "gitlab.com": 4, "bitbucket.org": 4,
                              "npmjs.com": 4, "pypi.org": 4},
    "total_non_empty_headers": 20, "hsts_looks_valid": 5, "csp_looks_valid": 5,
}

INVALID_JSON_REPORT = {
    # Report saved as malformed JSON (export sets report_valid_json=False).
    # C2 awards only 3 pts for an invalid-but-existent report.
    "task_start": TASK_START, "github_visits": 0, "gitlab_visits": 0,
    "bitbucket_visits": 0, "npm_visits": 0, "pypi_visits": 0,
    "report_exists": True, "report_fresh": True, "report_valid_json": False,
    "sites_present": [], "non_required_sites": [], "per_site_header_count": {},
    "total_non_empty_headers": 0, "hsts_looks_valid": 0, "csp_looks_valid": 0,
}

STALE_REPORT = {
    # Report mtime predates task_start (agent moved a pre-written file?).
    # C2 awards 8 (stale). No visits → C1/C3/C4/C5 zero. Total 8.
    "task_start": TASK_START, "github_visits": 0, "gitlab_visits": 0,
    "bitbucket_visits": 0, "npm_visits": 0, "pypi_visits": 0,
    "report_exists": True, "report_fresh": False, "report_valid_json": True,
    "sites_present": ["github.com"], "non_required_sites": [],
    "per_site_header_count": {"github.com": 4},
    "total_non_empty_headers": 4, "hsts_looks_valid": 1, "csp_looks_valid": 1,
}

NO_VISITS_FULL_REPORT = {
    # Agent fabricated a plausible JSON without ever browsing. Per-site visit
    # gating in C3/C4/C5 zeros out their contributions. Only C2 scores → 15.
    # This is the Safari port's hardening over the source firefox verifier
    # (which would have scored 75 → false pass).
    "task_start": TASK_START, "github_visits": 0, "gitlab_visits": 0,
    "bitbucket_visits": 0, "npm_visits": 0, "pypi_visits": 0,
    "report_exists": True, "report_fresh": True, "report_valid_json": True,
    "sites_present": ["github.com", "gitlab.com", "bitbucket.org", "npmjs.com", "pypi.org"],
    "non_required_sites": [],
    "per_site_header_count": {"github.com": 4, "gitlab.com": 4, "bitbucket.org": 4,
                              "npmjs.com": 4, "pypi.org": 4},
    "total_non_empty_headers": 20, "hsts_looks_valid": 5, "csp_looks_valid": 5,
}


if __name__ == "__main__":
    print("=== Offline verifier tests: devtools_security_header_audit ===")
    results = [
        run("do-nothing",                                DO_NOTHING,                expect_score=0,   expect_passed=False),
        run("wrong-target (empty report)",               WRONG_TARGET_EMPTY_REPORT, expect_score=15,  expect_passed=False),
        run("wrong-target (strict gate fires)",          WRONG_TARGET_STRICT,       expect_score=0,   expect_passed=False),
        run("partial (2/5 sites done end-to-end)",       PARTIAL,                   expect_score=50,  expect_passed=False),
        run("full-correct (all 5 sites)",                FULL_CORRECT,              expect_score=100, expect_passed=True),
        run("invalid-json report",                       INVALID_JSON_REPORT,       expect_score=3,   expect_passed=False),
        run("stale report (mtime predates task_start)",  STALE_REPORT,              expect_score=8,   expect_passed=False),
        run("no-visits full report (anti-gaming gate)",  NO_VISITS_FULL_REPORT,     expect_score=15,  expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
