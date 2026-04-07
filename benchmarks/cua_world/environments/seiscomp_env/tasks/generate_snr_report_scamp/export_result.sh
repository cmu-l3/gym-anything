#!/bin/bash
echo "=== Exporting generate_snr_report_scamp results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check for the expected report file
REPORT_PATH="/home/ga/snr_report.csv"
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Copy to tmp for the verifier to easily retrieve via copy_from_env
    cp "$REPORT_PATH" /tmp/snr_report.csv
    chmod 666 /tmp/snr_report.csv
fi

# Check if picks/amps were generated in files
XML_GENERATED="false"
if [ -f "/home/ga/picks.xml" ] || [ -f "/home/ga/amps.xml" ] || [ -f "/home/ga/picks.scml" ] || [ -f "/home/ga/amps.scml" ]; then
    XML_GENERATED="true"
fi

# Check if picks/amps were generated directly into the DB
CURRENT_PICK_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Pick" 2>/dev/null || echo "0")
CURRENT_AMP_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Amplitude" 2>/dev/null || echo "0")
INITIAL_PICK_COUNT=$(cat /tmp/initial_pick_count.txt 2>/dev/null || echo "0")

DB_GENERATED="false"
if [ "$CURRENT_PICK_COUNT" -gt "$INITIAL_PICK_COUNT" ]; then
    DB_GENERATED="true"
fi

# Write metadata JSON (use temp file to avoid permission issues)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "xml_generated": $XML_GENERATED,
    "db_generated": $DB_GENERATED,
    "initial_pick_count": $INITIAL_PICK_COUNT,
    "current_pick_count": $CURRENT_PICK_COUNT,
    "current_amp_count": $CURRENT_AMP_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="