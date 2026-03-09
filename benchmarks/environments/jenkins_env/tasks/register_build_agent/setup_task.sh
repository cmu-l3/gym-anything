#!/bin/bash
# Setup script for Register Build Agent task
# Ensures Jenkins is ready and records initial node count

echo "=== Setting up Register Build Agent Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 60; then
    echo "WARNING: Jenkins API not ready"
fi

# Record initial node count to verify a NEW node is created
echo "Recording initial node count..."
INITIAL_NODES=$(jenkins_api "computer/api/json" 2>/dev/null | jq '.computer | length' 2>/dev/null || echo "0")
printf '%s' "$INITIAL_NODES" > /tmp/initial_node_count
echo "Initial node count: $INITIAL_NODES"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is running and focused on Jenkins dashboard
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JENKINS_URL/computer/" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|jenkins" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Ensure we are on the nodes page or dashboard
    # (The browser start command above tried to go to /computer/, but if it was already open it might be elsewhere)
    # We won't force navigation here to allow agent to find the path, 
    # but starting at dashboard is standard.
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Register Build Agent Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Navigate to Manage Jenkins > Nodes"
echo "  2. Create a New Node named 'frontend-builder-01'"
echo "  3. Type: Permanent Agent"
echo "  4. Configure:"
echo "     - Executors: 4"
echo "     - Remote root: /opt/jenkins-agent"
echo "     - Labels: frontend linux high-mem"
echo "     - Usage: Only build jobs with label expressions matching this node"
echo "     - Launch method: Launch agent by connecting it to the controller"
echo ""