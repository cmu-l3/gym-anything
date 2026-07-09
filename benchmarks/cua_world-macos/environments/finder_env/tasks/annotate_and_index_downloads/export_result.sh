#!/bin/bash
# post_task hook for annotate_and_index_downloads on Finder/macOS.
# Produces /tmp/annotate_and_index_downloads_result.json for the verifier.
set -u

echo "=== Exporting annotate_and_index_downloads results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

RESULT_JSON='{"task_start":0,"files_by_folder":{},"tags_by_file":{},"comments_by_file":{},"index_exists":false,"index_lines":[],"export_error":"init"}'

RESULT_JSON=$(/usr/bin/python3 - "$TASK_START" << 'PYEOF'
import json, os, subprocess, re, sys

task_start = int(sys.argv[1])
home = os.path.expanduser("~")
organized = os.path.join(home, "Documents", "Organized")
index_path = os.path.join(home, "Desktop", "File_Index.txt")
subfolders = ["Financial", "Photos", "Notes", "Media", "Other"]

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
        "files_by_folder": {},
        "tags_by_file": {},
        "comments_by_file": {},
        "index_exists": os.path.isfile(index_path),
        "index_lines": [],
    }
    for sf in subfolders:
        folder = os.path.join(organized, sf)
        if os.path.isdir(folder):
            files = sorted(f for f in os.listdir(folder) if not f.startswith("."))
            result["files_by_folder"][sf] = files
            for fn in files:
                fp = os.path.join(folder, fn)
                result["tags_by_file"][fn] = get_tags(fp)
                result["comments_by_file"][fn] = get_comment(fp)
        else:
            result["files_by_folder"][sf] = []
    if result["index_exists"]:
        with open(index_path, "r", errors="replace") as f:
            result["index_lines"] = [ln.rstrip("\n") for ln in f.readlines()]
except Exception as exc:
    result = {"export_error": f"{type(exc).__name__}: {exc}", "task_start": task_start}

print(json.dumps(result, indent=2))
PYEOF
)

echo "$RESULT_JSON" > /tmp/annotate_and_index_downloads_result.json
echo "$RESULT_JSON"

echo "=== Export complete ==="
