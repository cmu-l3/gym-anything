#!/bin/bash
echo "=== Exporting Leaf Vein Skeleton Analysis Result ==="

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Fiji_Data/results/skeleton"

# Output files
SKEL_IMG="$RESULTS_DIR/leaf_skeleton.png"
OVERLAY_IMG="$RESULTS_DIR/skeleton_overlay.png"
CSV_FILE="$RESULTS_DIR/network_topology.csv"
REPORT_FILE="$RESULTS_DIR/analysis_report.txt"

# Helper to check file status
check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "{\"exists\": true, \"modified_during_task\": true, \"size\": $size}"
        else
            echo "{\"exists\": true, \"modified_during_task\": false, \"size\": $size}"
        fi
    else
        echo "{\"exists\": false, \"modified_during_task\": false, \"size\": 0}"
    fi
}

# Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Parse CSV content using Python (to be robust against formatting)
# We want to know if there are valid data rows
CSV_ANALYSIS=$(python3 -c "
import csv
import sys
import json
try:
    with open('$CSV_FILE', 'r') as f:
        # read first few lines to detect header vs data
        content = f.read()
        lines = [l for l in content.splitlines() if l.strip()]
        if len(lines) < 2:
            print(json.dumps({'valid_rows': 0, 'columns': []}))
            sys.exit(0)
        
        # Simple header check
        header = lines[0].lower()
        cols = [c.strip() for c in header.split(',')]
        
        # Check for keywords
        has_branch = any('branch' in c for c in cols)
        has_junc = any('junction' in c for c in cols)
        
        print(json.dumps({
            'valid_rows': len(lines) - 1,
            'columns': cols,
            'has_branch_col': has_branch,
            'has_junction_col': has_junc
        }))
except Exception:
    print(json.dumps({'valid_rows': 0, 'columns': [], 'error': 'parse_failed'}))
")

# Check Report Content
REPORT_CONTENT_CHECK="false"
if [ -f "$REPORT_FILE" ]; then
    # Case insensitive grep for keywords
    if grep -qi "branch" "$REPORT_FILE" && grep -qi "um" "$REPORT_FILE"; then
        REPORT_CONTENT_CHECK="true"
    fi
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/skeleton_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "skeleton_image": $(check_file "$SKEL_IMG"),
    "overlay_image": $(check_file "$OVERLAY_IMG"),
    "csv_file": $(check_file "$CSV_FILE"),
    "report_file": $(check_file "$REPORT_FILE"),
    "csv_analysis": $CSV_ANALYSIS,
    "report_content_valid": $REPORT_CONTENT_CHECK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json