#!/bin/bash
echo "=== Exporting MRI Reslice Results ==="

# Define paths
RESULTS_DIR="/home/ga/Fiji_Data/results/reslice"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper function to get file info
get_file_info() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during_task}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false}"
    fi
}

# Collect info for all expected files
CORONAL_STACK=$(get_file_info "$RESULTS_DIR/coronal_stack.tif")
SAGITTAL_STACK=$(get_file_info "$RESULTS_DIR/sagittal_stack.tif")
AXIAL_PROFILE=$(get_file_info "$RESULTS_DIR/axial_profile.csv")
CORONAL_PROFILE=$(get_file_info "$RESULTS_DIR/coronal_profile.csv")
MONTAGE=$(get_file_info "$RESULTS_DIR/orthogonal_montage.png")
REPORT=$(get_file_info "$RESULTS_DIR/measurement_report.txt")

# Read report content if it exists
REPORT_CONTENT=""
if [ -f "$RESULTS_DIR/measurement_report.txt" ]; then
    # Read first 1KB safely, escape quotes for JSON
    REPORT_CONTENT=$(head -c 1024 "$RESULTS_DIR/measurement_report.txt" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
else
    REPORT_CONTENT="\"\""
fi

# Build JSON result
# We use Python to analyze the CSV files slightly (row count) to ensure they aren't empty
PYTHON_ANALYSIS=$(python3 -c "
import os
import csv
import json

def analyze_csv(path):
    if not os.path.exists(path): return 0, 0
    try:
        with open(path, 'r') as f:
            lines = f.readlines()
            return len(lines), 1 # Validish
    except:
        return 0, 0

ax_rows, _ = analyze_csv('$RESULTS_DIR/axial_profile.csv')
cor_rows, _ = analyze_csv('$RESULTS_DIR/coronal_profile.csv')

print(json.dumps({
    'axial_profile_rows': ax_rows,
    'coronal_profile_rows': cor_rows
}))
")

# Create the final JSON structure
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "coronal_stack": $CORONAL_STACK,
        "sagittal_stack": $SAGITTAL_STACK,
        "axial_profile": $AXIAL_PROFILE,
        "coronal_profile": $CORONAL_PROFILE,
        "montage": $MONTAGE,
        "report": $REPORT
    },
    "report_content": $REPORT_CONTENT,
    "csv_analysis": $PYTHON_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"