#!/bin/bash
echo "=== Exporting Landfall Rising Range result ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/Landfall_Calibration"
CALC_FILE="/home/ga/Documents/range_calculations.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize JSON variables
SCENARIO_EXISTS="false"
ENV_INI_EXISTS="false"
OWNSHIP_INI_EXISTS="false"
OTHERSHIP_INI_EXISTS="false"
CALC_FILE_EXISTS="false"

# Check directories and files
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    [ -f "$SCENARIO_DIR/environment.ini" ] && ENV_INI_EXISTS="true"
    [ -f "$SCENARIO_DIR/ownship.ini" ] && OWNSHIP_INI_EXISTS="true"
    [ -f "$SCENARIO_DIR/othership.ini" ] && OTHERSHIP_INI_EXISTS="true"
fi

if [ -f "$CALC_FILE" ]; then
    CALC_FILE_EXISTS="true"
fi

# Function to safely extract value from INI file
get_ini_value() {
    local file="$1"
    local key="$2"
    if [ -f "$file" ]; then
        # Try specific key="value" format first (BC standard), then key=value
        grep -oP "${key}=\"\K[^\"]+" "$file" 2>/dev/null || \
        grep -oP "${key}=\K.*" "$file" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Extract Environment Data
ENV_SETTING=$(get_ini_value "$SCENARIO_DIR/environment.ini" "Setting")
ENV_START_TIME=$(get_ini_value "$SCENARIO_DIR/environment.ini" "StartTime")
ENV_VISIBILITY=$(get_ini_value "$SCENARIO_DIR/environment.ini" "VisibilityRange")
ENV_WEATHER=$(get_ini_value "$SCENARIO_DIR/environment.ini" "Weather")

# Extract Ownship Data
OWN_LAT=$(get_ini_value "$SCENARIO_DIR/ownship.ini" "InitialLat")
OWN_LONG=$(get_ini_value "$SCENARIO_DIR/ownship.ini" "InitialLong")
OWN_HEADING=$(get_ini_value "$SCENARIO_DIR/ownship.ini" "InitialBearing")

# Extract Othership Data (first vessel)
OTHER_LAT=""
OTHER_LONG=""
OTHER_HEADING=""

if [ "$OTHERSHIP_INI_EXISTS" = "true" ]; then
    # othership.ini uses indexed keys like InitLat(1)=...
    # We'll use python to parse this as it's cleaner than complex grep regex for indexed keys
    eval $(python3 -c "
import re
try:
    with open('$SCENARIO_DIR/othership.ini', 'r') as f:
        content = f.read()
    
    lat = re.search(r'InitLat\(1\)=([0-9.-]+)', content)
    lon = re.search(r'InitLong\(1\)=([0-9.-]+)', content)
    # Bearing might be Bearing(1,1) for first leg or just Bearing(1) in some contexts? 
    # Usually strictly defined legs in BC. Let's look for first leg bearing.
    bear = re.search(r'Bear\(1,1\)=([0-9.]+)', content)
    
    print(f'OTHER_LAT={lat.group(1) if lat else \"\"}')
    print(f'OTHER_LONG={lon.group(1) if lon else \"\"}')
    print(f'OTHER_HEADING={bear.group(1) if bear else \"\"}')
except:
    pass
")
fi

# Check timestamps to ensure files were created during task
FILES_NEW="false"
if [ "$SCENARIO_EXISTS" = "true" ]; then
    DIR_MTIME=$(stat -c %Y "$SCENARIO_DIR" 2>/dev/null || echo "0")
    if [ "$DIR_MTIME" -gt "$TASK_START" ]; then
        FILES_NEW="true"
    fi
fi

# Construct JSON result
cat > /tmp/task_result.json << EOF
{
    "scenario_exists": $SCENARIO_EXISTS,
    "files_created_during_task": $FILES_NEW,
    "environment": {
        "exists": $ENV_INI_EXISTS,
        "setting": "$ENV_SETTING",
        "start_time": "$ENV_START_TIME",
        "visibility": "$ENV_VISIBILITY",
        "weather": "$ENV_WEATHER"
    },
    "ownship": {
        "exists": $OWNSHIP_INI_EXISTS,
        "lat": "$OWN_LAT",
        "long": "$OWN_LONG",
        "heading": "$OWN_HEADING"
    },
    "othership": {
        "exists": $OTHERSHIP_INI_EXISTS,
        "lat": "$OTHER_LAT",
        "long": "$OTHER_LONG",
        "heading": "$OTHER_HEADING"
    },
    "calculations_doc_exists": $CALC_FILE_EXISTS
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json