#!/bin/bash
# post_task hook for archive_completed_projects on Finder/macOS.
# Produces /tmp/archive_completed_projects_result.json for the verifier.
set -u

echo "=== Exporting archive_completed_projects results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

RESULT_JSON='{"task_start":0,"active_folders_exist":{},"done_folders_exist":{},"active_tags":{},"archive_zips":[],"zip_comments":{},"export_error":"init"}'

RESULT_JSON=$(/usr/bin/python3 - "$TASK_START" << 'PYEOF'
import json, os, subprocess, re, sys

task_start = int(sys.argv[1])
home = os.path.expanduser("~")
projects = os.path.join(home, "Documents", "Projects")
archive = os.path.join(home, "Documents", "Archive")

active = ["HomeRenovation", "LearnPiano"]
done = ["VegetableGarden", "BookClub2024", "CookingChallenge"]

def get_tags(path):
    try:
        out = subprocess.check_output(["mdls", "-name", "kMDItemUserTags", path],
                                      stderr=subprocess.DEVNULL, text=True)
        return [t.strip() for t in re.findall(r'"([^"]+)"', out)]
    except Exception:
        return []

def get_comment(path):
    try:
        out = subprocess.check_output(
            ["osascript", "-e",
             f'tell application "Finder" to get comment of (POSIX file "{path}") as string'],
            stderr=subprocess.DEVNULL, text=True)
        return out.strip()
    except Exception:
        return ""

try:
    result = {
        "task_start": task_start,
        "active_folders_exist": {},
        "done_folders_exist": {},
        "active_tags": {},
        "archive_zips": [],
        "zip_comments": {},
    }
    for name in active:
        path = os.path.join(projects, name)
        exists = os.path.isdir(path)
        result["active_folders_exist"][name] = exists
        result["active_tags"][name] = get_tags(path) if exists else []
    for name in done:
        result["done_folders_exist"][name] = os.path.isdir(os.path.join(projects, name))
    if os.path.isdir(archive):
        zips = sorted(f for f in os.listdir(archive) if f.endswith(".zip"))
        result["archive_zips"] = zips
        for z in zips:
            result["zip_comments"][z] = get_comment(os.path.join(archive, z))
except Exception as exc:
    result = {"export_error": f"{type(exc).__name__}: {exc}", "task_start": task_start}

print(json.dumps(result, indent=2))
PYEOF
)

echo "$RESULT_JSON" > /tmp/archive_completed_projects_result.json
echo "$RESULT_JSON"

echo "=== Export complete ==="
