#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Sensor Fusion Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/sensor_fusion"
RESULT_FILE="/tmp/sensor_fusion_result.json"

# Focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Remove stale result
rm -f "$RESULT_FILE"

# Collect all files and test results
python3 << PYEXPORT
import json, os, subprocess

workspace = "$WORKSPACE_DIR"

files_to_export = {
    "filters/kalman_filter.py":           os.path.join(workspace, "filters", "kalman_filter.py"),
    "sensors/imu_processor.py":           os.path.join(workspace, "sensors", "imu_processor.py"),
    "transforms/coordinate_transform.py": os.path.join(workspace, "transforms", "coordinate_transform.py"),
    "fusion/sensor_fusion.py":            os.path.join(workspace, "fusion", "sensor_fusion.py"),
    "fusion/time_synchronizer.py":        os.path.join(workspace, "fusion", "time_synchronizer.py"),
}

result = {}
for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result[label] = f.read()
    except Exception as e:
        result[label] = f"ERROR: {e}"

# Run pytest to capture output (as secondary evidence)
try:
    test_out = subprocess.run(
        ["python3", "-m", "pytest", "tests/test_pipeline.py"],
        cwd=workspace,
        capture_output=True,
        text=True,
        timeout=10
    )
    result["pytest_stdout"] = test_out.stdout
    result["pytest_stderr"] = test_out.stderr
except Exception as e:
    result["pytest_stdout"] = f"ERROR running tests: {e}"

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported files to $RESULT_FILE")
PYEXPORT

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "=== Export Complete ==="