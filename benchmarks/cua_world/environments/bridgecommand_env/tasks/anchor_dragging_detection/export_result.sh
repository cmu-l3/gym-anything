#!/bin/bash
echo "=== Exporting Anchor Dragging Result ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/s) St Helens Anchor Drag"
BRIEFING_FILE="/home/ga/Documents/instructor_briefing.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize status variables
SCENARIO_EXISTS="false"
ENV_INI_CONTENT=""
OTHERSHIP_INI_CONTENT=""
OWNSHIP_INI_CONTENT=""
BRIEFING_EXISTS="false"
BRIEFING_CONTENT=""

# Check Scenario Directory
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    
    # Read environment.ini
    if [ -f "$SCENARIO_DIR/environment.ini" ]; then
        ENV_INI_CONTENT=$(cat "$SCENARIO_DIR/environment.ini" | base64 -w 0)
    fi
    
    # Read othership.ini
    if [ -f "$SCENARIO_DIR/othership.ini" ]; then
        OTHERSHIP_INI_CONTENT=$(cat "$SCENARIO_DIR/othership.ini" | base64 -w 0)
    fi

    # Read ownship.ini
    if [ -f "$SCENARIO_DIR/ownship.ini" ]; then
        OWNSHIP_INI_CONTENT=$(cat "$SCENARIO_DIR/ownship.ini" | base64 -w 0)
    fi
fi

# Check Briefing File
if [ -f "$BRIEFING_FILE" ]; then
    BRIEFING_EXISTS="true"
    BRIEFING_CONTENT=$(head -n 20 "$BRIEFING_FILE")
    # Check modification time to prevent pre-caching gaming
    FILE_MTIME=$(stat -c %Y "$BRIEFING_FILE")
    if [ "$FILE_MTIME" -lt "$TASK_START" ]; then
        BRIEFING_EXISTS="false_stale"
    fi
fi

# Create JSON Result
# We embed the base64 content to safely transport INI files to Python for robust parsing
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "scenario_exists": $SCENARIO_EXISTS,
    "env_ini_b64": "$ENV_INI_CONTENT",
    "othership_ini_b64": "$OTHERSHIP_INI_CONTENT",
    "ownship_ini_b64": "$OWNSHIP_INI_CONTENT",
    "briefing_exists": "$BRIEFING_EXISTS",
    "briefing_content": "$(echo $BRIEFING_CONTENT | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Export complete. Result saved to /tmp/task_result.json"