#!/bin/bash
echo "=== Setting up Historical Battle Reconstruction Task ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/h) River Plate 1939"
DOCS_DIR="/home/ga/Documents"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean state: Remove the scenario if it exists from a previous run
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# Remove the calculations file if it exists
if [ -f "$DOCS_DIR/battle_calculations.txt" ]; then
    rm -f "$DOCS_DIR/battle_calculations.txt"
fi

# Ensure Documents directory exists
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# Ensure Bridge Command is ready
if ! pgrep -f "bridgecommand" > /dev/null; then
    # We don't necessarily need to start it for this task as it's primarily file creation,
    # but we'll ensure the environment is clean.
    echo "Bridge Command is not running (clean state)."
else
    echo "Killing running Bridge Command instance..."
    pkill -f "bridgecommand"
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="