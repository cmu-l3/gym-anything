#!/bin/bash
echo "=== Exporting Metallographic Phase Quantification Results ==="

# 1. Capture Task End State
# ----------------------------------------------------------------
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Outputs
# ----------------------------------------------------------------
RESULTS_DIR="/home/ga/Fiji_Data/results/metallurgy"
MASK_PATH="$RESULTS_DIR/pearlite_mask.png"
CSV_PATH="$RESULTS_DIR/phase_measurements.csv"
REPORT_PATH="$RESULTS_DIR/report.txt"
GT_FILE="/var/lib/app/ground_truth_fraction.txt"

# Check existence
MASK_EXISTS="false"
[ -f "$MASK_PATH" ] && MASK_EXISTS="true"

CSV_EXISTS="false"
[ -f "$CSV_PATH" ] && CSV_EXISTS="true"

REPORT_EXISTS="false"
[ -f "$REPORT_PATH" ] && REPORT_EXISTS="true"

# Check if modified during task
FILES_NEW="false"
if [ "$MASK_EXISTS" = "true" ]; then
    MTIME=$(stat -c %Y "$MASK_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILES_NEW="true"
    fi
fi

# 3. Read Values
# ----------------------------------------------------------------
REPORTED_VALUE="-1"
if [ "$REPORT_EXISTS" = "true" ]; then
    # Try to extract the number after "Pearlite_Fraction:"
    REPORTED_VALUE=$(grep "Pearlite_Fraction" "$REPORT_PATH" | sed 's/[^0-9.]//g')
    # If empty or invalid, try to find any float in the file
    if [ -z "$REPORTED_VALUE" ]; then
        REPORTED_VALUE=$(grep -oE "[0-9]+\.[0-9]+" "$REPORT_PATH" | head -1)
    fi
fi
[ -z "$REPORTED_VALUE" ] && REPORTED_VALUE="-1"

GT_VALUE=$(cat "$GT_FILE" 2>/dev/null || echo "-1")

# 4. Build JSON
# ----------------------------------------------------------------
JSON_FILE="/tmp/task_result.json"
cat > "$JSON_FILE" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "mask_exists": $MASK_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "files_created_during_task": $FILES_NEW,
    "mask_path": "$MASK_PATH",
    "reported_value": $REPORTED_VALUE,
    "ground_truth_value": $GT_VALUE
}
EOF

# Set permissions for verify script
chmod 644 "$JSON_FILE"
cp "$MASK_PATH" /tmp/result_mask.png 2>/dev/null || true
chmod 644 /tmp/result_mask.png 2>/dev/null || true

echo "Export complete. Result saved to $JSON_FILE"