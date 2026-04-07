#!/bin/bash
echo "=== Exporting Blind Pilotage Planning Result ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/Blind Pilotage Calibration"
BRIEFING_FILE="/home/ga/Documents/pi_calibration_brief.txt"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# Capture final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# Initialize variables
SCENARIO_EXISTS="false"
ENV_INI_EXISTS="false"
OWNSHIP_INI_EXISTS="false"
OTHERSHIP_INI_EXISTS="false"
BRIEFING_EXISTS="false"

# Extracted values
VISIBILITY=""
START_TIME=""
OWN_LAT=""
OWN_LONG=""
OWN_HEADING=""
OWN_SPEED=""

# 1. Check Scenario Directory
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    
    # Check Environment.ini
    if [ -f "$SCENARIO_DIR/environment.ini" ]; then
        ENV_INI_EXISTS="true"
        VISIBILITY=$(grep -i "VisibilityRange" "$SCENARIO_DIR/environment.ini" | cut -d'=' -f2 | tr -d ' "')
        START_TIME=$(grep -i "StartTime" "$SCENARIO_DIR/environment.ini" | cut -d'=' -f2 | tr -d ' "')
    fi
    
    # Check Ownship.ini
    if [ -f "$SCENARIO_DIR/ownship.ini" ]; then
        OWNSHIP_INI_EXISTS="true"
        OWN_LAT=$(grep -i "InitialLat" "$SCENARIO_DIR/ownship.ini" | cut -d'=' -f2 | tr -d ' "')
        OWN_LONG=$(grep -i "InitialLong" "$SCENARIO_DIR/ownship.ini" | cut -d'=' -f2 | tr -d ' "')
        OWN_HEADING=$(grep -i "InitialBearing" "$SCENARIO_DIR/ownship.ini" | cut -d'=' -f2 | tr -d ' "')
        # Check for alternative key "Heading" if "InitialBearing" is missing
        if [ -z "$OWN_HEADING" ]; then
             OWN_HEADING=$(grep -i "^Heading" "$SCENARIO_DIR/ownship.ini" | cut -d'=' -f2 | tr -d ' "')
        fi
        OWN_SPEED=$(grep -i "InitialSpeed" "$SCENARIO_DIR/ownship.ini" | cut -d'=' -f2 | tr -d ' "')
    fi

    # Check Othership.ini
    if [ -f "$SCENARIO_DIR/othership.ini" ]; then
        OTHERSHIP_INI_EXISTS="true"
    fi
fi

# 2. Check Briefing Document
BRIEFING_CONTENT=""
if [ -f "$BRIEFING_FILE" ]; then
    BRIEFING_EXISTS="true"
    BRIEFING_CONTENT=$(cat "$BRIEFING_FILE" | head -n 20) # Grab first 20 lines
fi

# 3. Create JSON Result
# Using python for safe JSON formatting
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $NOW,
    'scenario_exists': '$SCENARIO_EXISTS' == 'true',
    'env_ini_exists': '$ENV_INI_EXISTS' == 'true',
    'ownship_ini_exists': '$OWNSHIP_INI_EXISTS' == 'true',
    'othership_ini_exists': '$OTHERSHIP_INI_EXISTS' == 'true',
    'briefing_exists': '$BRIEFING_EXISTS' == 'true',
    'extracted_values': {
        'visibility': '$VISIBILITY',
        'start_time': '$START_TIME',
        'own_lat': '$OWN_LAT',
        'own_long': '$OWN_LONG',
        'own_heading': '$OWN_HEADING',
        'own_speed': '$OWN_SPEED'
    },
    'briefing_content': '''$BRIEFING_CONTENT'''
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Set permissions so verifier can read it
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="