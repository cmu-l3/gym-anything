#!/bin/bash
echo "=== Setting up IMO Maneuvering Trials Task ==="

# Define paths
BC_DATA="/opt/bridgecommand"
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
SCENARIOS_ROOT="$BC_DATA/Scenarios"
TRIALS_DIR="$SCENARIOS_ROOT/Sea Trials"

# 1. Clean up any previous run artifacts
rm -rf "$TRIALS_DIR" 2>/dev/null || true
rm -f /home/ga/Documents/trials_plan.txt 2>/dev/null || true

# 2. Reset bc5.ini to known state (track_history=0)
# This ensures the agent MUST actively change it to pass.
mkdir -p "$BC_CONFIG_DIR"
if [ -f /workspace/config/bc5.ini ]; then
    cp /workspace/config/bc5.ini "$BC_CONFIG_DIR/bc5.ini"
else
    # Fallback if template missing
    touch "$BC_CONFIG_DIR/bc5.ini"
fi

# Ensure track_history is OFF initially
if grep -q "track_history" "$BC_CONFIG_DIR/bc5.ini"; then
    sed -i 's/^track_history=.*/track_history=0/' "$BC_CONFIG_DIR/bc5.ini"
else
    echo "track_history=0" >> "$BC_CONFIG_DIR/bc5.ini"
fi

# Also update the binary location config to match
cp "$BC_CONFIG_DIR/bc5.ini" "$BC_DATA/bc5.ini" 2>/dev/null || true

# Set permissions
chown -R ga:ga "$BC_CONFIG_DIR"
chown -R ga:ga /home/ga/Documents

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Ensure Bridge Command is NOT running (agent must start it if they want to test)
pkill -f "bridgecommand" 2>/dev/null || true

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="