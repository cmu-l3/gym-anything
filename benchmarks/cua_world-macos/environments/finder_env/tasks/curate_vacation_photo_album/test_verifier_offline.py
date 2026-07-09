"""Offline tests for curate_vacation_photo_album verifier (no live VM).

Run from repo root:
    python3 benchmarks/cua_world-macos/environments/finder_env/tasks/curate_vacation_photo_album/test_verifier_offline.py
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
verify = mod.verify_curate_vacation_photo_album

GC_FILES = mod.GC_FILES
PC_FILES = mod.PC_FILES
NE_FILES = mod.NE_FILES
GC_HIGHLIGHTS = mod.GC_HIGHLIGHTS
PC_HIGHLIGHTS = mod.PC_HIGHLIGHTS
NE_HIGHLIGHTS = mod.NE_HIGHLIGHTS


def make_env_info(data: dict) -> dict:
    fixture = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    fixture.write(json.dumps(data).encode())
    fixture.close()

    def copy_from_env(_remote: str, local: str) -> None:
        shutil.copy(fixture.name, local)

    return {"copy_from_env": copy_from_env}


def _perfect() -> dict:
    return {
        "gc_folder_exists": True,
        "pc_folder_exists": True,
        "ne_folder_exists": True,
        "gc_files": sorted(GC_FILES),
        "pc_files": sorted(PC_FILES),
        "ne_files": sorted(NE_FILES),
        "gc_highlights": sorted(GC_HIGHLIGHTS),
        "pc_highlights": sorted(PC_HIGHLIGHTS),
        "ne_highlights": sorted(NE_HIGHLIGHTS),
        "gc_tag": "Blue",
        "pc_tag": "Green",
        "ne_tag": "Red",
        "gc_comment": "Grand Canyon July 2019 road trip",
        "pc_comment": "Pacific Coast April 2021 drive",
        "ne_comment": "New England August 2023 fall leaves",
    }


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

    # C1=15, C2=48, C3=21, C4=12, C5=4 → 100
    failures += not run("perfect", _perfect(), expect_pass=True, expect_score=100)

    # Do nothing
    failures += not run("do_nothing", {
        "gc_folder_exists": False, "pc_folder_exists": False, "ne_folder_exists": False,
        "gc_files": [], "pc_files": [], "ne_files": [],
        "gc_highlights": [], "pc_highlights": [], "ne_highlights": [],
        "gc_tag": "", "pc_tag": "", "ne_tag": "",
        "gc_comment": "", "pc_comment": "", "ne_comment": "",
    }, expect_pass=False, expect_score=0)

    # Wrong tags GC=Red, NE=Blue: lose 7+7=14 pts → 86
    d = _perfect()
    d["gc_tag"] = "Red"
    d["ne_tag"] = "Blue"
    failures += not run("wrong_tags", d, expect_pass=True, expect_score=86)

    # Missing all GC highlights: GC trip 0/3 → 0 pts, PC=4, NE=4 → C4=8, score=96
    d = _perfect()
    d["gc_highlights"] = []
    failures += not run("missing_gc_highlights", d, expect_pass=True, expect_score=96)

    # Cross-contamination: swap GC/PC files → C2 only NE correct (16 pts) → total 68 < 70
    d = _perfect()
    d["gc_files"] = sorted(PC_FILES)
    d["pc_files"] = sorted(GC_FILES)
    failures += not run("cross_contamination", d, expect_pass=False, expect_score=68)

    if failures:
        print(f"\n{failures} test(s) FAILED")
        sys.exit(1)
    else:
        print("\nAll tests passed.")


if __name__ == "__main__":
    main()
