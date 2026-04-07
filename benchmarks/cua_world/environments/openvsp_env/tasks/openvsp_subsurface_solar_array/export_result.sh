#!/bin/bash
# Export script for openvsp_subsurface_solar_array
# Records file sizes, timestamps, and extracts the saved model XML content

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_subsurface_solar_array_result.json"
MODEL_PATH="/home/ga/Documents/OpenVSP/hale_uav_subsurfaces.vsp3"
CSV_PATH="/home/ga/Documents/OpenVSP/exports/hale_uav_degengeom.csv"

echo "=== Exporting result for openvsp_subsurface_solar_array ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Kill OpenVSP to release file locks
kill_openvsp

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if application was running
APP_RUNNING=$(pgrep -f "vsp" > /dev/null && echo "true" || echo "false")

python3 << PYEOF
import json, os

model_path = '$MODEL_PATH'
csv_path = '$CSV_PATH'
task_start = int('$TASK_START')
task_end = int('$TASK_END')

model_exists = os.path.isfile(model_path)
csv_exists = os.path.isfile(csv_path)

model_size = os.path.getsize(model_path) if model_exists else 0
csv_size = os.path.getsize(csv_path) if csv_exists else 0

model_mtime = int(os.path.getmtime(model_path)) if model_exists else 0
csv_mtime = int(os.path.getmtime(csv_path)) if csv_exists else 0

model_created_during_task = model_exists and (model_mtime >= task_start)
csv_created_during_task = csv_exists and (csv_mtime >= task_start)

# Read file contents for verifier analysis
model_content = ""
if model_exists:
    with open(model_path, 'r', errors='replace') as f:
        model_content = f.read()

csv_first_lines = ""
if csv_exists:
    with open(csv_path, 'r', errors='replace') as f:
        # read first 20 lines to verify headers
        lines = []
        for _ in range(20):
            line = f.readline()
            if not line: break
            lines.append(line)
        csv_first_lines = "".join(lines)

result = {
    'task_start': task_start,
    'task_end': task_end,
    'app_was_running': $APP_RUNNING,
    'model_exists': model_exists,
    'model_size': model_size,
    'model_created_during_task': model_created_during_task,
    'model_content': model_content,
    'csv_exists': csv_exists,
    'csv_size': csv_size,
    'csv_created_during_task': csv_created_during_task,
    'csv_first_lines': csv_first_lines
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result JSON saved to { '$RESULT_FILE' }")
print(f"Model exists: {model_exists}, CSV exists: {csv_exists}")
PYEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="