#!/bin/bash
echo "=== Exporting network_graph_centrality result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define file paths
SCRIPT_FILE="/home/ga/SUMO_Output/analyze_centrality.py"
CSV_FILE="/home/ga/SUMO_Output/node_centrality.csv"
TOP5_FILE="/home/ga/SUMO_Output/top_5_critical_nodes.txt"
NET_FILE="/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_buslanes.net.xml"

# Initialize state variables
SCRIPT_EXISTS="false"
SCRIPT_CREATED_DURING_TASK="false"
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
TOP5_EXISTS="false"
TOP5_CREATED_DURING_TASK="false"

# Check script
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    MTIME=$(stat -c %Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then SCRIPT_CREATED_DURING_TASK="true"; fi
    cp "$SCRIPT_FILE" /tmp/analyze_centrality.py
fi

# Check CSV
if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then CSV_CREATED_DURING_TASK="true"; fi
    cp "$CSV_FILE" /tmp/node_centrality.csv
fi

# Check Top 5 TXT
if [ -f "$TOP5_FILE" ]; then
    TOP5_EXISTS="true"
    MTIME=$(stat -c %Y "$TOP5_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then TOP5_CREATED_DURING_TASK="true"; fi
    cp "$TOP5_FILE" /tmp/top_5_critical_nodes.txt
fi

# Copy the network file to tmp so the verifier can read the ground truth structure
cp "$NET_FILE" /tmp/pasubio_buslanes.net.xml

# Adjust permissions so verifier can easily read them
chmod 666 /tmp/analyze_centrality.py /tmp/node_centrality.csv /tmp/top_5_critical_nodes.txt /tmp/pasubio_buslanes.net.xml 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "top5_exists": $TOP5_EXISTS,
    "top5_created_during_task": $TOP5_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safely move JSON result
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="