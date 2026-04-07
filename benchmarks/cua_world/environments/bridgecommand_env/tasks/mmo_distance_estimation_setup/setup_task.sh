#!/bin/bash
echo "=== Setting up MMO Calibration Task ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/m) MMO Calibration"
DOCS_DIR="/home/ga/Documents"

# 1. Clean up previous run artifacts
echo "Cleaning up previous scenarios..."
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$DOCS_DIR/calibration_card.txt" 2>/dev/null || true

# 2. Ensure directories exist
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Open File Manager to Scenarios directory (Helpful context)
echo "Opening file manager..."
if ! pgrep -f "nautilus" > /dev/null; then
    su - ga -c "DISPLAY=:1 nautilus /opt/bridgecommand/Scenarios &"
    sleep 2
fi

# 5. Open Terminal for calculations/editing
echo "Opening terminal..."
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal &"
    sleep 2
fi

# 6. Position windows (Terminal left, File Manager right)
DISPLAY=:1 wmctrl -r "Terminal" -e 0,0,0,960,1080 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Scenarios" -e 0,960,0,960,1080 2>/dev/null || true

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="