#!/bin/bash
echo "=== Exporting register_multiday_pass results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check for Proof Files
PROOF_SCREENSHOT="/home/ga/Documents/multiday_pass_proof.png"
PROOF_EXPORT="/home/ga/Documents/multiday_pass_info.txt"

PROOF_FOUND="false"
PROOF_TYPE="none"
PROOF_PATH=""

if [ -f "$PROOF_SCREENSHOT" ]; then
    MTIME=$(stat -c %Y "$PROOF_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PROOF_FOUND="true"
        PROOF_TYPE="screenshot"
        PROOF_PATH="$PROOF_SCREENSHOT"
    fi
elif [ -f "$PROOF_EXPORT" ]; then
    MTIME=$(stat -c %Y "$PROOF_EXPORT" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PROOF_FOUND="true"
        PROOF_TYPE="export"
        PROOF_PATH="$PROOF_EXPORT"
    fi
fi

# 2. Check if App is still running
APP_RUNNING=$(pgrep -f "LobbyTrack\|Lobby" > /dev/null && echo "true" || echo "false")

# 3. Capture Final Desktop Screenshot (standard evidence)
take_screenshot /tmp/task_final.png

# 4. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "proof_found": $PROOF_FOUND,
    "proof_type": "$PROOF_TYPE",
    "proof_path": "$PROOF_PATH",
    "app_running": $APP_RUNNING,
    "current_date_str": "$(date +%Y-%m-%d)",
    "target_expiration_str": "$(date -d "+14 days" +%Y-%m-%d)"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="