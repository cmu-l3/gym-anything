#!/bin/bash
echo "=== Exporting DNA Cell Cycle Analysis Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Fiji_Data/results/cell_cycle"

# Files to check
CSV_FILE="$RESULTS_DIR/measurements.csv"
HIST_FILE="$RESULTS_DIR/histogram.png"
REPORT_FILE="$RESULTS_DIR/g1_peak_report.txt"

# 1. Check CSV
CSV_EXISTS=false
CSV_ROWS=0
HAS_INTDEN=false
if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS=true
    CSV_ROWS=$(wc -l < "$CSV_FILE")
    if grep -q "IntegratedDen\|RawIntDen" "$CSV_FILE"; then
        HAS_INTDEN=true
    fi
fi

# 2. Check Histogram
HIST_EXISTS=false
if [ -f "$HIST_FILE" ]; then
    HIST_EXISTS=true
fi

# 3. Check Report & Extract Value
REPORT_EXISTS=false
REPORTED_VALUE=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    # Extract first number found in the file
    REPORTED_VALUE=$(grep -oE "[0-9]+(\.[0-9]+)?" "$REPORT_FILE" | head -n1 || echo "0")
fi

# 4. Get Ground Truth (Hidden)
GT_PEAK=0
if [ -f "/var/lib/ground_truth.json" ]; then
    GT_PEAK=$(python3 -c "import json; print(json.load(open('/var/lib/ground_truth.json')).get('g1_peak', 0))")
fi

# 5. Check timestamps
FILES_CREATED_DURING_TASK=false
if [ "$CSV_EXISTS" = true ]; then
    FILE_TIME=$(stat -c %Y "$CSV_FILE")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK=true
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "has_intden_column": $HAS_INTDEN,
    "histogram_exists": $HIST_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "reported_peak_value": $REPORTED_VALUE,
    "ground_truth_peak": $GT_PEAK,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Export complete."
cat /tmp/task_result.json