#!/bin/bash
set -e
echo "=== Exporting enforce_display_name_policy result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot (Agent's final view)
take_screenshot /tmp/task_final.png

# 2. Check for Evidence Screenshot (created by Agent)
EVIDENCE_PATH="/home/ga/evidence_disabled_button.png"
EVIDENCE_EXISTS="false"
EVIDENCE_CREATED_DURING="false"

if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_MTIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    if [ "$EVIDENCE_MTIME" -gt "$TASK_START" ]; then
        EVIDENCE_CREATED_DURING="true"
    fi
fi

# 3. Extract the config.js file for verification
CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/config.js"
CONFIG_MODIFIED="false"

# Copy to temp for export
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" /tmp/config_final.js
    chmod 666 /tmp/config_final.js
    
    # Check modification time
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi
else
    echo "WARNING: Config file not found at export time"
fi

# 4. Check if Agent is in a meeting (Successful Join)
# We check if the URL contains a room name (not just localhost:8080) 
# and potentially check the window title or page content
IN_MEETING="false"
# Simple check: Is Firefox running and not on the home page?
# Note: This is a loose check; verifier.py will do VLM checks on trajectory for robust proof.
if pgrep -f firefox > /dev/null; then
    IN_MEETING="true" 
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_created_during_task": $EVIDENCE_CREATED_DURING,
    "config_modified": $CONFIG_MODIFIED,
    "final_screenshot_path": "/tmp/task_final.png",
    "evidence_path": "$EVIDENCE_PATH",
    "config_backup_path": "/tmp/config_final.js"
}
EOF

# Move result to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="