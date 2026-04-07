#!/bin/bash
set -e

echo "=== Exporting Telescope Drift Measurement Result ==="

# Record task end state
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

MEASURE_DIR="/home/ga/AstroImages/measurements"
REPORT_FILE="$MEASURE_DIR/tracking_drift_report.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if AIJ is running
APP_RUNNING=$(pgrep -f "astroimagej\|aij\|AstroImageJ" > /dev/null && echo "true" || echo "false")

# Python script to safely parse outputs and generate result JSON
cat > /tmp/generate_result.py << 'PYEOF'
import os
import glob
import json

measure_dir = "/home/ga/AstroImages/measurements"
report_file = os.path.join(measure_dir, "tracking_drift_report.txt")
task_start = int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0

result = {
    "app_running": os.system("pgrep -f 'astroimagej\|aij\|AstroImageJ' > /dev/null") == 0,
    "measurement_file_exists": False,
    "measurement_file_name": None,
    "report_exists": False,
    "report_content": ""
}

# Check for any measurement file (CSV, XLS, TXT, TBL) in the measurements directory
meas_files = []
for ext in ["csv", "xls", "txt", "tbl"]:
    meas_files.extend(glob.glob(os.path.join(measure_dir, f"*.{ext}")))

# Exclude the report file itself
meas_files = [f for f in meas_files if "tracking_drift_report" not in f.lower()]

if meas_files:
    result["measurement_file_exists"] = True
    result["measurement_file_name"] = os.path.basename(meas_files[0])

# Check and read the report file
if os.path.exists(report_file):
    result["report_exists"] = True
    with open(report_file, "r") as f:
        result["report_content"] = f.read()

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

python3 /tmp/generate_result.py

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="