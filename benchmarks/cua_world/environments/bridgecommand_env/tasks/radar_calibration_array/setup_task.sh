#!/bin/bash
echo "=== Setting up Radar Calibration Array Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/z) Radar Calibration"

# Ensure clean state: Remove the target scenario if it exists from previous runs
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario artifact..."
    rm -rf "$SCENARIO_DIR"
fi

# Ensure Bridge Command is installed (binary check)
if [ ! -x "$BC_DATA/bridgecommand/bridgecommand" ]; then
    echo "ERROR: Bridge Command binary not found."
    # Attempt to locate it or fail
    if [ -x "/opt/bridgecommand/bridgecommand" ]; then
        echo "Found at /opt/bridgecommand/bridgecommand"
    else
        exit 1
    fi
fi

# Record initial file count in Scenarios directory
INITIAL_COUNT=$(find "$BC_DATA/Scenarios" -maxdepth 1 -type d | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_scenario_count.txt

# Create a dummy "reference" model list file for the agent to consult if they want
# (This helps simulating the 'exploration' aspect)
mkdir -p /home/ga/Documents
echo "Available Models Reference" > /home/ga/Documents/available_models_hint.txt
echo "Check /opt/bridgecommand/Models/ for valid vessel names." >> /home/ga/Documents/available_models_hint.txt

# Ensure permissions
chown -R ga:ga /home/ga/Documents

echo "=== Task setup complete ==="