#!/bin/bash
echo "=== Exporting Senate Polarization Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
CSV_PATH="/home/ga/RProjects/output/senate_ideal_points.csv"
PLOT_PATH="/home/ga/RProjects/output/polarization_map.png"
SCRIPT_PATH="/home/ga/RProjects/senate_analysis.R"

# 1. Check CSV Output
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ROWS=0
CSV_CONTENT_JSON="[]"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi
    CSV_ROWS=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
    
    # Extract CSV content to JSON for verification on host
    # using python to safely parse CSV and output JSON
    CSV_CONTENT_JSON=$(python3 -c "
import csv, json
data = []
try:
    with open('$CSV_PATH', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # clean keys
            clean_row = {k.strip().lower(): v.strip() for k, v in row.items() if k}
            data.append(clean_row)
except Exception:
    pass
print(json.dumps(data))
" 2>/dev/null || echo "[]")
fi

# 2. Check Plot Output
PLOT_EXISTS="false"
PLOT_IS_NEW="false"
PLOT_SIZE_BYTES=0

if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$PLOT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        PLOT_IS_NEW="true"
    fi
    PLOT_SIZE_BYTES=$(stat -c %s "$PLOT_PATH" 2>/dev/null || echo "0")
fi

# 3. Check Script
SCRIPT_MODIFIED="false"
HAS_SCALING_CODE="false"

if [ -f "$SCRIPT_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
    
    # Check for keywords indicating scaling analysis
    CONTENT=$(cat "$SCRIPT_PATH" | tr '[:upper:]' '[:lower:]')
    if echo "$CONTENT" | grep -qE "wnominate|prcomp|princomp|svd|cmdscale|ideal|rollcall"; then
        HAS_SCALING_CODE="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_rows": $CSV_ROWS,
    "csv_data": $CSV_CONTENT_JSON,
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_bytes": $PLOT_SIZE_BYTES,
    "script_modified": $SCRIPT_MODIFIED,
    "has_scaling_code": $HAS_SCALING_CODE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe copy to output
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"