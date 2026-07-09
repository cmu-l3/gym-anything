"""Offline tests for annotate_and_index_downloads verifier (no live VM).

Run from repo root:
    python3 benchmarks/cua_world-macos/environments/finder_env/tasks/annotate_and_index_downloads/test_verifier_offline.py
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
verify = mod.verify_annotate_and_index_downloads

EXPECTED = mod.EXPECTED
ALL_FILES = mod.ALL_FILES


def _perfect() -> dict:
    files_by_folder: dict = {}
    tags_by_file: dict = {}
    comments_by_file: dict = {}
    index_lines: list = []
    for fn, (folder, tag) in EXPECTED.items():
        files_by_folder.setdefault(folder, []).append(fn)
        tags_by_file[fn] = [tag]
        comment = f"This file contains important personal data about {fn.split('.')[0]}"
        comments_by_file[fn] = comment
        index_lines.append(f"{fn} | {folder} | {comment}")
    return {
        "files_by_folder": files_by_folder,
        "tags_by_file": tags_by_file,
        "comments_by_file": comments_by_file,
        "index_exists": True,
        "index_lines": index_lines,
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
        "files_by_folder": {"Financial": [], "Photos": [], "Notes": [], "Media": [], "Other": []},
        "tags_by_file": {},
        "comments_by_file": {},
        "index_exists": False,
        "index_lines": [],
    }, expect_pass=False, expect_score=0)

    # Missing index (lose 25 pts)
    d = _perfect()
    d["index_exists"] = False
    d["index_lines"] = []
    failures += not run("missing_index", d, expect_pass=True, expect_score=75)

    # Wrong tag color on all (lose 20 pts)
    d = _perfect()
    for fn in d["tags_by_file"]:
        d["tags_by_file"][fn] = ["Purple"]
    failures += not run("wrong_tags", d, expect_pass=True, expect_score=80)

    # Short comments on all (lose 25 pts)
    d = _perfect()
    for fn in d["comments_by_file"]:
        d["comments_by_file"][fn] = "Too short"
    failures += not run("short_comments", d, expect_pass=True, expect_score=75)

    # Wrong folder for Financial (lose 3*2=6 pts)
    d = _perfect()
    moved = d["files_by_folder"].pop("Financial")
    d["files_by_folder"]["Other"] = d["files_by_folder"].get("Other", []) + moved
    failures += not run("wrong_folder", d, expect_pass=True, expect_score=94)

    if failures:
        print(f"\n{failures} test(s) FAILED")
        sys.exit(1)
    else:
        print("\nAll tests passed.")


if __name__ == "__main__":
    main()
