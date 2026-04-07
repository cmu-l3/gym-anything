#!/bin/bash
echo "=== Setting up Spithead Fleet Review Choreography ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/r) Spithead Fleet Review"
SCHEDULE_FILE="/home/ga/Documents/review_schedule.txt"
DOCS_DIR="/home/ga/Documents"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# clean up previous attempts
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$SCHEDULE_FILE" 2>/dev/null || true

# Ensure documents directory exists
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# Ensure Bridge Command is accessible (standard env setup)
if [ ! -d "/opt/bridgecommand" ]; then
    echo "ERROR: Bridge Command installation not found."
    exit 1
fi

# Maximize any existing windows (standard practice)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Task ready. Create scenario at: $SCENARIO_DIR"