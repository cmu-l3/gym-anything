#!/bin/bash
echo "=== Setting up Wind Farm Scenario Creation Task ==="

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Target directory
SCENARIO_DIR="/opt/bridgecommand/Scenarios/w) Solent Wind Farm Assessment"

# 1. Clean up any previous attempt to ensure a fresh start
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# 2. Clean up document
rm -f "/home/ga/Documents/notice_to_mariners_014.txt"

# 3. Ensure Bridge Command is NOT running (file creation task)
pkill -f "bridgecommand" 2>/dev/null || true

# 4. Record initial state of scenarios directory
ls -R "/opt/bridgecommand/Scenarios" > /tmp/initial_scenarios_list.txt

# 5. Ensure Models directory exists and is readable (agent needs to see 'Buoy')
if [ ! -d "/opt/bridgecommand/Models" ]; then
    echo "ERROR: Models directory missing!"
    exit 1
fi

# 6. Take initial screenshot of the desktop/terminal
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="