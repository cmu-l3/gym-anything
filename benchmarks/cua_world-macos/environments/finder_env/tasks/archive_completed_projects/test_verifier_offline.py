"""Offline tests for archive_completed_projects verifier (no live VM).

Run from repo root:
    python3 benchmarks/cua_world-macos/environments/finder_env/tasks/archive_completed_projects/test_verifier_offline.py
"""
from __future__ import annotations

import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("verifier", HERE / "verifier.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
verify = mod.verify_archive_completed_projects

ACTIVE_PROJECTS = mod.ACTIVE_PROJECTS
DONE_PROJECTS = mod.DONE_PROJECTS


def _perfect() -> dict:
    return {
        "active_folders_exist": {n: True for n in ACTIVE_PROJECTS},
        "done_folders_exist": {n: False for n in DONE_PROJECTS},
        "active_tags": {n: ["Green"] for n in ACTIVE_PROJECTS},
        "archive_zips": sorted(f"{n}.zip" for n in DONE_PROJECTS),
        "zip_comments": {f"{n}.zip": "Archived May 2026" for n in DONE_PROJECTS},
    }


def make_env_info(data: dict) -> dict:
    fixture = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    fixture.write(json.dumps(data).encode())
    fixture.close()

    def copy_from_env(_remote: str, local: str) -> None:
        shutil.copy(fixture.name, local)

    return {"copy_from_env": copy_from_env}


def run(label: str, data: dict, expect_pass: bool, expect_score: int | None = None) -> bool:
    r = verify({}, make_env_info(data), {})
    ok = True
    if r["passed"] != expect_pass:
        print(f"FAIL [{label}]: expected passed={expect_pass}, got {r['passed']} (score={r['score']})")
        print(f"  feedback: {r['feedback']}")
        ok = False
    if expect_score is not None and r["score"] != expect_score:
        print(f"FAIL [{label}]: expected score={expect_score}, got {r['score']}")
        print(f"  feedback: {r['feedback']}")
        ok = False
    if ok:
        print(f"PASS [{label}] score={r['score']} passed={r['passed']}")
    return ok


def main() -> None:
    failures = 0

    failures += not run("perfect", _perfect(), expect_pass=True, expect_score=100)

    # Do nothing: active folders exist (no tags), done folders exist, no zips, no comments
    failures += not run("do_nothing", {
        "active_folders_exist": {n: True for n in ACTIVE_PROJECTS},
        "done_folders_exist": {n: True for n in DONE_PROJECTS},
        "active_tags": {n: [] for n in ACTIVE_PROJECTS},
        "archive_zips": [],
        "zip_comments": {},
    }, expect_pass=False, expect_score=20)

    # Active project deleted (lose 15 pts for HomeRenovation)
    d = _perfect()
    d["active_folders_exist"]["HomeRenovation"] = False
    failures += not run("active_deleted", d, expect_pass=True, expect_score=85)

    # Original not deleted (lose 7 pts for VegetableGarden)
    d = _perfect()
    d["done_folders_exist"]["VegetableGarden"] = True
    failures += not run("original_not_deleted", d, expect_pass=True, expect_score=93)

    # Bad zip comment (lose 7 pts for VegetableGarden)
    d = _perfect()
    d["zip_comments"]["VegetableGarden.zip"] = "Done"
    failures += not run("bad_comment", d, expect_pass=True, expect_score=93)

    # Missing zip for BookClub2024: lose 10 pts C2 + 7 pts C4 (zip comment also absent) → 83
    d = _perfect()
    d["archive_zips"] = [z for z in d["archive_zips"] if "BookClub2024" not in z]
    del d["zip_comments"]["BookClub2024.zip"]
    failures += not run("missing_zip", d, expect_pass=True, expect_score=83)

    if failures:
        print(f"\n{failures} test(s) FAILED")
        sys.exit(1)
    else:
        print("\nAll tests passed.")


if __name__ == "__main__":
    main()
