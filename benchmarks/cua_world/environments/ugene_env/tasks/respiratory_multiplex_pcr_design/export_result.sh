#!/bin/bash
echo "=== Exporting Respiratory Multiplex PCR Design task results ==="

# Record task end
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/multiplex/results"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Check UGENE status
UGENE_RUNNING="false"
if pgrep -f "ugene" > /dev/null; then
    UGENE_RUNNING="true"
fi

# Check GenBank Files
GB_FLUA_EXISTS="false"
GB_FLUB_EXISTS="false"
GB_RSV_EXISTS="false"

if [ -s "${RESULTS_DIR}/fluA_annotated.gb" ]; then
    GB_FLUA_EXISTS="true"
    cp "${RESULTS_DIR}/fluA_annotated.gb" /tmp/fluA_annotated.gb
    chmod 666 /tmp/fluA_annotated.gb
fi

if [ -s "${RESULTS_DIR}/fluB_annotated.gb" ]; then
    GB_FLUB_EXISTS="true"
    cp "${RESULTS_DIR}/fluB_annotated.gb" /tmp/fluB_annotated.gb
    chmod 666 /tmp/fluB_annotated.gb
fi

if [ -s "${RESULTS_DIR}/rsv_annotated.gb" ]; then
    GB_RSV_EXISTS="true"
    cp "${RESULTS_DIR}/rsv_annotated.gb" /tmp/rsv_annotated.gb
    chmod 666 /tmp/rsv_annotated.gb
fi

# Check CSV file
CSV_EXISTS="false"
CSV_MODIFIED_DURING_TASK="false"
if [ -s "${RESULTS_DIR}/multiplex_panel.csv" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "${RESULTS_DIR}/multiplex_panel.csv" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        CSV_MODIFIED_DURING_TASK="true"
    fi
    cp "${RESULTS_DIR}/multiplex_panel.csv" /tmp/multiplex_panel.csv
    chmod 666 /tmp/multiplex_panel.csv
fi

# Build result JSON directly
TEMP_JSON=$(mktemp /tmp/pcr_task_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "ugene_running": $UGENE_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_modified_during_task": $CSV_MODIFIED_DURING_TASK,
    "gb_flua_exists": $GB_FLUA_EXISTS,
    "gb_flub_exists": $GB_FLUB_EXISTS,
    "gb_rsv_exists": $GB_RSV_EXISTS
}
EOF

# Move and fix permissions
cp "$TEMP_JSON" /tmp/pcr_task_result.json
chmod 666 /tmp/pcr_task_result.json
rm -f "$TEMP_JSON"

echo "Results exported successfully to /tmp/pcr_task_result.json"
cat /tmp/pcr_task_result.json