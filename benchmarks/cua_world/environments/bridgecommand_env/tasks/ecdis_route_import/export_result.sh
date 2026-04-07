#!/bin/bash
echo "=== Exporting ECDIS Route Import Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/Imported ECDIS Route"
OWNSHIP_FILE="$SCENARIO_DIR/ownship.ini"
ENV_FILE="$SCENARIO_DIR/environment.ini"
OTHER_FILE="$SCENARIO_DIR/othership.ini"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check existence
DIR_EXISTS="false"
OWNSHIP_EXISTS="false"
ENV_EXISTS="false"
OTHER_EXISTS="false"
NEWLY_CREATED="false"

if [ -d "$SCENARIO_DIR" ]; then
    DIR_EXISTS="true"
    # Check creation time
    DIR_MTIME=$(stat -c %Y "$SCENARIO_DIR" 2>/dev/null || echo "0")
    if [ "$DIR_MTIME" -gt "$TASK_START" ]; then
        NEWLY_CREATED="true"
    fi
fi

[ -f "$OWNSHIP_FILE" ] && OWNSHIP_EXISTS="true"
[ -f "$ENV_FILE" ] && ENV_EXISTS="true"
[ -f "$OTHER_FILE" ] && OTHER_EXISTS="true"

# Extract Ownship Data
INITIAL_LAT=""
INITIAL_LONG=""
INITIAL_BEARING=""
LEG1_LAT=""
LEG1_LONG=""
LEG2_LAT=""
LEG2_LONG=""
LEG3_LAT=""
LEG3_LONG=""

if [ "$OWNSHIP_EXISTS" = "true" ]; then
    # Grep for values, handling potential quoting or spacing
    # InitialLat
    INITIAL_LAT=$(grep -i "InitialLat" "$OWNSHIP_FILE" | head -1 | cut -d'=' -f2 | tr -d ' "')
    INITIAL_LONG=$(grep -i "InitialLong" "$OWNSHIP_FILE" | head -1 | cut -d'=' -f2 | tr -d ' "')
    INITIAL_BEARING=$(grep -i "InitialBearing" "$OWNSHIP_FILE" | head -1 | cut -d'=' -f2 | tr -d ' "')

    # Extract Legs (Leg(1)Lat, etc.)
    # Note: grep needs escaping for parenthesis
    LEG1_LAT=$(grep -i "Leg(1)Lat" "$OWNSHIP_FILE" | head -1 | cut -d'=' -f2 | tr -d ' "')
    LEG1_LONG=$(grep -i "Leg(1)Long" "$OWNSHIP_FILE" | head -1 | cut -d'=' -f2 | tr -d ' "')
    
    LEG2_LAT=$(grep -i "Leg(2)Lat" "$OWNSHIP_FILE" | head -1 | cut -d'=' -f2 | tr -d ' "')
    LEG2_LONG=$(grep -i "Leg(2)Long" "$OWNSHIP_FILE" | head -1 | cut -d'=' -f2 | tr -d ' "')

    LEG3_LAT=$(grep -i "Leg(3)Lat" "$OWNSHIP_FILE" | head -1 | cut -d'=' -f2 | tr -d ' "')
    LEG3_LONG=$(grep -i "Leg(3)Long" "$OWNSHIP_FILE" | head -1 | cut -d'=' -f2 | tr -d ' "')
fi

# Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "dir_exists": $DIR_EXISTS,
    "newly_created": $NEWLY_CREATED,
    "files": {
        "ownship": $OWNSHIP_EXISTS,
        "environment": $ENV_EXISTS,
        "othership": $OTHER_EXISTS
    },
    "ownship_data": {
        "initial_lat": "$INITIAL_LAT",
        "initial_long": "$INITIAL_LONG",
        "initial_bearing": "$INITIAL_BEARING",
        "leg1": {"lat": "$LEG1_LAT", "long": "$LEG1_LONG"},
        "leg2": {"lat": "$LEG2_LAT", "long": "$LEG2_LONG"},
        "leg3": {"lat": "$LEG3_LAT", "long": "$LEG3_LONG"}
    }
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json