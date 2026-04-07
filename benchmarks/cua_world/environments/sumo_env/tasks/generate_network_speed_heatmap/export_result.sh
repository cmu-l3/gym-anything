#!/bin/bash
echo "=== Exporting generate_network_speed_heatmap result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_DIR="/home/ga/SUMO_Output"
EDGEDATA_FILE="$OUTPUT_DIR/edgedata.add.xml"
SUMOCFG_FILE="$OUTPUT_DIR/run_heatmap.sumocfg"
METRICS_FILE="$OUTPUT_DIR/edge_metrics.xml"
SCRIPT_FILE="$OUTPUT_DIR/plot_heatmap.py"
IMAGE_FILE="$OUTPUT_DIR/speed_heatmap.png"

# Helper function to get file info
get_file_info() {
    local filepath=$1
    if [ -f "$filepath" ]; then
        local size=$(stat -c%s "$filepath" 2>/dev/null || echo "0")
        local mtime=$(stat -c%Y "$filepath" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

EDGEDATA_INFO=$(get_file_info "$EDGEDATA_FILE")
SUMOCFG_INFO=$(get_file_info "$SUMOCFG_FILE")
METRICS_INFO=$(get_file_info "$METRICS_FILE")
SCRIPT_INFO=$(get_file_info "$SCRIPT_FILE")
IMAGE_INFO=$(get_file_info "$IMAGE_FILE")

# Copy script and image to /tmp for verifier access
if [ -f "$SCRIPT_FILE" ]; then
    cp "$SCRIPT_FILE" /tmp/plot_heatmap_copy.py
    chmod 666 /tmp/plot_heatmap_copy.py
fi

if [ -f "$IMAGE_FILE" ]; then
    cp "$IMAGE_FILE" /tmp/speed_heatmap_copy.png
    chmod 666 /tmp/speed_heatmap_copy.png
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "edgedata_xml": $EDGEDATA_INFO,
    "sumocfg": $SUMOCFG_INFO,
    "edge_metrics": $METRICS_INFO,
    "plot_script": $SCRIPT_INFO,
    "heatmap_image": $IMAGE_INFO,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="