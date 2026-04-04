#!/bin/bash
echo "=== Exporting Disable Shared Video results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (Agent should have left the menu open)
take_screenshot /tmp/task_final.png

# 2. Inspect the configuration inside the container
# Find the web container id
CONTAINER_ID=$(docker ps --format "{{.ID}} {{.Names}}" | grep -i "jitsi-web" | awk '{print $1}' | head -n 1)

CONFIG_HAS_SHAREDVIDEO="unknown"
CONFIG_HAS_MIC="unknown"
CONFIG_VALID_JS="unknown"
CONFIG_CONTENT=""

if [ -n "$CONTAINER_ID" ]; then
    echo "Found web container: $CONTAINER_ID"
    
    # Extract config content
    docker exec "$CONTAINER_ID" cat /config/config.js > /tmp/final_config.js 2>/dev/null || true
    
    if [ -f /tmp/final_config.js ]; then
        # Check for sharedvideo
        if grep -q "'sharedvideo'" /tmp/final_config.js || grep -q "\"sharedvideo\"" /tmp/final_config.js; then
            CONFIG_HAS_SHAREDVIDEO="true"
        else
            CONFIG_HAS_SHAREDVIDEO="false"
        fi
        
        # Check for microphone (sanity check - prevent deleting whole array)
        if grep -q "'microphone'" /tmp/final_config.js || grep -q "\"microphone\"" /tmp/final_config.js; then
            CONFIG_HAS_MIC="true"
        else
            CONFIG_HAS_MIC="false"
        fi
        
        # Simple syntax check (node -c)
        if command -v node >/dev/null; then
             # config.js often has 'var config = ...' which is valid JS
             if node -c /tmp/final_config.js 2>/dev/null; then
                 CONFIG_VALID_JS="true"
             else
                 CONFIG_VALID_JS="false"
             fi
        else
             CONFIG_VALID_JS="unchecked"
        fi
    else
        echo "Failed to retrieve config.js from container"
    fi
else
    echo "ERROR: Could not find jitsi-web container"
fi

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "container_found": $([ -n "$CONTAINER_ID" ] && echo "true" || echo "false"),
    "config_has_sharedvideo": "$CONFIG_HAS_SHAREDVIDEO",
    "config_has_mic": "$CONFIG_HAS_MIC",
    "config_valid_js": "$CONFIG_VALID_JS",
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json