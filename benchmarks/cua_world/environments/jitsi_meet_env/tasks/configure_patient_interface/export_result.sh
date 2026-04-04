#!/bin/bash
set -e
echo "=== Exporting configure_patient_interface results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_SCREENSHOT="/home/ga/Documents/restricted_settings.png"

# 1. Capture final state screenshot (desktop)
take_screenshot /tmp/task_final.png

# 2. Extract the interface_config.js from the container
WEB_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i "web" | head -n 1)
CONFIG_EXPORT_PATH="/tmp/extracted_interface_config.js"
CONFIG_FOUND="false"

if [ -n "$WEB_CONTAINER" ]; then
    echo "Attempting to copy config from $WEB_CONTAINER..."
    # Try standard location
    if docker cp "$WEB_CONTAINER:/usr/share/jitsi-meet/interface_config.js" "$CONFIG_EXPORT_PATH" 2>/dev/null; then
        CONFIG_FOUND="true"
        echo "Config exported successfully."
    else
        echo "Config not found at standard path, trying /defaults..."
        if docker cp "$WEB_CONTAINER:/defaults/interface_config.js" "$CONFIG_EXPORT_PATH" 2>/dev/null; then
            CONFIG_FOUND="true"
            echo "Config exported from defaults."
        fi
    fi
else
    echo "WARNING: Web container not found during export."
fi

# 3. Check for the agent's proof screenshot
SCREENSHOT_EXISTS="false"
if [ -f "$OUTPUT_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    # Copy to tmp for safe export if needed, or just reference it
    cp "$OUTPUT_SCREENSHOT" /tmp/agent_proof.png
fi

# 4. Get Browser Title (if possible via xdotool)
BROWSER_TITLE=$(xdotool search --class "firefox" getwindowname 2>/dev/null | head -n 1 || echo "")

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config_found": $CONFIG_FOUND,
    "config_path": "$CONFIG_EXPORT_PATH",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/agent_proof.png",
    "final_desktop_screenshot": "/tmp/task_final.png",
    "browser_title": "$(echo "$BROWSER_TITLE" | sed 's/"/\\"/g')",
    "timestamp": $(date +%s)
}
EOF

# Move to standard result location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="