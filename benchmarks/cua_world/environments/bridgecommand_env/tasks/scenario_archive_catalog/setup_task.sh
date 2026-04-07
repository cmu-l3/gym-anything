#!/bin/bash
set -e
echo "=== Setting up Scenario Archive Catalog Task ==="

# Record task start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# Ensure the Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any previous run artifacts
rm -f /home/ga/Documents/scenario_catalog.json
rm -f /home/ga/Documents/scenario_checksums.sha256
rm -f /home/ga/Documents/preservation_report.txt

# Ensure Bridge Command Scenarios exist
SCENARIOS_DIR="/opt/bridgecommand/Scenarios"
if [ ! -d "$SCENARIOS_DIR" ]; then
    echo "ERROR: Scenarios directory not found at $SCENARIOS_DIR"
    exit 1
fi

# Ensure there are scenarios to inventory
SCENARIO_COUNT=$(ls -d "$SCENARIOS_DIR"/*/ 2>/dev/null | wc -l)
echo "Found $SCENARIO_COUNT scenarios in $SCENARIOS_DIR"

if [ "$SCENARIO_COUNT" -eq 0 ]; then
    echo "WARNING: No scenarios found. Creating dummy scenarios for validity."
    # Create a couple of dummy scenarios if none exist (fallback for bare installations)
    mkdir -p "$SCENARIOS_DIR/a) Training Alpha"
    echo "Setting=\"Solent\"" > "$SCENARIOS_DIR/a) Training Alpha/environment.ini"
    echo "StartTime=12.0" >> "$SCENARIOS_DIR/a) Training Alpha/environment.ini"
    echo "ShipName=\"Fast Ferry\"" > "$SCENARIOS_DIR/a) Training Alpha/ownship.ini"
    echo "Number=1" > "$SCENARIOS_DIR/a) Training Alpha/othership.ini"
    echo "Type(1)=\"Tanker\"" >> "$SCENARIOS_DIR/a) Training Alpha/othership.ini"
fi

# Open a terminal for the agent to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x30 &"
fi

# Maximize terminal
sleep 2
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="