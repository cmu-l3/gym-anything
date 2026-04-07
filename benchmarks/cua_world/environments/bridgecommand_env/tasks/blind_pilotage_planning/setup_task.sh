#!/bin/bash
echo "=== Setting up Blind Pilotage Planning Task ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_NAME="Blind Pilotage Calibration"
SCENARIO_DIR="$BC_DATA/Scenarios/$SCENARIO_NAME"
DOCS_DIR="/home/ga/Documents"

# 1. Clean up previous task artifacts
# We remove the specific scenario directory if it exists to ensure the agent creates it from scratch
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# Remove the briefing document
rm -f "$DOCS_DIR/pi_calibration_brief.txt" 2>/dev/null || true

# 2. Ensure directory structure exists for the agent
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 3. Ensure Bridge Command is in a known state
# Reset bc5.ini to defaults to prevent interference from previous tasks
mkdir -p "/home/ga/.config/Bridge Command"
cp /workspace/config/bc5.ini "/home/ga/.config/Bridge Command/bc5.ini" 2>/dev/null || true
chown -R ga:ga "/home/ga/.config"

# 4. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 5. Launch Bridge Command to the main menu (optional, but helpful for context)
# We don't necessarily need it running since this is primarily a file creation task,
# but having it open allows the agent to check the "Solent" map coordinates if they want.
echo "Starting Bridge Command in background..."
pkill -f "bridgecommand" 2>/dev/null || true
sleep 1
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_startup.log 2>&1 &"

# Wait for window
sleep 5
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="