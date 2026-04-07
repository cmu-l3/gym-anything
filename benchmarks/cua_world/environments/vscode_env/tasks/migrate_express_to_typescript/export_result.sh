#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Express API to TypeScript Migration Result ==="

WORKSPACE_DIR="/home/ga/workspace/bookshelf-api"
RESULT_FILE="/tmp/migration_result.json"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1

echo "Saving all files..."
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Remove any stale result file
rm -f "$RESULT_FILE"

# Collect project state and run TypeScript compiler
python3 << PYEXPORT
import json
import os
import subprocess

workspace = "$WORKSPACE_DIR"
task_start = $TASK_START
task_end = $TASK_END

result = {
    "task_start": task_start,
    "task_end": task_end,
    "tsc_exit_code": -1,
    "tsc_output": "",
    "js_file_count": 0,
    "ts_file_count": 0,
    "tsconfig": None,
    "package_json": None,
    "source_files": {}
}

# 1. Count JS and TS files
src_dir = os.path.join(workspace, "src")
js_files = []
ts_files = []

if os.path.exists(src_dir):
    for root, dirs, files in os.walk(src_dir):
        for f in files:
            if f.endswith('.js'):
                js_files.append(os.path.join(root, f))
            elif f.endswith('.ts') and not f.endswith('.d.ts'):
                ts_files.append(os.path.join(root, f))

result["js_file_count"] = len(js_files)
result["ts_file_count"] = len(ts_files)

# 2. Extract contents of TS files
for ts_file in ts_files:
    rel_path = os.path.relpath(ts_file, workspace)
    try:
        with open(ts_file, 'r', encoding='utf-8') as f:
            content = f.read()
            # Also check modified time to prevent gaming
            mtime = os.path.getmtime(ts_file)
            result["source_files"][rel_path] = {
                "content": content,
                "modified_during_task": mtime > task_start
            }
    except Exception as e:
        result["source_files"][rel_path] = {"error": str(e)}

# 3. Parse config files
for config in ["tsconfig.json", "package.json"]:
    path = os.path.join(workspace, config)
    if os.path.exists(path):
        try:
            with open(path, 'r', encoding='utf-8') as f:
                # Store raw text as some tsconfigs have comments and aren't pure JSON
                content = f.read()
                key = config.replace(".", "_")
                result[key] = content
        except Exception as e:
            result[config.replace(".", "_")] = f"ERROR: {str(e)}"

# 4. Run TypeScript Compiler (npx tsc --noEmit)
# We run this in the workspace context using the local TS version if installed
try:
    process = subprocess.run(
        ["npx", "tsc", "--noEmit"],
        cwd=workspace,
        capture_output=True,
        text=True,
        timeout=30
    )
    result["tsc_exit_code"] = process.returncode
    result["tsc_output"] = process.stdout + "\n" + process.stderr
except Exception as e:
    result["tsc_output"] = f"Failed to run tsc: {str(e)}"

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported compilation state to $RESULT_FILE")
PYEXPORT

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

echo "=== Export Complete ==="