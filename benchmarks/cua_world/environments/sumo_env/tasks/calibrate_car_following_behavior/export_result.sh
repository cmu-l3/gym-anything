#!/bin/bash
echo "=== Exporting calibrate_car_following_behavior result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected files
OUTPUT_DIR="/home/ga/SUMO_Output"
VTYPES_FILE="$OUTPUT_DIR/cautious_vtypes.add.xml"
CONFIG_FILE="$OUTPUT_DIR/cautious_run.sumocfg"
BASE_TRIP_FILE="$OUTPUT_DIR/baseline_tripinfo.xml"
CAUT_TRIP_FILE="$OUTPUT_DIR/cautious_tripinfo.xml"
JSON_FILE="$OUTPUT_DIR/calibration_impact.json"
CHART_FILE="$OUTPUT_DIR/comparison_chart.png"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Function to safely get file modification time
get_mtime() {
    if [ -f "$1" ]; then
        stat -c %Y "$1" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Check files and creation timestamps
VTYPES_MTIME=$(get_mtime "$VTYPES_FILE")
CONFIG_MTIME=$(get_mtime "$CONFIG_FILE")
BASE_TRIP_MTIME=$(get_mtime "$BASE_TRIP_FILE")
CAUT_TRIP_MTIME=$(get_mtime "$CAUT_TRIP_FILE")
JSON_MTIME=$(get_mtime "$JSON_FILE")
CHART_MTIME=$(get_mtime "$CHART_FILE")

# Generate structured JSON containing file statuses
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "vtypes": {
            "exists": $([ -f "$VTYPES_FILE" ] && echo "true" || echo "false"),
            "created_during_task": $([ "$VTYPES_MTIME" -gt "$TASK_START" ] && echo "true" || echo "false")
        },
        "config": {
            "exists": $([ -f "$CONFIG_FILE" ] && echo "true" || echo "false"),
            "created_during_task": $([ "$CONFIG_MTIME" -gt "$TASK_START" ] && echo "true" || echo "false")
        },
        "base_trip": {
            "exists": $([ -f "$BASE_TRIP_FILE" ] && echo "true" || echo "false"),
            "created_during_task": $([ "$BASE_TRIP_MTIME" -gt "$TASK_START" ] && echo "true" || echo "false")
        },
        "cautious_trip": {
            "exists": $([ -f "$CAUT_TRIP_FILE" ] && echo "true" || echo "false"),
            "created_during_task": $([ "$CAUT_TRIP_MTIME" -gt "$TASK_START" ] && echo "true" || echo "false")
        },
        "json": {
            "exists": $([ -f "$JSON_FILE" ] && echo "true" || echo "false"),
            "created_during_task": $([ "$JSON_MTIME" -gt "$TASK_START" ] && echo "true" || echo "false")
        },
        "chart": {
            "exists": $([ -f "$CHART_FILE" ] && echo "true" || echo "false"),
            "created_during_task": $([ "$CHART_MTIME" -gt "$TASK_START" ] && echo "true" || echo "false"),
            "size_bytes": $(stat -c %s "$CHART_FILE" 2>/dev/null || echo "0")
        }
    }
}
EOF

# Move results to standard readable location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="