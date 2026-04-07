#!/bin/bash
echo "=== Setting up SAR Drift Modeling Task ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/s) Solent SAR Kayak"
DOCS_DIR="/home/ga/Documents"

# Ensure clean state
echo "Cleaning up previous run artifacts..."
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$DOCS_DIR/drift_analysis.txt" 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial file counts
ls -1 "$BC_DATA/Scenarios" | wc -l > /tmp/initial_scenario_count.txt

# Ensure Bridge Command is closed
pkill -f "bridgecommand" 2>/dev/null || true

# Maximize any existing windows just in case (though none should be open)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="