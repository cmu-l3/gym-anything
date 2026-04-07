#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Debug Software Rasterizer Result ==="

WORKSPACE_DIR="/home/ga/workspace/tiny_rasterizer"
RESULT_FILE="/tmp/rasterizer_result.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Re-run render to ensure output.png is up to date
echo "Re-running render.py..."
sudo -u ga python3 "$WORKSPACE_DIR/render.py" || true

# Run the hidden test suite against the agent's code
echo "Running hidden mathematical test suite..."
sudo python3 /var/lib/app/ground_truth/test_math.py || true

# Gather output file info
OUTPUT_PATH="$WORKSPACE_DIR/output.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_UPDATED="true"
    else
        FILE_UPDATED="false"
    fi
    OUTPUT_EXISTS="true"
else
    OUTPUT_EXISTS="false"
    FILE_UPDATED="false"
fi

# Bundle results into JSON
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"

# 1. Source files
files = {
    "geometry.py":   os.path.join(workspace, "geometry.py"),
    "camera.py":     os.path.join(workspace, "camera.py"),
    "rasterizer.py": os.path.join(workspace, "rasterizer.py")
}

result_dict = {
    "source_code": {},
    "file_stats": {
        "output_exists": ${OUTPUT_EXISTS},
        "output_updated": ${FILE_UPDATED}
    },
    "test_results": {}
}

for label, path in files.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result_dict["source_code"][label] = f.read()
    except Exception as e:
        result_dict["source_code"][label] = f"ERROR: {e}"

# 2. Hidden test results
try:
    with open('/tmp/test_results.json', 'r') as f:
        result_dict["test_results"] = json.load(f)
except Exception as e:
    result_dict["test_results"] = {"error": str(e)}

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result_dict, out, indent=2)
PYEXPORT

echo "=== Export Complete ==="