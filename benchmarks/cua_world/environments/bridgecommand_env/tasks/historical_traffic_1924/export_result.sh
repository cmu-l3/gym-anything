#!/bin/bash
echo "=== Exporting Historical Traffic 1924 results ==="

# Paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/h) Solent 1924"
MANIFEST_FILE="/home/ga/Documents/1924_manifest.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize result variables
SCENARIO_EXISTS="false"
ENV_EXISTS="false"
OWN_EXISTS="false"
OTHER_EXISTS="false"
MANIFEST_EXISTS="false"

ENV_CONTENT=""
OWN_CONTENT=""
OTHER_CONTENT=""
MANIFEST_CONTENT=""

# Check directory and files
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    
    if [ -f "$SCENARIO_DIR/environment.ini" ]; then
        ENV_EXISTS="true"
        # Read content safely (limit size)
        ENV_CONTENT=$(head -n 50 "$SCENARIO_DIR/environment.ini" | base64 -w 0)
    fi
    
    if [ -f "$SCENARIO_DIR/ownship.ini" ]; then
        OWN_EXISTS="true"
        OWN_CONTENT=$(head -n 50 "$SCENARIO_DIR/ownship.ini" | base64 -w 0)
    fi
    
    if [ -f "$SCENARIO_DIR/othership.ini" ]; then
        OTHER_EXISTS="true"
        OTHER_CONTENT=$(cat "$SCENARIO_DIR/othership.ini" | base64 -w 0)
    fi
fi

if [ -f "$MANIFEST_FILE" ]; then
    MANIFEST_EXISTS="true"
    MANIFEST_CONTENT=$(head -n 100 "$MANIFEST_FILE" | base64 -w 0)
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scenario_exists": $SCENARIO_EXISTS,
    "env_exists": $ENV_EXISTS,
    "own_exists": $OWN_EXISTS,
    "other_exists": $OTHER_EXISTS,
    "manifest_exists": $MANIFEST_EXISTS,
    "env_content_b64": "$ENV_CONTENT",
    "own_content_b64": "$OWN_CONTENT",
    "other_content_b64": "$OTHER_CONTENT",
    "manifest_content_b64": "$MANIFEST_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="