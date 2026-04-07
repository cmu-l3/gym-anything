#!/bin/bash
echo "=== Setting up simulate_vehicle_breakdown_traci task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/SUMO_Output
rm -f /home/ga/SUMO_Output/simulate_breakdown.py
rm -f /home/ga/SUMO_Output/breakdown_queue.csv
chown -R ga:ga /home/ga/SUMO_Output

# Kill any existing SUMO processes
kill_sumo
sleep 1

SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_pasubio"

# Extract two connected edges from the route file to guarantee traffic
# We look for a route definition and pick the first two edges
EDGES=$(grep -m 1 -oP '(?<=edges=")[^"]+' "$SCENARIO_DIR/pasubio.rou.xml" || echo "")

if [ -n "$EDGES" ]; then
    UPSTREAM_EDGE=$(echo "$EDGES" | awk '{print $1}')
    CRITICAL_EDGE=$(echo "$EDGES" | awk '{print $2}')
else
    # Fallback if regex fails
    UPSTREAM_EDGE="123456"
    CRITICAL_EDGE="123457"
fi

# Create the target_edges.json file for the agent to read
TARGET_JSON="$SCENARIO_DIR/target_edges.json"
cat > "$TARGET_JSON" << EOF
{
    "upstream_edge": "$UPSTREAM_EDGE",
    "critical_edge": "$CRITICAL_EDGE"
}
EOF
chown ga:ga "$TARGET_JSON"

echo "Selected upstream_edge: $UPSTREAM_EDGE"
echo "Selected critical_edge: $CRITICAL_EDGE"

# Take initial screenshot of empty desktop
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="