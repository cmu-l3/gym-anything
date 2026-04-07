#!/bin/bash
echo "=== Exporting tb_katg_locus_extraction task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

GB_FILE="/home/ga/UGENE_Data/tb_resistance_panel/katG_locus.gb"
REPORT_FILE="/home/ga/UGENE_Data/tb_resistance_panel/extraction_report.txt"

# Initialize variables
GB_EXISTS="false"
GB_CREATED_DURING_TASK="false"
GB_SIZE=0

REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE=0

# Check GenBank file
if [ -f "$GB_FILE" ]; then
    GB_EXISTS="true"
    GB_SIZE=$(stat -c %s "$GB_FILE" 2>/dev/null || echo "0")
    GB_MTIME=$(stat -c %Y "$GB_FILE" 2>/dev/null || echo "0")
    if [ "$GB_MTIME" -ge "$TASK_START" ]; then
        GB_CREATED_DURING_TASK="true"
    fi
    # Copy to /tmp for verifier access
    cp "$GB_FILE" /tmp/katG_locus.gb
    chmod 666 /tmp/katG_locus.gb
fi

# Check Report file
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Copy to /tmp for verifier access
    cp "$REPORT_FILE" /tmp/extraction_report.txt
    chmod 666 /tmp/extraction_report.txt
fi

# Check if UGENE was running
UGENE_RUNNING=$(pgrep -f "ugene" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gb_exists": $GB_EXISTS,
    "gb_created_during_task": $GB_CREATED_DURING_TASK,
    "gb_size_bytes": $GB_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "ugene_running": $UGENE_RUNNING
}
EOF

# Move to final location safely
rm -f /tmp/katg_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/katg_task_result.json
chmod 666 /tmp/katg_task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/katg_task_result.json"
echo "=== Export complete ==="