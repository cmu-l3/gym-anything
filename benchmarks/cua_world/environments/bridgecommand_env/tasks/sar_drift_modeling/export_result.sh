#!/bin/bash
echo "=== Exporting SAR Drift Modeling Result ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/s) Solent SAR Kayak"
DOCS_DIR="/home/ga/Documents"
ANALYSIS_FILE="$DOCS_DIR/drift_analysis.txt"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Check Analysis Document ---
DOC_EXISTS="false"
DOC_CREATED_DURING_TASK="false"
DOC_CONTENT=""

if [ -f "$ANALYSIS_FILE" ]; then
    DOC_EXISTS="true"
    DOC_MTIME=$(stat -c %Y "$ANALYSIS_FILE" 2>/dev/null || echo "0")
    if [ "$DOC_MTIME" -gt "$TASK_START" ]; then
        DOC_CREATED_DURING_TASK="true"
    fi
    # Read first 1000 chars of content (safe for JSON)
    DOC_CONTENT=$(head -c 1000 "$ANALYSIS_FILE" | tr -d '\000-\011\013\014\016-\037')
fi

# --- Check Scenario Existence ---
SCENARIO_EXISTS="false"
ENV_EXISTS="false"
OWNSHIP_EXISTS="false"
OTHERSHIP_EXISTS="false"

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    [ -f "$SCENARIO_DIR/environment.ini" ] && ENV_EXISTS="true"
    [ -f "$SCENARIO_DIR/ownship.ini" ] && OWNSHIP_EXISTS="true"
    [ -f "$SCENARIO_DIR/othership.ini" ] && OTHERSHIP_EXISTS="true"
fi

# --- Extract Scenario Data ---
# Initialize variables
ENV_START_TIME=""
ENV_WIND_DIR=""
ENV_WIND_SPEED=""
OWN_LAT=""
OWN_LONG=""
TARGET_LAT=""
TARGET_LONG=""

# Parse environment.ini
if [ "$ENV_EXISTS" = "true" ]; then
    ENV_START_TIME=$(grep -i "StartTime" "$SCENARIO_DIR/environment.ini" | cut -d'=' -f2 | tr -d ' \r')
    ENV_WIND_DIR=$(grep -i "WindDirection" "$SCENARIO_DIR/environment.ini" | cut -d'=' -f2 | tr -d ' \r')
    ENV_WIND_SPEED=$(grep -i "WindSpeed" "$SCENARIO_DIR/environment.ini" | cut -d'=' -f2 | tr -d ' \r')
fi

# Parse ownship.ini (Rescue Vessel)
if [ "$OWNSHIP_EXISTS" = "true" ]; then
    OWN_LAT=$(grep -i "InitialLat" "$SCENARIO_DIR/ownship.ini" | cut -d'=' -f2 | tr -d ' \r')
    OWN_LONG=$(grep -i "InitialLong" "$SCENARIO_DIR/ownship.ini" | cut -d'=' -f2 | tr -d ' \r')
fi

# Parse othership.ini (Target Vessel)
# We need to find the first vessel's position
if [ "$OTHERSHIP_EXISTS" = "true" ]; then
    # Bridge Command uses InitLat(1)=... format or sometimes just InitLat=... if single
    # Try indexed format first
    TARGET_LAT=$(grep -i "InitLat(1)" "$SCENARIO_DIR/othership.ini" | cut -d'=' -f2 | tr -d ' \r')
    TARGET_LONG=$(grep -i "InitLong(1)" "$SCENARIO_DIR/othership.ini" | cut -d'=' -f2 | tr -d ' \r')
    
    # Fallback to non-indexed if empty
    if [ -z "$TARGET_LAT" ]; then
        TARGET_LAT=$(grep -i "InitLat" "$SCENARIO_DIR/othership.ini" | head -1 | cut -d'=' -f2 | tr -d ' \r')
        TARGET_LONG=$(grep -i "InitLong" "$SCENARIO_DIR/othership.ini" | head -1 | cut -d'=' -f2 | tr -d ' \r')
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "doc_exists": $DOC_EXISTS,
    "doc_created_during_task": $DOC_CREATED_DURING_TASK,
    "doc_content": "$(echo "$DOC_CONTENT" | sed 's/"/\\"/g')",
    "scenario_exists": $SCENARIO_EXISTS,
    "files": {
        "environment": $ENV_EXISTS,
        "ownship": $OWNSHIP_EXISTS,
        "othership": $OTHERSHIP_EXISTS
    },
    "data": {
        "env_start_time": "$ENV_START_TIME",
        "env_wind_dir": "$ENV_WIND_DIR",
        "env_wind_speed": "$ENV_WIND_SPEED",
        "own_lat": "$OWN_LAT",
        "own_long": "$OWN_LONG",
        "target_lat": "$TARGET_LAT",
        "target_long": "$TARGET_LONG"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="