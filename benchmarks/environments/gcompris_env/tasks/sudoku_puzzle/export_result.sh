#!/bin/bash
set -e
echo "=== Exporting Sudoku Puzzle Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- 1. Capture Final State ---
take_screenshot /tmp/task_final_state.png

# --- 2. Check Application Status ---
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# --- 3. Check for File Activity (Evidence of Interaction) ---
# GCompris writes to sqlite databases or config files when activities are used/completed.
# We check if any file in the GCompris data directory has been modified since task start.
DATA_DIR="/home/ga/.local/share/GCompris"
CONFIG_DIR="/home/ga/.config/gcompris-qt"

MODIFIED_FILE_COUNT=0
NEWEST_FILE=""

# Helper to check modification times
check_modifications() {
    local dir="$1"
    if [ -d "$dir" ]; then
        # Find files modified after TASK_START
        local count=$(find "$dir" -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)
        MODIFIED_FILE_COUNT=$((MODIFIED_FILE_COUNT + count))
    fi
}

check_modifications "$DATA_DIR"
check_modifications "$CONFIG_DIR"

# --- 4. Export JSON Result ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "modified_file_count": $MODIFIED_FILE_COUNT,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json