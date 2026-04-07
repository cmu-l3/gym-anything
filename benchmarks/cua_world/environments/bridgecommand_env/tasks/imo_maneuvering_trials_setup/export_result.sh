#!/bin/bash
echo "=== Exporting IMO Maneuvering Trials Result ==="

# Define paths
TRIALS_DIR="/opt/bridgecommand/Scenarios/Sea Trials"
PLAN_FILE="/home/ga/Documents/trials_plan.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Directory Structure
SCENARIOS_EXIST="false"
DIR_TURNING="false"
DIR_ZIGZAG="false"
DIR_STOPPING="false"

if [ -d "$TRIALS_DIR" ]; then
    SCENARIOS_EXIST="true"
    [ -d "$TRIALS_DIR/a) Turning Circle Test" ] && DIR_TURNING="true"
    [ -d "$TRIALS_DIR/b) Zig-Zag Test" ] && DIR_ZIGZAG="true"
    [ -d "$TRIALS_DIR/c) Crash Stop Test" ] && DIR_STOPPING="true"
fi

# 3. Helper function to parse INI values
get_ini_value() {
    local file="$1"
    local key="$2"
    if [ -f "$file" ]; then
        # Grep for Key=Value, handle quoted and unquoted, case insensitive keys
        grep -i -oP "^${key}\s*=\s*\K.*" "$file" | tr -d '"' | tr -d '\r' | head -1
    else
        echo ""
    fi
}

# 4. Extract data from each scenario
# We build a JSON structure for the verifier to analyze

# Function to extract scenario data
extract_scenario_data() {
    local dir="$1"
    local env_file="$dir/environment.ini"
    local own_file="$dir/ownship.ini"
    local other_file="$dir/othership.ini"

    local weather=$(get_ini_value "$env_file" "Weather")
    local lat=$(get_ini_value "$own_file" "InitialLat")
    local speed=$(get_ini_value "$own_file" "InitialSpeed")
    local name=$(get_ini_value "$own_file" "ShipName")
    local traffic_count=$(get_ini_value "$other_file" "Number")
    
    # Handle empty Othership file implies 0
    if [ -z "$traffic_count" ] && [ -f "$other_file" ]; then
        traffic_count="0"
    fi

    echo "{\"weather\": \"$weather\", \"lat\": \"$lat\", \"speed\": \"$speed\", \"name\": \"$name\", \"traffic\": \"$traffic_count\"}"
}

DATA_TURNING="{}"
DATA_ZIGZAG="{}"
DATA_STOPPING="{}"

if [ "$DIR_TURNING" = "true" ]; then DATA_TURNING=$(extract_scenario_data "$TRIALS_DIR/a) Turning Circle Test"); fi
if [ "$DIR_ZIGZAG" = "true" ]; then DATA_ZIGZAG=$(extract_scenario_data "$TRIALS_DIR/b) Zig-Zag Test"); fi
if [ "$DIR_STOPPING" = "true" ]; then DATA_STOPPING=$(extract_scenario_data "$TRIALS_DIR/c) Crash Stop Test"); fi

# 5. Check bc5.ini for track_history
TRACK_HISTORY="0"
# Check both possible locations
for cfg in "/home/ga/.config/Bridge Command/bc5.ini" "/opt/bridgecommand/bc5.ini"; do
    if [ -f "$cfg" ]; then
        val=$(get_ini_value "$cfg" "track_history")
        if [ "$val" == "1" ]; then
            TRACK_HISTORY="1"
            break
        fi
    fi
done

# 6. Read Trials Plan Document
PLAN_CONTENT=""
PLAN_EXISTS="false"
if [ -f "$PLAN_FILE" ]; then
    PLAN_EXISTS="true"
    PLAN_CONTENT=$(cat "$PLAN_FILE" | head -c 1000) # Read first 1000 chars
fi

# 7. Construct Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "scenarios_root_exists": $SCENARIOS_EXIST,
    "dirs": {
        "turning": $DIR_TURNING,
        "zigzag": $DIR_ZIGZAG,
        "stopping": $DIR_STOPPING
    },
    "data": {
        "turning": $DATA_TURNING,
        "zigzag": $DATA_ZIGZAG,
        "stopping": $DATA_STOPPING
    },
    "config": {
        "track_history": "$TRACK_HISTORY"
    },
    "plan": {
        "exists": $PLAN_EXISTS,
        "content": $(echo "$PLAN_CONTENT" | jq -R -s '.')
    }
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json