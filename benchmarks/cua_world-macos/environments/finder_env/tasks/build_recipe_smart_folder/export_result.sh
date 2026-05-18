#!/bin/bash
# post_task hook for build_recipe_smart_folder on Finder/macOS.
# Produces /tmp/build_recipe_smart_folder_result.json for the verifier.
set -u

echo "=== Exporting build_recipe_smart_folder results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

RESULT_JSON='{"task_start":0,"folders_exist":{},"files_by_folder":{},"tags_by_file":{},"smart_folder_exists":false,"smart_folder_content":"","export_error":"init"}'

RESULT_JSON=$(/usr/bin/python3 - "$TASK_START" << 'PYEOF'
import json, os, subprocess, re, sys

task_start = int(sys.argv[1])
home = os.path.expanduser("~")
recipes = os.path.join(home, "Documents", "Recipes")
smart_path = os.path.join(home, "Library", "Saved Searches", "My Recipes.savedSearch")
subfolders = ["Italian", "Asian", "Mexican", "Baking", "Other"]

def get_tags(path):
    try:
        out = subprocess.check_output(["mdls", "-name", "kMDItemUserTags", path],
                                      stderr=subprocess.DEVNULL, text=True)
        return [t.strip() for t in re.findall(r'"([^"]+)"', out)]
    except Exception:
        return []

try:
    result = {
        "task_start": task_start,
        "folders_exist": {sf: os.path.isdir(os.path.join(recipes, sf)) for sf in subfolders},
        "files_by_folder": {},
        "tags_by_file": {},
        "smart_folder_exists": os.path.isfile(smart_path),
        "smart_folder_content": "",
    }
    for sf in subfolders:
        folder = os.path.join(recipes, sf)
        if os.path.isdir(folder):
            files = sorted(f for f in os.listdir(folder) if f.endswith(".txt"))
            result["files_by_folder"][sf] = files
            for fn in files:
                result["tags_by_file"][fn] = get_tags(os.path.join(folder, fn))
        else:
            result["files_by_folder"][sf] = []
    if result["smart_folder_exists"]:
        try:
            with open(smart_path, "rb") as f:
                result["smart_folder_content"] = f.read().hex()
        except Exception:
            pass
except Exception as exc:
    result = {"export_error": f"{type(exc).__name__}: {exc}", "task_start": task_start}

print(json.dumps(result, indent=2))
PYEOF
)

echo "$RESULT_JSON" > /tmp/build_recipe_smart_folder_result.json
echo "$RESULT_JSON"

echo "=== Export complete ==="
