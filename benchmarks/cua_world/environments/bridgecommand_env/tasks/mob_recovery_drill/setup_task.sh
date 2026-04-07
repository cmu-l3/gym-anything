#!/bin/bash
echo "=== Setting up MOB Recovery Drill Task ==="

BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"
BC_USER_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
BC_SYSTEM_CONFIG="$BC_DATA/bc5.ini"
SCENARIO_DIR="$BC_DATA/Scenarios/o) MOB Recovery Drill"

# 1. Clean up previous run artifacts
echo "Cleaning previous scenario artifacts..."
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f /home/ga/Documents/mob_drill_procedures.txt 2>/dev/null || true

# 2. Reset Configuration to a "baseline" state (so we can verify changes)
# We set radar settings to known incorrect values to verify the agent fixes them
echo "Resetting configuration..."
mkdir -p "$(dirname "$BC_USER_CONFIG")"
cp /workspace/config/bc5.ini "$BC_USER_CONFIG"

# Set baseline values (arpa_on=0, max_radar_range=24) to ensure agent must edit them
sed -i 's/^arpa_on=.*/arpa_on=0/' "$BC_USER_CONFIG"
sed -i 's/^full_radar=.*/full_radar=0/' "$BC_USER_CONFIG"
sed -i 's/^max_radar_range=.*/max_radar_range=24/' "$BC_USER_CONFIG"
sed -i 's/^hide_instruments=.*/hide_instruments=1/' "$BC_USER_CONFIG"

# Sync to system config location as BC reads both
cp "$BC_USER_CONFIG" "$BC_SYSTEM_CONFIG" 2>/dev/null || true
chown -R ga:ga "/home/ga/.config/Bridge Command"
chown ga:ga "$BC_SYSTEM_CONFIG" 2>/dev/null || true

# 3. Create Documents directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 4. Record Task Start Time (Critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 5. Launch Bridge Command Launcher (Agent needs to see available worlds/models)
# We launch it but don't start a simulation, just the menu/launcher
echo "Launching Bridge Command..."
if ! pgrep -f "bridgecommand" > /dev/null; then
    su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
            echo "Bridge Command window detected"
            break
        fi
        sleep 1
    done
fi

# Focus and maximize
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true

# 6. Capture Initial State Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="