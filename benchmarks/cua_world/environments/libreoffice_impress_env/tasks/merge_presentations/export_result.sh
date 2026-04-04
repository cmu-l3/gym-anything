#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Merge Presentations Result ==="

# Define paths
OUTPUT_FILE="/home/ga/Documents/Presentations/Executive_Briefing.odp"
TASK_START_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# 1. Take Final Screenshot
# ------------------------
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Collect File Stats
# ---------------------
FILE_EXISTS="false"
FILE_SIZE_BYTES=0
FILE_CREATED_DURING_TASK="false"
TASK_START_TIME=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Source Files (Anti-Gaming)
# -----------------------------------
# Agent should not delete source files
SOURCE_1_EXISTS=$([ -f "/home/ga/Documents/Presentations/BIA_Findings.odp" ] && echo "true" || echo "false")
SOURCE_2_EXISTS=$([ -f "/home/ga/Documents/Presentations/Risk_Assessment.odp" ] && echo "true" || echo "false")

# 4. Check Application State
# --------------------------
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# 5. Generate JSON Result
# -----------------------
# Use a temp file first to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result_temp.XXXXXX)

cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START_TIME,
    "output_exists": $FILE_EXISTS,
    "output_size_bytes": $FILE_SIZE_BYTES,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "source_bia_exists": $SOURCE_1_EXISTS,
    "source_risk_exists": $SOURCE_2_EXISTS,
    "app_running": $APP_RUNNING,
    "output_path": "$OUTPUT_FILE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permissive rights
cp "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON"
rm "$TEMP_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"

echo "=== Export Complete ==="