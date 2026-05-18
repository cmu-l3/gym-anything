#!/bin/bash
# post_task hook for curate_vacation_photo_album on Finder/macOS.
# Produces /tmp/curate_vacation_photo_album_result.json for the verifier.
set -u   # NOT set -e — emit valid JSON even on partial failure.

echo "=== Exporting curate_vacation_photo_album results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

RESULT_JSON='{"task_start":0,"gc_folder_exists":false,"pc_folder_exists":false,"ne_folder_exists":false,"gc_files":[],"pc_files":[],"ne_files":[],"gc_highlights":[],"pc_highlights":[],"ne_highlights":[],"gc_tag":"","pc_tag":"","ne_tag":"","gc_comment":"","pc_comment":"","ne_comment":"","export_error":"init"}'

RESULT_JSON=$(/usr/bin/python3 - "$TASK_START" << 'PYEOF'
import json, os, subprocess, re, sys

task_start = int(sys.argv[1])
home = os.path.expanduser("~")
pics = os.path.join(home, "Pictures", "Family Trips")

GC = os.path.join(pics, "Grand Canyon 2019")
PC = os.path.join(pics, "Pacific Coast 2021")
NE = os.path.join(pics, "New England 2023")

def list_jpgs(d):
    if not os.path.isdir(d):
        return []
    return sorted(f for f in os.listdir(d) if f.endswith(".jpg") and os.path.isfile(os.path.join(d, f)))

def get_tags(path):
    try:
        out = subprocess.check_output(["mdls", "-name", "kMDItemUserTags", path],
                                      stderr=subprocess.DEVNULL, text=True)
        return ",".join(re.findall(r'"([^"]+)"', out))
    except Exception:
        return ""

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
        "gc_folder_exists": os.path.isdir(GC),
        "pc_folder_exists": os.path.isdir(PC),
        "ne_folder_exists": os.path.isdir(NE),
        "gc_files":       list_jpgs(GC),
        "pc_files":       list_jpgs(PC),
        "ne_files":       list_jpgs(NE),
        "gc_highlights":  list_jpgs(os.path.join(GC, "Highlights")),
        "pc_highlights":  list_jpgs(os.path.join(PC, "Highlights")),
        "ne_highlights":  list_jpgs(os.path.join(NE, "Highlights")),
        "gc_tag":         get_tags(GC),
        "pc_tag":         get_tags(PC),
        "ne_tag":         get_tags(NE),
        "gc_comment":     get_comment(GC),
        "pc_comment":     get_comment(PC),
        "ne_comment":     get_comment(NE),
    }
except Exception as exc:
    result = {"export_error": f"{type(exc).__name__}: {exc}", "task_start": task_start}

print(json.dumps(result, indent=2))
PYEOF
)

echo "$RESULT_JSON" > /tmp/curate_vacation_photo_album_result.json
echo "$RESULT_JSON"

echo "=== Export complete ==="
