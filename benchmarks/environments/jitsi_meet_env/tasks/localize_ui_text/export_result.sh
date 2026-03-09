#!/bin/bash
echo "=== Exporting localize_ui_text results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Export the localization file from the container for verification
WEB_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i "web" | head -n 1)
LANG_FILE_EXPORTED="false"

if [ -n "$WEB_CONTAINER" ]; then
    echo "Exporting main.json from $WEB_CONTAINER..."
    if docker cp "$WEB_CONTAINER:/usr/share/jitsi-meet/lang/main.json" /tmp/jitsi_main.json 2>/dev/null; then
        LANG_FILE_EXPORTED="true"
        chmod 644 /tmp/jitsi_main.json
    else
        echo "Failed to copy main.json from container"
    fi
else
    echo "Web container not found"
fi

# 2. Check for agent's evidence screenshot
EVIDENCE_PATH="/home/ga/Documents/custom_ui_evidence.png"
EVIDENCE_EXISTS="false"
if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    # Copy to tmp for verifier access
    cp "$EVIDENCE_PATH" /tmp/agent_evidence.png
fi

# 3. Take final system screenshot (ground truth of visual state)
take_screenshot /tmp/task_final.png

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "lang_file_exported": $LANG_FILE_EXPORTED,
    "evidence_screenshot_exists": $EVIDENCE_EXISTS,
    "web_container": "$WEB_CONTAINER"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="