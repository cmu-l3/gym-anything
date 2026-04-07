#!/bin/bash
echo "=== Setting up Fisheries Patrol Exercise ==="

# Bridge Command paths
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/p) Solent Fisheries Patrol"
DOCS_DIR="/home/ga/Documents"

# 1. Clean up previous run artifacts
echo "Cleaning previous scenario and documents..."
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$DOCS_DIR/fisheries_patrol_briefing.txt" 2>/dev/null || true

# 2. Reset Configuration to defaults (to ensure agent actually changes them)
echo "Resetting bc5.ini configuration..."
# We reset both the user config and the install dir config to be safe
CONFIG_DIRS=("/home/ga/.config/Bridge Command" "$BC_DATA" "/home/ga/.Bridge Command/5.10")

for DIR in "${CONFIG_DIRS[@]}"; do
    if [ -f "$DIR/bc5.ini" ]; then
        # Reset specific keys to "wrong" defaults so we can verify the agent changed them
        sed -i 's/^arpa_on=.*/arpa_on=0/' "$DIR/bc5.ini" 2>/dev/null || true
        sed -i 's/^full_radar=.*/full_radar=0/' "$DIR/bc5.ini" 2>/dev/null || true
        sed -i 's/^radar_range_resolution=.*/radar_range_resolution=64/' "$DIR/bc5.ini" 2>/dev/null || true
        sed -i 's/^max_radar_range=.*/max_radar_range=24/' "$DIR/bc5.ini" 2>/dev/null || true
        sed -i 's/^radar_angular_resolution=.*/radar_angular_resolution=360/' "$DIR/bc5.ini" 2>/dev/null || true
    fi
done

# 3. Ensure directories exist
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 4. Record start time for anti-gaming (timestamp verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 5. Launch Bridge Command Launcher (the agent needs this to edit settings/verify scenario)
echo "Launching Bridge Command..."
# Kill any existing instance
pkill -f "bridgecommand" 2>/dev/null || true
sleep 2

# Launch
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_launch.log 2>&1 &"

# Wait for window
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
        echo "Bridge Command window detected."
        break
    fi
    sleep 1
done

# Focus window
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="