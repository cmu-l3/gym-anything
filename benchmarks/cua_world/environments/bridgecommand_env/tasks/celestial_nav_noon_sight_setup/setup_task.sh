#!/bin/bash
echo "=== Setting up Celestial Navigation Noon Sight Task ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/c) Celestial Noon Sight"
DOCS_DIR="/home/ga/Documents"

# Ensure clean state
echo "Cleaning previous attempts..."
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$DOCS_DIR/instructor_briefing.txt" 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial state of scenarios directory
ls -R "$BC_DATA/Scenarios" > /tmp/initial_scenarios_list.txt 2>/dev/null || true

# Kill any running Bridge Command instances
pkill -f "bridgecommand" 2>/dev/null || true

# Maximize and focus windows logic (if agent launches app)
# Note: Agent might do calculations via python or calculator, or just edit files directly.
# We ensure the desktop is ready.
DISPLAY=:1 xset s off 2>/dev/null || true
DISPLAY=:1 xset -dpms 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Task ready. Determine LAN for 45N 10W on June 15, 2025 and set up the scenario."