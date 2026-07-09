"""Offline tests for build_recipe_smart_folder verifier (no live VM).

Run from repo root:
    python3 benchmarks/cua_world-macos/environments/finder_env/tasks/build_recipe_smart_folder/test_verifier_offline.py
"""
from __future__ import annotations

import importlib.util
import json
import plistlib
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("verifier", HERE / "verifier.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
verify = mod.verify_build_recipe_smart_folder

EXPECTED = mod.EXPECTED
SUBFOLDERS = mod.SUBFOLDERS


def _smart_folder_hex(raw_query: str = 'kMDItemUserTags == "Yellow"cd',
                      scopes: list | None = None) -> str:
    if scopes is None:
        scopes = ["/Users/lume/Documents/Recipes"]
    pl = {"RawQuery": raw_query, "SearchScopes": scopes, "CompatibleVersion": 1}
    return plistlib.dumps(pl).hex()


def _perfect() -> dict:
    files_by_folder: dict = {sf: [] for sf in SUBFOLDERS}
    tags_by_file: dict = {}
    for _orig, (folder, renamed) in EXPECTED.items():
        files_by_folder[folder].append(renamed)
        tags_by_file[renamed] = ["Yellow"]
    return {
        "folders_exist": {sf: True for sf in SUBFOLDERS},
        "files_by_folder": files_by_folder,
        "tags_by_file": tags_by_file,
        "smart_folder_exists": True,
        "smart_folder_content": _smart_folder_hex(),
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

    # Do nothing
    failures += not run("do_nothing", {
        "folders_exist": {sf: False for sf in SUBFOLDERS},
        "files_by_folder": {sf: [] for sf in SUBFOLDERS},
        "tags_by_file": {},
        "smart_folder_exists": False,
        "smart_folder_content": "",
    }, expect_pass=False, expect_score=0)

    # Missing smart folder (lose 10 pts)
    d = _perfect()
    d["smart_folder_exists"] = False
    d["smart_folder_content"] = ""
    failures += not run("missing_smart_folder", d, expect_pass=True, expect_score=90)

    # Wrong tag color (lose 20 pts)
    d = _perfect()
    for k in d["tags_by_file"]:
        d["tags_by_file"][k] = ["Red"]
    failures += not run("wrong_tag", d, expect_pass=True, expect_score=80)

    if failures:
        print(f"\n{failures} test(s) FAILED")
        sys.exit(1)
    else:
        print("\nAll tests passed.")


if __name__ == "__main__":
    main()
