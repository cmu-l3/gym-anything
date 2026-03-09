#!/bin/bash
echo "=== Exporting disable_p2p_routing results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONFIG_PATH="/home/ga/.jitsi-meet-cfg/web/custom-config.js"
EVIDENCE_PATH="/home/ga/p2p_disabled_evidence.png"

# 1. Capture final screenshot (framework requirement)
take_screenshot /tmp/task_final.png

# 2. Check Config File (File System)
CONFIG_EXISTS="false"
CONFIG_CONTENT=""
CONFIG_CORRECT="false"

if [ -f "$CONFIG_PATH" ]; then
    CONFIG_EXISTS="true"
    # Read content safely
    CONFIG_CONTENT=$(cat "$CONFIG_PATH" | tr -d '\n' | sed 's/"/\\"/g')
    
    # Check for the required setting using grep
    if grep -q "config.p2p" "$CONFIG_PATH" && grep -q "enabled.*false" "$CONFIG_PATH"; then
        CONFIG_CORRECT="true"
    fi
fi

# 3. Check Config Serving (HTTP) - Did they restart the container?
# If the container was restarted, curl should return the new config
HTTP_CONFIG_CONTENT=$(curl -s "http://localhost:8080/custom-config.js" || echo "")
HTTP_CONFIG_CORRECT="false"
if echo "$HTTP_CONFIG_CONTENT" | grep -q "config.p2p" && echo "$HTTP_CONFIG_CONTENT" | grep -q "enabled.*false"; then
    HTTP_CONFIG_CORRECT="true"
fi

# 4. Check Evidence Screenshot
EVIDENCE_EXISTS="false"
if [ -f "$EVIDENCE_PATH" ]; then
    # Check timestamp
    EVIDENCE_TIME=$(stat -c %Y "$EVIDENCE_PATH" 2>/dev/null || echo "0")
    if [ "$EVIDENCE_TIME" -gt "$TASK_START" ]; then
        EVIDENCE_EXISTS="true"
        # Copy to /tmp for extraction if needed
        cp "$EVIDENCE_PATH" /tmp/agent_evidence.png
    fi
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config_exists": $CONFIG_EXISTS,
    "config_correct_fs": $CONFIG_CORRECT,
    "config_correct_http": $HTTP_CONFIG_CORRECT,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_path": "/tmp/agent_evidence.png",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json