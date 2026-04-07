#!/bin/bash
echo "=== Exporting sector_light_asset_config result ==="

# Define paths
BC_DATA="/opt/bridgecommand"
MODEL_DIR="$BC_DATA/Models/Othership/SectorLight"
SCENARIO_DIR="$BC_DATA/Scenarios/Sector_Light_Test"
BOAT_INI="$MODEL_DIR/boat.ini"

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Gather Evidence ---

# 1. Check Model Directory & Geometry
MODEL_EXISTS="false"
GEOMETRY_FOUND="false"
GEOMETRY_FILES=""
if [ -d "$MODEL_DIR" ]; then
    MODEL_EXISTS="true"
    # Look for .x (DirectX) or .3ds files
    GEOM_COUNT=$(find "$MODEL_DIR" -name "*.x" -o -name "*.3ds" -o -name "*.obj" | wc -l)
    if [ "$GEOM_COUNT" -gt 0 ]; then
        GEOMETRY_FOUND="true"
        GEOMETRY_FILES=$(find "$MODEL_DIR" -name "*.x" -o -name "*.3ds" -o -name "*.obj" -printf "%f,")
    fi
fi

# 2. Read boat.ini content (Configuration)
BOAT_INI_CONTENT=""
BOAT_INI_MTIME="0"
if [ -f "$BOAT_INI" ]; then
    BOAT_INI_CONTENT=$(cat "$BOAT_INI" | base64 -w 0)
    BOAT_INI_MTIME=$(stat -c %Y "$BOAT_INI")
fi

# 3. Check Scenario Files
SCENARIO_EXISTS="false"
OWNSHIP_CONTENT=""
OTHERSHIP_CONTENT=""

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    if [ -f "$SCENARIO_DIR/ownship.ini" ]; then
        OWNSHIP_CONTENT=$(cat "$SCENARIO_DIR/ownship.ini" | base64 -w 0)
    fi
    if [ -f "$SCENARIO_DIR/othership.ini" ]; then
        OTHERSHIP_CONTENT=$(cat "$SCENARIO_DIR/othership.ini" | base64 -w 0)
    fi
fi

# 4. Check if Bridge Command is running (Agent should have restarted it)
APP_RUNNING="false"
if pgrep -f "bridgecommand" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "model_exists": $MODEL_EXISTS,
    "geometry_found": $GEOMETRY_FOUND,
    "geometry_files": "$GEOMETRY_FILES",
    "boat_ini_exists": $([ -f "$BOAT_INI" ] && echo "true" || echo "false"),
    "boat_ini_mtime": $BOAT_INI_MTIME,
    "boat_ini_base64": "$BOAT_INI_CONTENT",
    "scenario_exists": $SCENARIO_EXISTS,
    "ownship_base64": "$OWNSHIP_CONTENT",
    "othership_base64": "$OTHERSHIP_CONTENT",
    "app_running": $APP_RUNNING
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="