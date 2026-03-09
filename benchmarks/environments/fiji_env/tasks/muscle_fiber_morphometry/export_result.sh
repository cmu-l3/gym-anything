#!/bin/bash
echo "=== Exporting Muscle Fiber Morphometry Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Setup Variables
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Fiji_Data/results/muscle"
CSV_FILE="$RESULTS_DIR/results.csv"
IMG_FILE="$RESULTS_DIR/segmentation_check.png"
REPORT_FILE="$RESULTS_DIR/report.txt"
JSON_OUT="/tmp/muscle_result.json"

# 3. Analyze CSV (Measurements)
CSV_EXISTS="false"
ROW_COUNT=0
MEAN_AREA=0
if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    # Count data rows (excluding header)
    ROW_COUNT=$(tail -n +2 "$CSV_FILE" | wc -l)
    
    # Calculate Mean Area from CSV using python
    # We look for a column named 'Area' (case insensitive)
    MEAN_AREA=$(python3 -c "
import pandas as pd
import sys
try:
    df = pd.read_csv('$CSV_FILE')
    # Find area column
    area_col = next((c for c in df.columns if 'area' in c.lower()), None)
    if area_col:
        print(df[area_col].mean())
    else:
        print('0')
except:
    print('0')
")
fi

# 4. Analyze Report
REPORT_EXISTS="false"
REPORT_VAL=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Extract the first number found in the report
    REPORT_VAL=$(grep -oE "[0-9]+(\.[0-9]+)?" "$REPORT_FILE" | head -1 || echo "0")
fi

# 5. Analyze Visualization
IMG_EXISTS="false"
if [ -f "$IMG_FILE" ]; then
    IMG_EXISTS="true"
fi

# 6. Check Timestamps (Anti-Gaming)
FILES_NEW="false"
if [ "$CSV_EXISTS" = "true" ]; then
    F_TIME=$(stat -c %Y "$CSV_FILE")
    if [ "$F_TIME" -gt "$TASK_START" ]; then
        FILES_NEW="true"
    fi
fi

# 7. Generate JSON
cat > "$JSON_OUT" <<EOF
{
    "csv_exists": $CSV_EXISTS,
    "img_exists": $IMG_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "files_created_during_task": $FILES_NEW,
    "fiber_count": $ROW_COUNT,
    "csv_mean_area": ${MEAN_AREA:-0},
    "report_value": ${REPORT_VAL:-0},
    "task_start": $TASK_START
}
EOF

# 8. Set permissions for verify script to read
chmod 644 "$JSON_OUT"

echo "Export complete. Summary:"
cat "$JSON_OUT"