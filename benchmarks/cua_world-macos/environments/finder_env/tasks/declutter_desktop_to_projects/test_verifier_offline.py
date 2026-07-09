"""Offline tests for declutter_desktop_to_projects verifier (no live VM).

Run from repo root:
    python3 benchmarks/cua_world-macos/environments/finder_env/tasks/declutter_desktop_to_projects/test_verifier_offline.py
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
verify = mod.verify_declutter_desktop_to_projects

EXPECTED_FILES = mod.EXPECTED_FILES
ALL_FILES = mod.ALL_FILES
FOLDERS = mod.FOLDERS


def _perfect() -> dict:
    files_by_folder = {f: sorted(fns) for f, fns in EXPECTED_FILES.items()}
    locked_by_file = {fn: True for fn in ALL_FILES}
    readme_by_folder = {
        folder: "\n".join(sorted(fns)) + "\n"
        for folder, fns in EXPECTED_FILES.items()
    }
    return {
        "files_by_folder": files_by_folder,
        "locked_by_file": locked_by_file,
        "readme_by_folder": readme_by_folder,
        "desktop_leftover": [],
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

    failures += not run("do_nothing", {
        "files_by_folder": {f: [] for f in FOLDERS},
        "locked_by_file": {},
        "readme_by_folder": {f: None for f in FOLDERS},
        "desktop_leftover": ["HV_kitchen_quotes.txt", "SC_fall_schedule.txt"],
    }, expect_pass=False, expect_score=0)

    # Files not locked (lose 25 pts)
    d = _perfect()
    for fn in d["locked_by_file"]:
        d["locked_by_file"][fn] = False
    failures += not run("not_locked", d, expect_pass=True, expect_score=75)

    # Desktop leftover (lose 15 pts)
    d = _perfect()
    d["desktop_leftover"] = ["HV_kitchen_quotes.txt"]
    failures += not run("desktop_leftover", d, expect_pass=True, expect_score=85)

    # Missing README in one folder (lose 7 pts for Home Renovation)
    d = _perfect()
    d["readme_by_folder"]["Home Renovation"] = None
    failures += not run("missing_readme", d, expect_pass=True, expect_score=93)

    # 6 HV_ files in School Schedule instead of Home Renovation:
    # C1=round(12*40/18)=27, C2=round(12*25/18)=17, C3=20, C4=15 → 79 (passes at ≥75)
    d = _perfect()
    hv = list(EXPECTED_FILES["Home Renovation"])
    d["files_by_folder"]["School Schedule"] = sorted(
        list(EXPECTED_FILES["School Schedule"]) + hv
    )
    d["files_by_folder"]["Home Renovation"] = []
    for fn in hv:
        del d["locked_by_file"][fn]
    failures += not run("wrong_folder_6_files", d, expect_pass=True, expect_score=79)

    # All 18 files in one wrong folder: C1=0, C2=0, C3=20 (READMEs list correct names), C4=15 → 35 < 75
    d = _perfect()
    all_files = sorted(ALL_FILES)
    d["files_by_folder"] = {"Home Renovation": all_files, "School Schedule": [], "Garden Design": []}
    failures += not run("all_wrong_folder", d, expect_pass=False)

    if failures:
        print(f"\n{failures} test(s) FAILED")
        sys.exit(1)
    else:
        print("\nAll tests passed.")


if __name__ == "__main__":
    main()
