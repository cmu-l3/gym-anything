#!/bin/bash
echo "=== Setting up Oil Spill Boom Deployment Task ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_NAME="q) Oil Recovery V-Sweep"
SCENARIO_DIR="$BC_DATA/Scenarios/$SCENARIO_NAME"
DOC_DIR="/home/ga/Documents"

# 1. Clean up previous runs to ensure fresh state
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

rm -f "$DOC_DIR/boom_deployment_plan.txt" 2>/dev/null || true

# 2. Ensure directories exist
mkdir -p "$DOC_DIR"
chown ga:ga "$DOC_DIR"

# 3. Record start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# 4. Open Bridge Command Launcher to giving agent a starting point
# (Agent can use GUI to create folder structure or terminal, but GUI helps visualize)
echo "Starting Bridge Command Launcher..."
if ! pgrep -f "bridgecommand" > /dev/null; then
    su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_launch.log 2>&1 &"
    sleep 5
fi

# 5. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
        echo "Bridge Command window detected."
        DISPLAY=:1 wmctrl -r "Bridge Command" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="