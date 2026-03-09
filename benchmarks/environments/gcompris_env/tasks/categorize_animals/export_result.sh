#!/bin/bash
set -e
echo "=== Exporting Categorize Animals results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State (Critical for VLM)
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png

# 2. Check Application Status
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Check for Data Persistence/Progress
# GCompris often writes to sqlite or config files upon level completion
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DATA_MODIFIED="false"

# Check common data locations for GCompris-qt
for data_dir in "/home/ga/.local/share/GCompris" "/home/ga/.local/share/gcompris-qt"; do
    if [ -d "$data_dir" ]; then
        # Look for files modified after task start
        MODIFIED_COUNT=$(find "$data_dir" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
        if [ "$MODIFIED_COUNT" -gt "0" ]; then
            DATA_MODIFIED="true"
            echo "Found modified data in $data_dir"
            break
        fi
    fi
done

# 4. Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_running": $APP_RUNNING,
    "data_modified": $DATA_MODIFIED,
    "timestamp": "$(date -Iseconds)",
    "task_start_ts": $TASK_START
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"