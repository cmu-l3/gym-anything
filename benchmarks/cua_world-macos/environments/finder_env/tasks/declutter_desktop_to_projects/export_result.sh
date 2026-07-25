#!/bin/bash
# post_task hook for declutter_desktop_to_projects on Finder/macOS.
# Produces /tmp/declutter_desktop_to_projects_result.json for the verifier.
set -u

echo "=== Exporting declutter_desktop_to_projects results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

RESULT_JSON='{"task_start":0,"files_by_folder":{},"locked_by_file":{},"readme_by_folder":{},"desktop_leftover":[],"export_error":"init"}'

RESULT_JSON=$(/usr/bin/python3 - "$TASK_START" << 'PYEOF'
import json, os, stat, sys

task_start = int(sys.argv[1])
home = os.path.expanduser("~")
desktop = os.path.join(home, "Desktop")
projects = os.path.join(home, "Documents", "Projects")
folders = ["Home Renovation", "School Schedule", "Garden Design"]
UF_IMMUTABLE = 0x00020000

def is_locked(path):
    try:
        return bool(os.stat(path).st_flags & UF_IMMUTABLE)
    except Exception:
        return False

def read_readme(folder_path):
    readme = os.path.join(folder_path, "README.txt")
    if os.path.isfile(readme):
        try:
            with open(readme, "r", errors="replace") as f:
                return f.read()
        except Exception:
            return ""
    return None

try:
    result = {
        "task_start": task_start,
        "files_by_folder": {},
        "locked_by_file": {},
        "readme_by_folder": {},
        "desktop_leftover": [],
    }
    for folder in folders:
        fpath = os.path.join(projects, folder)
        if os.path.isdir(fpath):
            files = sorted(fn for fn in os.listdir(fpath)
                           if fn != "README.txt" and not fn.startswith("."))
            result["files_by_folder"][folder] = files
            for fn in files:
                fp = os.path.join(fpath, fn)
                result["locked_by_file"][fn] = is_locked(fp)
            result["readme_by_folder"][folder] = read_readme(fpath)
        else:
            result["files_by_folder"][folder] = []
            result["readme_by_folder"][folder] = None
    if os.path.isdir(desktop):
        result["desktop_leftover"] = sorted(
            fn for fn in os.listdir(desktop)
            if fn.startswith(("HV_", "SC_", "GD_"))
        )
except Exception as exc:
    result = {"export_error": f"{type(exc).__name__}: {exc}", "task_start": task_start}

print(json.dumps(result, indent=2))
PYEOF
)

echo "$RESULT_JSON" > /tmp/declutter_desktop_to_projects_result.json
echo "$RESULT_JSON"

echo "=== Export complete ==="
