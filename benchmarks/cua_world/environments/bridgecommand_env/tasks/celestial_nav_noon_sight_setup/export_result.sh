#!/bin/bash
echo "=== Exporting Celestial Navigation Task Results ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/c) Celestial Noon Sight"
ENV_INI="$SCENARIO_DIR/environment.ini"
OWNSHIP_INI="$SCENARIO_DIR/ownship.ini"
BRIEFING_FILE="/home/ga/Documents/instructor_briefing.txt"

# Initialize variables
SCENARIO_EXISTS="false"
ENV_EXISTS="false"
OWNSHIP_EXISTS="false"
BRIEFING_EXISTS="false"

START_TIME=""
START_DAY=""
START_MONTH=""
SETTING=""

LAT=""
LONG=""
HEADING=""

BRIEFING_CONTENT=""

# Collect Scenario Data
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    
    if [ -f "$ENV_INI" ]; then
        ENV_EXISTS="true"
        # Extract values using grep/regex. Note: INI keys might be quoted.
        START_TIME=$(grep -oP 'StartTime=\K[0-9.]+' "$ENV_INI" || echo "")
        START_DAY=$(grep -oP 'StartDay=\K[0-9]+' "$ENV_INI" || echo "")
        START_MONTH=$(grep -oP 'StartMonth=\K[0-9]+' "$ENV_INI" || echo "")
        SETTING=$(grep -oP 'Setting="\K[^"]+' "$ENV_INI" || grep -oP 'Setting=\K.*' "$ENV_INI" || echo "")
    fi

    if [ -f "$OWNSHIP_INI" ]; then
        OWNSHIP_EXISTS="true"
        LAT=$(grep -oP 'InitialLat=\K[0-9.-]+' "$OWNSHIP_INI" || echo "")
        LONG=$(grep -oP 'InitialLong=\K[0-9.-]+' "$OWNSHIP_INI" || echo "")
        HEADING=$(grep -oP 'InitialBearing=\K[0-9.]+' "$OWNSHIP_INI" || echo "")
    fi
fi

# Collect Briefing Content
if [ -f "$BRIEFING_FILE" ]; then
    BRIEFING_EXISTS="true"
    # Read first 10 lines of briefing to avoid huge files
    BRIEFING_CONTENT=$(head -n 20 "$BRIEFING_FILE")
fi

# Check timestamps to ensure files were created during task
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_CREATED_DURING_TASK="false"

if [ "$SCENARIO_EXISTS" = "true" ]; then
    SCENARIO_MTIME=$(stat -c %Y "$SCENARIO_DIR" 2>/dev/null || echo "0")
    if [ "$SCENARIO_MTIME" -gt "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/celestial_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "scenario_exists": $SCENARIO_EXISTS,
    "env_ini_exists": $ENV_EXISTS,
    "ownship_ini_exists": $OWNSHIP_EXISTS,
    "briefing_exists": $BRIEFING_EXISTS,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "config": {
        "start_time_decimal": "$START_TIME",
        "start_day": "$START_DAY",
        "start_month": "$START_MONTH",
        "setting": "$SETTING",
        "lat": "$LAT",
        "long": "$LONG",
        "heading": "$HEADING"
    },
    "briefing_content": $(python3 -c "import json; print(json.dumps('''$BRIEFING_CONTENT'''))")
}
EOF

# Safe move
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json