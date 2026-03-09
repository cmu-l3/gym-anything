#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/config.js"
CUSTOM_CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/custom-config.js"
EVIDENCE_FILE="/home/ga/analytics_verification.png"

# Check config file
CONFIG_EXISTS="false"
CONFIG_CONTENT=""
CONFIG_MTIME="0"

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_EXISTS="true"
    CONFIG_CONTENT=$(cat "$CONFIG_FILE" | base64 -w 0)
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
fi

# Check custom config (alternative valid approach)
CUSTOM_CONFIG_EXISTS="false"
CUSTOM_CONFIG_CONTENT=""
CUSTOM_CONFIG_MTIME="0"

if [ -f "$CUSTOM_CONFIG_FILE" ]; then
    CUSTOM_CONFIG_EXISTS="true"
    CUSTOM_CONFIG_CONTENT=$(cat "$CUSTOM_CONFIG_FILE" | base64 -w 0)
    CUSTOM_CONFIG_MTIME=$(stat -c %Y "$CUSTOM_CONFIG_FILE" 2>/dev/null || echo "0")
fi

# Check evidence screenshot
EVIDENCE_EXISTS="false"
if [ -f "$EVIDENCE_FILE" ]; then
    EVIDENCE_EXISTS="true"
fi

# Take final system screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_exists": $CONFIG_EXISTS,
    "config_mtime": $CONFIG_MTIME,
    "config_content_b64": "$CONFIG_CONTENT",
    "custom_config_exists": $CUSTOM_CONFIG_EXISTS,
    "custom_config_mtime": $CUSTOM_CONFIG_MTIME,
    "custom_config_content_b64": "$CUSTOM_CONFIG_CONTENT",
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_path": "$EVIDENCE_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="