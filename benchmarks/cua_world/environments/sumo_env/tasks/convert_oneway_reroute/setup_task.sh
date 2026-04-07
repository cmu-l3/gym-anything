#!/bin/bash
echo "=== Setting up convert_oneway_reroute task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

WORK_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"

# Ensure the environment is clean of any previous runs
rm -f "$WORK_DIR/acosta_oneway.net.xml" 2>/dev/null || true
rm -f "$WORK_DIR/acosta_oneway.rou.xml" 2>/dev/null || true
rm -f "$WORK_DIR/acosta_oneway.rou.alt.xml" 2>/dev/null || true
rm -f "$WORK_DIR/run_oneway.sumocfg" 2>/dev/null || true
rm -f "$WORK_DIR/tripinfos_oneway.xml" 2>/dev/null || true

# Dynamically select a real edge from the network to remove
# We grep for an edge that is NOT internal (internal edges start with ':')
TARGET_EDGE=$(grep '<edge id=' "$WORK_DIR/acosta_buslanes.net.xml" | grep -v 'function="internal"' | head -n 15 | tail -n 1 | sed -n 's/.*id="\([^"]*\)".*/\1/p')

# Fallback in case parsing fails
if [ -z "$TARGET_EDGE" ]; then
    TARGET_EDGE="143360431#0" 
fi

# Save the target edge for the verifier
echo "$TARGET_EDGE" > /tmp/target_edge.txt

# Create the circulation plan for the agent to read
cat > "$WORK_DIR/circulation_plan.txt" << EOF
CITY OF BOLOGNA - MOBILITY DEPARTMENT
CIRCULATION PLAN AMENDMENT - ACOSTA NEIGHBORHOOD

Directive: Convert the following road segment to a pedestrian-only zone (one-way removal from vehicle network).

Target Edge ID to Remove: $TARGET_EDGE

Please run a traffic assignment simulation to evaluate the impact of this closure on the surrounding street grid.
EOF

chown ga:ga "$WORK_DIR/circulation_plan.txt"

# Open a terminal for the agent in the working directory
echo "Launching terminal..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$WORK_DIR --maximize &"

# Wait for terminal window
sleep 3
wait_for_window "Terminal" 10

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
take_screenshot /tmp/task_initial.png

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="