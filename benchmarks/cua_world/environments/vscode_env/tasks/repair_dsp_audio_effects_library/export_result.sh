#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting DSP Audio Effects Library Result ==="

WORKSPACE_DIR="/home/ga/workspace/audio_dsp"
RESULT_FILE="/tmp/dsp_task_result.json"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

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

# Collect all relevant source files into a single JSON dict
python3 << PYEXPORT
import json
import os
import stat

workspace = "$WORKSPACE_DIR"

files_to_export = {
    "dsp/core.py":                 os.path.join(workspace, "dsp", "core.py"),
    "dsp/effects/delay.py":        os.path.join(workspace, "dsp", "effects", "delay.py"),
    "dsp/effects/distortion.py":   os.path.join(workspace, "dsp", "effects", "distortion.py"),
    "dsp/effects/chorus.py":       os.path.join(workspace, "dsp", "effects", "chorus.py"),
    "tests/test_dsp.py":           os.path.join(workspace, "tests", "test_dsp.py")
}

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {}
}

for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
            mtime = os.stat(path).st_mtime
            result["files"][label] = {
                "content": content,
                "modified_during_task": mtime > $TASK_START
            }
    except FileNotFoundError:
        result["files"][label] = {"content": None, "modified_during_task": False}
        print(f"Warning: {path} not found")
    except Exception as e:
        result["files"][label] = {"content": None, "modified_during_task": False}
        print(f"Warning: error reading {path}: {e}")

# Run tests to check if agent fully succeeded
import subprocess
try:
    test_run = subprocess.run(
        ["python3", "-m", "unittest", "discover", "-s", os.path.join(workspace, "tests")],
        capture_output=True, text=True
    )
    result["test_output"] = test_run.stderr + "\n" + test_run.stdout
    result["tests_passed"] = test_run.returncode == 0
except Exception as e:
    result["test_output"] = str(e)
    result["tests_passed"] = False

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported files to $RESULT_FILE")
PYEXPORT

echo "=== Export Complete ==="