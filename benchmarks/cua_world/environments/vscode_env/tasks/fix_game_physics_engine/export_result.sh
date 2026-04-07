#!/bin/bash
echo "=== Exporting Physics Engine Result ==="

source /workspace/scripts/task_utils.sh

WORKSPACE_DIR="/home/ga/workspace/physics_engine"
RESULT_FILE="/tmp/physics_engine_result.json"

# Take final screenshot BEFORE doing automated exports
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus VSCode and save all open files safely
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Remove stale result
rm -f "$RESULT_FILE"

# Collect all files into a JSON structure
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"
files_to_export = [
    "engine/vector2d.py",
    "engine/rigid_body.py",
    "engine/integrator.py",
    "engine/collision.py",
    "engine/resolver.py"
]

result = {}
for rel_path in files_to_export:
    full_path = os.path.join(workspace, rel_path)
    try:
        with open(full_path, "r", encoding="utf-8") as f:
            result[rel_path] = f.read()
    except FileNotFoundError:
        result[rel_path] = "ERROR: File Not Found"
    except Exception as e:
        result[rel_path] = f"ERROR: {e}"

# Also run tests and capture output
import subprocess
try:
    test_run = subprocess.run(
        ["python3", "run_tests.py"],
        cwd=workspace,
        capture_output=True,
        text=True,
        timeout=10
    )
    result["test_output"] = test_run.stderr + "\n" + test_run.stdout
    result["tests_passed"] = (test_run.returncode == 0)
except Exception as e:
    result["test_output"] = f"ERROR running tests: {e}"
    result["tests_passed"] = False

# Capture modification times
result["mtimes"] = {}
for rel_path in files_to_export:
    full_path = os.path.join(workspace, rel_path)
    if os.path.exists(full_path):
        result["mtimes"][rel_path] = os.path.getmtime(full_path)

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported data to $RESULT_FILE")
PYEXPORT

chmod 666 "$RESULT_FILE"

echo "=== Export Complete ==="