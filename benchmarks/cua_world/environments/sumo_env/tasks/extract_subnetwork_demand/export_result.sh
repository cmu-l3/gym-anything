#!/bin/bash
echo "=== Exporting extract_subnetwork_demand result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Expected output files
NET_FILE="/home/ga/SUMO_Output/micro.net.xml"
ROU_FILE="/home/ga/SUMO_Output/micro.rou.xml"
CFG_FILE="/home/ga/SUMO_Output/micro.sumocfg"
ORIG_NET="/home/ga/SUMO_Scenarios/bologna_acosta/acosta_buslanes.net.xml"

# Initialize variables
NET_EXISTS="false"
ROU_EXISTS="false"
CFG_EXISTS="false"
NET_MTIME=0
ROU_MTIME=0
CFG_MTIME=0
CONV_BOUNDARY=""
ORIG_EDGES=0
MICRO_EDGES=0
SIMULATION_EXIT_CODE=999
SIMULATION_RAN="false"

# Check Original Network Edges
if [ -f "$ORIG_NET" ]; then
    ORIG_EDGES=$(grep -c "<edge " "$ORIG_NET" 2>/dev/null || echo "0")
fi

# Check Network File
if [ -f "$NET_FILE" ]; then
    NET_EXISTS="true"
    NET_MTIME=$(stat -c %Y "$NET_FILE" 2>/dev/null || echo "0")
    # Extract convBoundary attribute from the location tag
    CONV_BOUNDARY=$(grep -m 1 "convBoundary=" "$NET_FILE" | grep -oP 'convBoundary="\K[^"]+')
    MICRO_EDGES=$(grep -c "<edge " "$NET_FILE" 2>/dev/null || echo "0")
fi

# Check Route File
if [ -f "$ROU_FILE" ]; then
    ROU_EXISTS="true"
    ROU_MTIME=$(stat -c %Y "$ROU_FILE" 2>/dev/null || echo "0")
fi

# Check Config File
if [ -f "$CFG_FILE" ]; then
    CFG_EXISTS="true"
    CFG_MTIME=$(stat -c %Y "$CFG_FILE" 2>/dev/null || echo "0")
    
    # Run a quick check of the simulation to see if it's structurally valid
    # Run for just 5 steps to verify routes map to the network correctly without hanging
    echo "Testing simulation integrity..."
    su - ga -c "SUMO_HOME=/usr/share/sumo sumo -c $CFG_FILE --step-length 1 --end 5 > /tmp/micro_sim_test.log 2>&1"
    SIMULATION_EXIT_CODE=$?
    SIMULATION_RAN="true"
    echo "Simulation exit code: $SIMULATION_EXIT_CODE"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "net_exists": $NET_EXISTS,
    "net_mtime": $NET_MTIME,
    "rou_exists": $ROU_EXISTS,
    "rou_mtime": $ROU_MTIME,
    "cfg_exists": $CFG_EXISTS,
    "cfg_mtime": $CFG_MTIME,
    "conv_boundary": "$CONV_BOUNDARY",
    "orig_edges": $ORIG_EDGES,
    "micro_edges": $MICRO_EDGES,
    "simulation_ran": $SIMULATION_RAN,
    "simulation_exit_code": $SIMULATION_EXIT_CODE
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="