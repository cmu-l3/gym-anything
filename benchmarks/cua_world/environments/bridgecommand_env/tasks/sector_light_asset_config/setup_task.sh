#!/bin/bash
echo "=== Setting up sector_light_asset_config task ==="

BC_DATA="/opt/bridgecommand"
MODEL_DIR="$BC_DATA/Models/Othership/SectorLight"
SCENARIO_DIR="$BC_DATA/Scenarios/Sector_Light_Test"

# 1. Clean up any previous attempts (Anti-gaming/Reset state)
if [ -d "$MODEL_DIR" ]; then
    echo "Removing existing SectorLight model directory..."
    rm -rf "$MODEL_DIR"
fi

if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing verification scenario..."
    rm -rf "$SCENARIO_DIR"
fi

# 2. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Ensure permissions allow agent to create files
# The agent user 'ga' owns /opt/bridgecommand from the env setup, 
# but let's double check to avoid permission errors.
chown -R ga:ga "$BC_DATA"

# 4. Launch Bridge Command to establish "Starting State"
# The agent is expected to interact with the file system, but having the app open 
# initially is the standard starting state.
echo "Starting Bridge Command..."
pkill -f "bridgecommand" 2>/dev/null || true
sleep 1

# Must run from BC data dir
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_setup.log 2>&1 &"
sleep 5

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="