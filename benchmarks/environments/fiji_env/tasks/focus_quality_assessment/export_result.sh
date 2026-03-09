#!/bin/bash
echo "=== Exporting Focus Quality Assessment Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
RESULTS_DIR="/home/ga/Fiji_Data/results/focus_qc"
CSV_PATH="$RESULTS_DIR/focus_metrics.csv"
SUMMARY_PATH="$RESULTS_DIR/qc_summary.txt"
IMG_PATH="$RESULTS_DIR/focus_comparison.png"
JSON_OUTPUT="/tmp/task_result.json"

# Helper to get file stats
get_file_info() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath")
        local mtime=$(stat -c %Y "$fpath")
        # Check if created/modified after task start
        local fresh="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            fresh="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"fresh\": $fresh}"
    else
        echo "{\"exists\": false, \"size\": 0, \"fresh\": false}"
    fi
}

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# Validate CSV content (Python)
# We do a quick parse here to check row count and basic validity, 
# but full statistical verification happens in verifier.py
CSV_STATS=$(python3 << EOF
import csv
import sys
import json
import os

path = "$CSV_PATH"
result = {"rows": 0, "cols": [], "valid_metrics": False}

if os.path.exists(path):
    try:
        with open(path, 'r') as f:
            reader = csv.DictReader(f)
            result["cols"] = reader.fieldnames if reader.fieldnames else []
            rows = list(reader)
            result["rows"] = len(rows)
            
            # Check if metrics look like numbers
            valid_count = 0
            for r in rows:
                try:
                    if float(r.get('laplacian_var', 0)) >= 0:
                        valid_count += 1
                except:
                    pass
            
            if len(rows) > 0 and valid_count == len(rows):
                result["valid_metrics"] = True
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
EOF
)

# Export result JSON
cat > "$JSON_OUTPUT" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_file": $(get_file_info "$CSV_PATH"),
    "summary_file": $(get_file_info "$SUMMARY_PATH"),
    "image_file": $(get_file_info "$IMG_PATH"),
    "csv_stats": $CSV_STATS,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Copy CSV to tmp for verifier to access easily via copy_from_env
if [ -f "$CSV_PATH" ]; then
    cp "$CSV_PATH" /tmp/focus_metrics_export.csv
    chmod 666 /tmp/focus_metrics_export.csv
fi

# Set permissions
chmod 666 "$JSON_OUTPUT"

echo "Export complete. Result saved to $JSON_OUTPUT"