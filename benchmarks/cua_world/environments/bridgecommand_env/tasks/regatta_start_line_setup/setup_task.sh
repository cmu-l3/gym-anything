#!/bin/bash
echo "=== Setting up Regatta Start Line task ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/r) Cowes Regatta Start"
DOCS_DIR="/home/ga/Documents"

# 1. Clean up previous attempts
echo "Cleaning up previous scenario files..."
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$DOCS_DIR/sailing_instructions.txt" 2>/dev/null || true
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Ensure Bridge Command is NOT running (clean slate)
pkill -f "bridgecommand" 2>/dev/null || true
sleep 1

# 4. Open the Models directory so the agent can see available assets immediately
# This acts as a hint and saves them navigation time
if command -v nautilus >/dev/null; then
    su - ga -c "DISPLAY=:1 nautilus '$BC_DATA/Models' &"
    sleep 3
    # Maximize the file explorer
    DISPLAY=:1 wmctrl -r "Models" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Take initial screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="