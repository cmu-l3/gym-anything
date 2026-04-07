#!/bin/bash
echo "=== Setting up Landfall Rising Range task ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/Landfall_Calibration"
DOCS_DIR="/home/ga/Documents"

# Ensure Bridge Command is installed
if [ ! -d "$BC_DATA" ]; then
    echo "ERROR: Bridge Command data directory not found at $BC_DATA"
    exit 1
fi

# Clean previous run artifacts
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

rm -f "$DOCS_DIR/range_calculations.txt" 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial file count in Scenarios to detect new creations
ls -1 "$BC_DATA/Scenarios" | wc -l > /tmp/initial_scenario_count.txt

# Ensure no BC instances are running
pkill -f "bridgecommand" 2>/dev/null || true

echo "=== Setup complete ==="