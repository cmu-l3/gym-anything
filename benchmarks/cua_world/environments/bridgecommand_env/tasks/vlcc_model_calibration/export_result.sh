#!/bin/bash
echo "=== Exporting VLCC Model Calibration Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

MODEL_DIR="/opt/bridgecommand/Models/VLCC_Training"
BOAT_FILE="$MODEL_DIR/boat.txt"
SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) VLCC Channel Approach"
REPORT_FILE="/home/ga/Documents/vlcc_config_report.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Helper to get file modification time ---
get_mtime() {
    stat -c %Y "$1" 2>/dev/null || echo "0"
}

# --- Check Model Directory and boat.txt ---
MODEL_EXISTS="false"
BOAT_FILE_EXISTS="false"
BOAT_FILE_CONTENT=""
MESH_FILES_EXIST="false"

if [ -d "$MODEL_DIR" ]; then
    MODEL_EXISTS="true"
    # Check for 3D model files (mesh)
    MESH_COUNT=$(ls "$MODEL_DIR"/*.x "$MODEL_DIR"/*.3ds "$MODEL_DIR"/*.obj 2>/dev/null | wc -l)
    if [ "$MESH_COUNT" -gt 0 ]; then
        MESH_FILES_EXIST="true"
    fi
fi

if [ -f "$BOAT_FILE" ]; then
    BOAT_FILE_EXISTS="true"
    BOAT_FILE_MTIME=$(get_mtime "$BOAT_FILE")
    # Read content for python verifier
    BOAT_FILE_CONTENT=$(cat "$BOAT_FILE" | head -n 100) # limit size
fi

# --- Check Scenario ---
SCENARIO_EXISTS="false"
OWNSHIP_INI_EXISTS="false"
OTHERSHIP_INI_EXISTS="false"
ENV_INI_EXISTS="false"
OWNSHIP_CONTENT=""
OTHERSHIP_CONTENT=""
ENV_CONTENT=""

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    if [ -f "$SCENARIO_DIR/ownship.ini" ]; then
        OWNSHIP_INI_EXISTS="true"
        OWNSHIP_CONTENT=$(cat "$SCENARIO_DIR/ownship.ini")
    fi
    if [ -f "$SCENARIO_DIR/othership.ini" ]; then
        OTHERSHIP_INI_EXISTS="true"
        OTHERSHIP_CONTENT=$(cat "$SCENARIO_DIR/othership.ini")
    fi
    if [ -f "$SCENARIO_DIR/environment.ini" ]; then
        ENV_INI_EXISTS="true"
        ENV_CONTENT=$(cat "$SCENARIO_DIR/environment.ini")
    fi
fi

# --- Check Report ---
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -n 100)
fi

# --- Construct JSON Result ---
# Using python to safely construct JSON with potentially messy file content
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'model': {
        'exists': $MODEL_EXISTS,
        'boat_file_exists': $BOAT_FILE_EXISTS,
        'boat_file_content': '''$BOAT_FILE_CONTENT''',
        'mesh_files_exist': $MESH_FILES_EXIST,
        'boat_file_mtime': $(get_mtime "$BOAT_FILE")
    },
    'scenario': {
        'exists': $SCENARIO_EXISTS,
        'ownship_exists': $OWNSHIP_INI_EXISTS,
        'othership_exists': $OTHERSHIP_INI_EXISTS,
        'env_exists': $ENV_INI_EXISTS,
        'ownship_content': '''$OWNSHIP_CONTENT''',
        'othership_content': '''$OTHERSHIP_CONTENT''',
        'env_content': '''$ENV_CONTENT'''
    },
    'report': {
        'exists': $REPORT_EXISTS,
        'content': '''$REPORT_CONTENT'''
    }
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Result saved to $RESULT_JSON"
echo "=== Export complete ==="