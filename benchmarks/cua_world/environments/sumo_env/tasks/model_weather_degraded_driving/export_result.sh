#!/bin/bash
echo "=== Exporting Weather Degraded Driving Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define target paths
VTYPES_RAIN="/home/ga/SUMO_Output/pasubio_vtypes_rain.add.xml"
RUN_RAIN="/home/ga/SUMO_Scenarios/bologna_pasubio/run_rain.sumocfg"
TRIPINFO_BASELINE="/home/ga/SUMO_Output/tripinfo_baseline.xml"
TRIPINFO_RAIN="/home/ga/SUMO_Output/tripinfo_rain.xml"
IMPACT_TXT="/home/ga/SUMO_Output/weather_impact.txt"

# Function to safely check modification time
check_mtime() {
    local file=$1
    if [ -f "$file" ]; then
        local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

# Function to safely copy to /tmp for the verifier
safe_copy() {
    local src=$1
    local dest=$2
    if [ -f "$src" ]; then
        cp "$src" "$dest"
        chmod 644 "$dest"
    else
        rm -f "$dest"
    fi
}

# Copy files for verifier to access via copy_from_env
safe_copy "$VTYPES_RAIN" "/tmp/vtypes_rain.xml"
safe_copy "$RUN_RAIN" "/tmp/run_rain.sumocfg"
safe_copy "$TRIPINFO_BASELINE" "/tmp/tripinfo_baseline.xml"
safe_copy "$TRIPINFO_RAIN" "/tmp/tripinfo_rain.xml"
safe_copy "$IMPACT_TXT" "/tmp/weather_impact.txt"

# Create task_result.json with basic metadata
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "vtypes_rain_exists": $([ -f "$VTYPES_RAIN" ] && echo "true" || echo "false"),
    "vtypes_rain_newer": $(check_mtime "$VTYPES_RAIN"),
    "run_rain_exists": $([ -f "$RUN_RAIN" ] && echo "true" || echo "false"),
    "run_rain_newer": $(check_mtime "$RUN_RAIN"),
    "tripinfo_baseline_exists": $([ -f "$TRIPINFO_BASELINE" ] && echo "true" || echo "false"),
    "tripinfo_baseline_newer": $(check_mtime "$TRIPINFO_BASELINE"),
    "tripinfo_rain_exists": $([ -f "$TRIPINFO_RAIN" ] && echo "true" || echo "false"),
    "tripinfo_rain_newer": $(check_mtime "$TRIPINFO_RAIN"),
    "impact_txt_exists": $([ -f "$IMPACT_TXT" ] && echo "true" || echo "false"),
    "impact_txt_newer": $(check_mtime "$IMPACT_TXT"),
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="