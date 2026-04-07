#!/bin/bash
set -e

echo "=== Exporting Epidemiological Surveillance Workspace Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill local server
if [ -f /tmp/epi_server_pid ]; then
    kill $(cat /tmp/epi_server_pid) 2>/dev/null || true
fi

# 3. Gracefully close Chrome to flush Preferences and Local State
echo "Closing Chrome to flush data to disk..."
pkill -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# 4. Check Downloaded Files
DIR="/home/ga/Documents/Surveillance_Data"
F1_EXISTS="false"
F2_EXISTS="false"
F1_CREATED="false"
F2_CREATED="false"

if [ -f "$DIR/linelist_anonymized.csv" ]; then
    F1_EXISTS="true"
    MTIME=$(stat -c %Y "$DIR/linelist_anonymized.csv")
    if [ "$MTIME" -ge "$TASK_START" ]; then F1_CREATED="true"; fi
fi

if [ -f "$DIR/case_definitions_2026.pdf" ]; then
    F2_EXISTS="true"
    MTIME=$(stat -c %Y "$DIR/case_definitions_2026.pdf")
    if [ "$MTIME" -ge "$TASK_START" ]; then F2_CREATED="true"; fi
fi

# 5. Export JSON
TEMP_JSON=$(mktemp /tmp/epi_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "downloads": {
        "linelist_exists": $F1_EXISTS,
        "linelist_created_during_task": $F1_CREATED,
        "pdf_exists": $F2_EXISTS,
        "pdf_created_during_task": $F2_CREATED
    }
}
EOF

mv "$TEMP_JSON" /tmp/epi_task_result.json
chmod 666 /tmp/epi_task_result.json

echo "Export complete. Results saved to /tmp/epi_task_result.json"