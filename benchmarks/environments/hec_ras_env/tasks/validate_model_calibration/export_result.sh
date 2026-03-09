#!/bin/bash
echo "=== Exporting Validation Task Results ==="

# Source utility functions
source /workspace/scripts/task_utils.sh 2>/dev/null || true

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
ANALYSIS_CSV="$RESULTS_DIR/calibration_analysis.csv"
SUMMARY_TXT="$RESULTS_DIR/calibration_summary.txt"
PLOT_PNG="$RESULTS_DIR/calibration_plot.png"
GROUND_TRUTH="/var/lib/hec_ras/calibration_ground_truth.json"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false" # Exists but old
        fi
    else
        echo "false"
    fi
}

CSV_CREATED=$(check_file "$ANALYSIS_CSV")
TXT_CREATED=$(check_file "$SUMMARY_TXT")
PLOT_CREATED=$(check_file "$PLOT_PNG")

# 3. Read Content (if safe)
RMSE_REPORTED=""
if [ -f "$SUMMARY_TXT" ]; then
    # Extract just the number/line
    RMSE_REPORTED=$(head -n 1 "$SUMMARY_TXT")
fi

# 4. Prepare Export JSON
# We use Python to robustly create the JSON and include file contents
cat << EOF > /tmp/create_export.py
import json
import os
import shutil

result = {
    "csv_created": $CSV_CREATED,
    "txt_created": $TXT_CREATED,
    "plot_created": $PLOT_CREATED,
    "rmse_reported_text": """$RMSE_REPORTED""",
    "files": {}
}

# Copy files for verifier to inspect
export_dir = "/tmp/verifier_files"
os.makedirs(export_dir, exist_ok=True)

paths = {
    "analysis_csv": "$ANALYSIS_CSV",
    "ground_truth": "$GROUND_TRUTH"
}

for key, path in paths.items():
    if os.path.exists(path):
        dest = os.path.join(export_dir, os.path.basename(path))
        shutil.copy(path, dest)
        result["files"][key] = dest

# Save json
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

python3 /tmp/create_export.py

echo "Export complete. Result at /tmp/task_result.json"