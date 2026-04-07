#!/bin/bash
echo "=== Exporting Scenario Audit Results ==="

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SCENARIO_DIR="/opt/bridgecommand/Scenarios/h) Humber Approach Training"
REPORT_PATH="/home/ga/Documents/scenario_audit_report.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to read INI values safely
# Usage: read_ini_value "file.ini" "Key"
read_ini_value() {
    local file="$1"
    local key="$2"
    if [ -f "$file" ]; then
        # Handle simple Key=Value
        grep -oP "^$key=\K.*" "$file" | head -1 | tr -d '\r'
    fi
}

# Helper to read Indexed INI values (e.g., InitialLat(1)=...)
# Usage: read_indexed_value "file.ini" "KeyPrefix" "Index"
read_indexed_value() {
    local file="$1"
    local prefix="$2"
    local idx="$3"
    # Escape parentheses for grep
    grep -oP "^${prefix}\(${idx}\)=\K.*" "$file" | head -1 | tr -d '\r'
}

# Check file modification times (Anti-gaming)
check_mtime() {
    local file="$1"
    if [ -f "$file" ]; then
        local mtime=$(stat -c %Y "$file")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

# --- EXTRACT DATA ---

# 1. Environment.ini
ENV_FILE="$SCENARIO_DIR/environment.ini"
ENV_MODIFIED=$(check_mtime "$ENV_FILE")
START_TIME=$(read_ini_value "$ENV_FILE" "StartTime")
START_MONTH=$(read_ini_value "$ENV_FILE" "StartMonth")
WEATHER=$(read_ini_value "$ENV_FILE" "Weather")

# 2. Ownship.ini
OWN_FILE="$SCENARIO_DIR/ownship.ini"
OWN_MODIFIED=$(check_mtime "$OWN_FILE")
OWN_LAT=$(read_ini_value "$OWN_FILE" "InitialLat")
OWN_LONG=$(read_ini_value "$OWN_FILE" "InitialLong")
OWN_SPEED=$(read_ini_value "$OWN_FILE" "InitialSpeed")

# 3. Othership.ini
OTHER_FILE="$SCENARIO_DIR/othership.ini"
OTHER_MODIFIED=$(check_mtime "$OTHER_FILE")
# Vessel 1 (Tanker - Baseline)
V1_LAT=$(read_indexed_value "$OTHER_FILE" "InitialLat" "1")
V1_LONG=$(read_indexed_value "$OTHER_FILE" "InitialLong" "1")
# Vessel 2 (Container - Collision Risk)
V2_LAT=$(read_indexed_value "$OTHER_FILE" "InitialLat" "2")
V2_LONG=$(read_indexed_value "$OTHER_FILE" "InitialLong" "2")
V2_LEGS=$(read_indexed_value "$OTHER_FILE" "Legs" "2")
# Vessel 3 (VLCC - Speed Risk)
V3_SPEED=$(read_indexed_value "$OTHER_FILE" "InitialSpeed" "3")
# Check waypoint speeds for V3 just in case
V3_WP_SPEED=$(grep "Speed(3,1)" "$OTHER_FILE" | cut -d'=' -f2 | tr -d '\r')

# 4. Report
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_SIZE=0
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
    # Read first 2KB of report for verification
    REPORT_CONTENT=$(head -c 2048 "$REPORT_PATH" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
else
    REPORT_CONTENT='""'
fi

# Create JSON Output
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "environment": {
            "modified": $ENV_MODIFIED,
            "start_time": "$START_TIME",
            "start_month": "$START_MONTH",
            "weather": "$WEATHER"
        },
        "ownship": {
            "modified": $OWN_MODIFIED,
            "lat": "$OWN_LAT",
            "long": "$OWN_LONG",
            "speed": "$OWN_SPEED"
        },
        "othership": {
            "modified": $OTHER_MODIFIED,
            "v1_lat": "$V1_LAT",
            "v1_long": "$V1_LONG",
            "v2_lat": "$V2_LAT",
            "v2_long": "$V2_LONG",
            "v2_legs": "$V2_LEGS",
            "v3_speed": "$V3_SPEED",
            "v3_wp_speed": "$V3_WP_SPEED"
        }
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "size": $REPORT_SIZE,
        "content": $REPORT_CONTENT
    }
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"