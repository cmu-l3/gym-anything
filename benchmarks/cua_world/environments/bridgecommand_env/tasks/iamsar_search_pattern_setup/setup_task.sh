#!/bin/bash
echo "=== Setting up IAMSAR Search Pattern Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/s) SAR Expanding Square"

# Ensure clean state: Remove scenario if it exists
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# Remove document if exists
rm -f "/home/ga/Documents/search_action_plan.txt"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Ensure Bridge Command directory permissions
# The agent needs to write to Scenarios
if [ -d "$BC_DATA/Scenarios" ]; then
    chmod 777 "$BC_DATA/Scenarios"
fi

# Setup display for Bridge Command (standard practice, though not strictly required for file editing)
# We don't launch the app here to let the agent decide when/how to verify their work
# But we ensure the environment variable is set for any tools they might use
export DISPLAY=:1

# Take initial screenshot of the desktop/environment
if command -v scrot &> /dev/null; then
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Setup complete ==="
echo "Task: Create Expanding Square Search scenario starting at 50° 35.00' N, 001° 20.00' W"
echo "Target directory: $SCENARIO_DIR"