#!/bin/bash
echo "=== Exporting enforce_identity_validation results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/custom-config.js"
BLOCKED_EVIDENCE="/home/ga/Documents/evidence_blocked.png"
SUCCESS_EVIDENCE="/home/ga/Documents/evidence_success.png"

# 1. Check Config File
CONFIG_EXISTS="false"
CONFIG_CONTENT=""
CONFIG_MODIFIED_DURING_TASK="false"

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_EXISTS="true"
    CONFIG_CONTENT=$(cat "$CONFIG_FILE" | base64 -w 0) # Base64 encode to safely pass to JSON
    
    FILE_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED_DURING_TASK="true"
    fi
fi

# 2. Check Evidence Screenshots
check_evidence() {
    local file="$1"
    if [ -f "$file" ]; then
        local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false" # Existed before task
        fi
    else
        echo "false"
    fi
}

BLOCKED_EXISTS=$(check_evidence "$BLOCKED_EVIDENCE")
SUCCESS_EXISTS=$(check_evidence "$SUCCESS_EVIDENCE")

# 3. Check Jitsi Container Status (Did they restart it?)
# We check if the web container is up. We can't easily check if it was restarted,
# but we can check uptime if we really wanted. For now, just ensuring it's running is basic.
JITSI_RUNNING="false"
if curl -sfk "http://localhost:8080" >/dev/null 2>&1; then
    JITSI_RUNNING="true"
fi

# 4. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_exists": $CONFIG_EXISTS,
    "config_content_b64": "$CONFIG_CONTENT",
    "config_modified_during_task": $CONFIG_MODIFIED_DURING_TASK,
    "blocked_evidence_exists": $BLOCKED_EXISTS,
    "success_evidence_exists": $SUCCESS_EXISTS,
    "jitsi_running": $JITSI_RUNNING,
    "blocked_evidence_path": "$BLOCKED_EVIDENCE",
    "success_evidence_path": "$SUCCESS_EVIDENCE"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"